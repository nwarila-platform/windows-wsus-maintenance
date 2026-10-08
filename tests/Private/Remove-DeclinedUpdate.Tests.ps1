#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Remove-DeclinedUpdate' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # Declined updates across classifications, one of them protected, and one update that is
    #   not declined.
    Function script:New-DeclinedFleet {
      @(
        New-FakeUpdate -Title 'Old driver' -Kb @() -Classification 'Drivers' -Declined $True
        New-FakeUpdate -Title 'Old security update' -Kb @('5000401') -Classification 'Security Updates' -Declined $True
        New-FakeUpdate -Title 'Protected update' -Kb @('5000402') -Classification 'Security Updates' -Declined $True
        New-FakeUpdate -Title 'Old feature pack' -Kb @('5000403') -Classification 'Feature Packs' -Declined $True
        New-FakeUpdate -Title 'Approved update' -Kb @('5000404') -Approved $True
      )
    }

    Function script:Invoke-Deletion {
      Param ($Server, [System.String]$Settings = '', [System.Boolean]$DryRun = $False, [System.String]$Declines = '')
      $Extra = ', "declinedDeletion": { "enabled": true' + $(If ($Settings -ne '') { ', ' + $Settings } Else { '' }) + ' }'
      If ($Declines -ne '') {
        $Extra = $Extra + ', "declines": { ' + $Declines + ' }'
      }
      $Context = New-FakeStageContext -UpdateServer $Server -Extra $Extra -DryRun $DryRun -Log $script:Log
      $Context.StageName = 'DeclinedDeletion'
      Remove-DeclinedUpdate -Context $Context
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    Mock -CommandName New-WsusAdministrationObject -MockWith { New-FakeWsusObject -TypeName $TypeName }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'deletes the declined updates except the protected ones' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet)

    $Result = Invoke-Deletion -Server $Server -Settings '"protected": [ "KB5000402" ]'

    $Result.Status | Should -Be 'Success'
    $Server.State.DeletedUpdates | Should -Be @('Old driver', 'Old security update', 'Old feature pack')
    $Result.Counts['Found'] | Should -Be 4
    $Result.Counts['Protected'] | Should -Be 1
    $Result.Counts['Deleted'] | Should -Be 3
    $Result.Items[1] | Should -Be 'deleted: Old security update (KB5000401, created 2026-01-01)'
    $Result.Message | Should -Be 'Deleted 3 of 4 declined update(s); 1 protected, 0 excluded by classification, 0 failed.'
    $Server.State.UpdateScopes[0].ApprovedStates | Should -Be 'Declined'
  }

  It 'deletes only declined updates in the included classifications, never those excluded' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet)

    $Result = Invoke-Deletion -Server $Server -Settings '"includedClassifications": [ "Drivers", "Feature Packs" ], "excludedClassifications": [ "Feature Packs" ]'

    $Server.State.DeletedUpdates | Should -Be @('Old driver')
    $Result.Counts['ExcludedByClassification'] | Should -Be 3
  }

  It 'deletes nothing further on a second run' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet)

    $Null = Invoke-Deletion -Server $Server -Settings '"protected": [ "5000402" ]'
    $Again = Invoke-Deletion -Server $Server -Settings '"protected": [ "5000402" ]'

    $Again.Counts['Deleted'] | Should -Be 0
    $Again.Counts['Found'] | Should -Be 1
  }

  It 'lists a failed deletion with its error, carries on and ends in error' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet) -FailingUpdates @('Old driver')

    $Result = Invoke-Deletion -Server $Server

    $Server.State.DeletedUpdates | Should -Be @('Old security update', 'Protected update', 'Old feature pack')
    $Result.Status | Should -Be 'Error'
    $Result.Items[-1] | Should -BeLike 'failed: Old driver (no Knowledge Base article, created 2026-01-01): *still referenced*'
    $Result.Notices[0].Severity | Should -Be 'Error'
  }

  It 'deletes nothing in a dry run and lists the pending deletions' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet)

    $Result = Invoke-Deletion -Server $Server -DryRun $True

    $Server.State.DeletedUpdates | Should -HaveCount 0
    $Result.Items[0] | Should -Be 'pending: Old driver (no Knowledge Base article, created 2026-01-01)'
    $Result.Message | Should -Be 'pending: 4 of 4 declined update(s) would be deleted; 0 protected, 0 excluded by classification.'
  }

  It 'stops between deletions when the time budget runs out' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet)
    $script:BudgetChecks = 0
    Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 1 }

    $Result = Invoke-Deletion -Server $Server

    $Server.State.DeletedUpdates | Should -Be @('Old driver')
    $Result.Status | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'Time budget reached after deleting 1 of 4 declined update(s); the rest are deleted on the next run.'
  }

  It 'deletes nothing and ends in error when <Case>' -ForEach @(
    @{ Case = 'the declined updates cannot be retrieved'; Failure = 'The operation has timed out.'; CultureFails = $False; Settings = ''; Message = 'nothing deleted: the declined updates could not be retrieved'; Notice = 'The declined updates could not be retrieved, so none was deleted: The operation has timed out. *' }
    @{ Case = 'classifications filter the deletion and the language cannot be set'; Failure = ''; CultureFails = $True; Settings = '"includedClassifications": [ "Drivers" ]'; Message = 'nothing deleted: the evaluation language could not be set'; Notice = 'No declined update was deleted: the evaluation language en could not be set (*), so the classification filters could not be applied reliably.' }
  ) {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet) -UpdatesFailure $Failure -CultureFails $CultureFails

    $Result = Invoke-Deletion -Server $Server -Settings $Settings

    $Server.State.DeletedUpdates | Should -HaveCount 0
    $Result.Status | Should -Be 'Error'
    $Result.Message | Should -Be $Message
    $Result.Notices[0].Message | Should -BeLike $Notice
  }

  It 'deletes without classification filters even when the language cannot be set' {
    $Server = New-FakeUpdateServer -Updates (New-DeclinedFleet) -CultureFails $True

    $Result = Invoke-Deletion -Server $Server

    $Result.Counts['Deleted'] | Should -Be 4
  }
}
