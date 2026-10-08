#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-StaleComputerCleanup' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # The stage context's run start is 2026-11-02 01:00 local time; the threshold is 90 days.
    $script:Cutoff = [System.DateTime]::new(2026, 11, 2, 1, 0, 0).ToUniversalTime().AddDays(-90)

    # 40 computers that synchronized recently, three stale ones (b, never synchronized; c; a)
    #   and one stale computer reported through a downstream server.
    Function script:New-Fleet {
      Param ([System.Int32]$Fresh = 40)
      For ($Index = 1; $Index -le $Fresh; $Index++) {
        New-FakeComputer -Name ('fresh{0:D2}.example' -f $Index) -LastSync $script:Cutoff.AddDays(1)
      }
      New-FakeComputer -Name 'c.example' -LastSync $script:Cutoff.AddDays(-1)
      New-FakeComputer -Name 'b.example' -LastSync ([System.DateTime]::MinValue)
      New-FakeComputer -Name 'a.example' -LastSync $script:Cutoff.AddDays(-200)
      New-FakeComputer -Name 'down.example' -LastSync $script:Cutoff.AddDays(-5) -Downstream $True
    }

    Function script:Invoke-Stale {
      Param ($Server, [System.String]$Settings = '', [System.String]$Tier = 'Autonomous', [System.Boolean]$DryRun = $False)
      $Extra = ''
      If ($Settings -ne '') {
        $Extra = ', "staleComputers": { ' + $Settings + ' }'
      }
      Invoke-StaleComputerCleanup -Context (New-FakeStageContext -UpdateServer $Server -Extra $Extra -Tier $Tier -DryRun $DryRun -Log $script:Log)
    }

    $script:Line = '{0} (last synchronized {1}, Windows Server 2022 Standard, client 10.0.20348.2700)'
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    $script:Scopes = [System.Collections.Generic.List[System.Object]]::new()
    Mock -CommandName New-WsusAdministrationObject -MockWith {
      $Scope = New-FakeWsusObject -TypeName $TypeName
      $script:Scopes.Add($Scope)
      $Scope
    }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'deletes the computers that have not synchronized within the threshold, listed by name' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet)

    $Result = Invoke-Stale -Server $Server

    $Result.Status | Should -Be 'Success'
    $Server.State.Deleted | Should -Be @('a.example', 'b.example', 'c.example')
    $Result.Items | Should -Be @(
      ('deleted: ' + ($script:Line -f 'a.example', ($script:Cutoff.AddDays(-200).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) + ' UTC')))
      ('deleted: ' + ($script:Line -f 'b.example', 'never'))
      ('deleted: ' + ($script:Line -f 'c.example', ($script:Cutoff.AddDays(-1).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture) + ' UTC')))
    )
    $Result.Counts['Total'] | Should -Be 43
    $Result.Counts['Selected'] | Should -Be 3
    $Result.Counts['Deleted'] | Should -Be 3
    $Result.Message | Should -Be 'Deleted 3 of 3 computer(s) not synchronized for 90 day(s) (of 43 in total); 0 failed.'
    $script:Scopes[1].ToLastSyncTime | Should -Be $script:Cutoff
    $script:Scopes[1].IncludeDownstreamComputerTargets | Should -BeFalse
    @(Get-Content -LiteralPath $script:Log.Path | Where-Object -FilterScript { $PSItem -like '*StaleComputers: Progress*' }) | Should -HaveCount 3
  }

  It 'includes computers reported through downstream servers when configured' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet)

    $Result = Invoke-Stale -Server $Server -Settings '"includeDownstream": true'

    $Server.State.Deleted | Should -Contain 'down.example'
    $Result.Counts['Total'] | Should -Be 44
    $script:Scopes[1].IncludeDownstreamComputerTargets | Should -BeTrue
  }

  It 'changes nothing and raises a High notice when <Case>' -ForEach @(
    @{ Case = 'more computers than the guard count are selected'; Fresh = 40; Settings = '"guardCount": 2' }
    @{ Case = 'a larger share than the guard percentage is selected'; Fresh = 5; Settings = '' }
  ) {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet -Fresh $Fresh)

    $Result = Invoke-Stale -Server $Server -Settings $Settings

    $Server.State.Deleted | Should -HaveCount 0
    $Result.Status | Should -Be 'Warning'
    $Result.Counts['GuardExceeded'] | Should -Be 1
    $Result.Message | Should -Be ('guard exceeded: 3 of {0} computer(s) selected; nothing was changed' -f ($Fresh + 3))
    $Result.Items[0] | Should -BeLike 'not changed (guard): a.example (*'
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'High'
    $Result.Notices[0].Message | Should -BeLike ('3 of {0} computer(s) have not synchronized for 90 day(s), more than staleComputers.guardCount (*) or staleComputers.guardPercent (10%) allows, so none was changed.*' -f ($Fresh + 3))
  }

  It 'processes a selection beyond the guard with a Warning notice when the override is set' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet)

    $Result = Invoke-Stale -Server $Server -Settings '"guardCount": 2, "override": true'

    $Server.State.Deleted | Should -HaveCount 3
    $Result.Status | Should -Be 'Success'
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'The stale-computer guard was exceeded (3 of 43 computer(s) selected) and staleComputers.override is set, so the selection is processed.'
  }

  It 'moves the stale computers into the target group, leaving out those already in it' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet) -Groups @('Stale Computers')
    $Server.State.Groups[0].Members.Add(@($Server.State.Computers | Where-Object -FilterScript { $PSItem.FullDomainName -eq 'b.example' })[0])

    $Result = Invoke-Stale -Server $Server -Settings '"action": "Move", "targetGroup": "stale computers"'

    $Server.State.Added | Should -Be @('Stale Computers:a.example', 'Stale Computers:c.example')
    $Server.State.Deleted | Should -HaveCount 0
    $Result.Counts['Moved'] | Should -Be 2
    $Result.Items[0] | Should -BeLike 'moved to Stale Computers: a.example (*'
    $Result.Message | Should -Be 'Moved 2 of 2 computer(s) not synchronized for 90 day(s) (of 43 in total) to Stale Computers; 0 failed.'
  }

  It 'changes nothing and ends in error when the target group does not exist' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet) -Groups @('Pilot')

    $Result = Invoke-Stale -Server $Server -Settings '"action": "Move", "targetGroup": "Stale Computers"'

    $Server.State.Added | Should -HaveCount 0
    $Result.Status | Should -Be 'Error'
    $Result.Message | Should -Be 'target group missing; nothing was changed'
    $Result.Notices[0].Severity | Should -Be 'Error'
    $Result.Notices[0].Message | Should -Be "Stale computers were not moved: the computer group 'Stale Computers' does not exist. Create it, or change staleComputers.targetGroup."
  }

  It 'records a computer it cannot delete and carries on' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet) -FailingComputers @('b.example')

    $Result = Invoke-Stale -Server $Server

    $Server.State.Deleted | Should -Be @('a.example', 'c.example')
    $Result.Status | Should -Be 'Error'
    $Result.Counts['Failed'] | Should -Be 1
    $Result.Items[-1] | Should -BeLike 'failed: b.example (*): *could not be deleted*'
    $Result.Notices[0].Severity | Should -Be 'Error'
    $Result.Notices[0].Message | Should -BeLike '1 stale computer(s) could not be handled. First failure: failed: b.example*'
    (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Error\s+\[RUN\] StaleComputers: failed: b\.example'
  }

  It 'stops at the first refusal on a replica and reports it as rejected by server role' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet) -FailingComputers @('a.example', 'b.example')

    $Result = Invoke-Stale -Server $Server -Tier 'Replica'

    $Server.State.Deleted | Should -HaveCount 0
    $Result.Status | Should -Be 'Warning'
    $Result.Message | Should -Be 'rejected by server role'
    $Result.Notices[0].Message | Should -BeLike 'The change to stale computers was refused, as expected on a replica (rejected by server role): *'
  }

  It 'stops between computers when the time budget runs out' {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet)
    $script:BudgetChecks = 0
    Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 1 }

    $Result = Invoke-Stale -Server $Server

    $Server.State.Deleted | Should -Be @('a.example')
    $Result.Status | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'Time budget reached after 1 of 3 stale computer(s); the rest are handled on the next run.'
  }

  It 'changes nothing in a dry run and marks the list as a simulation, for <Action>' -ForEach @(
    @{ Action = 'Delete'; Settings = ''; Item = 'simulation, would delete: a.example (*'; Message = 'Simulation: would delete 3 computer(s) not synchronized for 90 day(s) (of 43 in total); nothing was changed.' }
    @{ Action = 'Move'; Settings = '"action": "Move", "targetGroup": "Stale Computers"'; Item = 'simulation, would move to Stale Computers: a.example (*'; Message = 'Simulation: would move 3 computer(s) not synchronized for 90 day(s) (of 43 in total) to Stale Computers; nothing was changed.' }
  ) {
    $Server = New-FakeUpdateServer -Computers @(New-Fleet) -Groups @('Stale Computers')

    $Result = Invoke-Stale -Server $Server -Settings $Settings -DryRun $True

    $Server.State.Deleted | Should -HaveCount 0
    $Server.State.Added | Should -HaveCount 0
    $Result.Items[0] | Should -BeLike $Item
    $Result.Message | Should -Be $Message
  }

  It 'succeeds with nothing to do when no computer is stale' {
    $Server = New-FakeUpdateServer -Computers @(New-FakeComputer -Name 'fresh.example' -LastSync $script:Cutoff.AddDays(1))

    $Result = Invoke-Stale -Server $Server

    $Result.Status | Should -Be 'Success'
    $Result.Message | Should -Be 'Deleted 0 of 0 computer(s) not synchronized for 90 day(s) (of 1 in total); 0 failed.'
  }
}
