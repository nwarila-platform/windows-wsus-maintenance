#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# A run can be terminated at any point, by a reboot or by the task's time limit. Each test stops a
#   stage part-way, the way termination does (nothing after that point runs), and then runs the
#   stage again as the next night would: the second run finishes exactly the work that was left,
#   touches nothing twice and finds no half-applied change (REQ-096).

Describe 'Interrupted runs' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # The stage context's run start (2026-11-02 01:00 local time) in UTC: the reference for ages.
    $script:Now = [System.DateTime]::new(2026, 11, 2, 1, 0, 0).ToUniversalTime()

    Function script:New-Context {
      Param ($Database = $Null, $Server = $Null, [System.String]$Extra = '', [System.String]$Stage = 'Stage')
      $Context = New-FakeStageContext -Database $Database -UpdateServer $Server -Extra $Extra -Log $script:Log
      $Context.StageName = $Stage
      $Context | Add-Member -NotePropertyName Events -NotePropertyValue ([PSCustomObject]@{ Name = 'channel' }) -Force
      $Context
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    Mock -CommandName New-WsusAdministrationObject -MockWith { New-FakeWsusObject -TypeName $TypeName }
    Mock -CommandName Write-MaintenanceEvent -MockWith { }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'

    # The item-by-item stages log progress after every item, and check the time budget before
    #   each item or batch; either point can be where the run is terminated.
    $script:ItemsLeft = [System.Int32]::MaxValue
    $script:ChecksLeft = [System.Int32]::MaxValue
    Mock -CommandName Write-MaintenanceProgress -MockWith {
      $script:ItemsLeft--
      If ($script:ItemsLeft -le 0) { Throw 'The run was terminated.' }
    }
    Mock -CommandName Test-MaintenanceBudget -MockWith {
      $script:ChecksLeft--
      If ($script:ChecksLeft -lt 0) { Throw 'The run was terminated.' }
      $False
    }
  }

  It 'resumes obsolete-update deletion from what remains' {
    $State = @{ Left = [System.Collections.Generic.List[System.Int32]]::new([System.Int32[]]@(101, 102, 103, 104, 105)); Deleted = [System.Collections.Generic.List[System.Int32]]::new() }
    $Responder = {
      Param ($Text, $Parameters, $NonQuery)
      If ($NonQuery) {
        $Null = $State.Left.Remove([System.Int32]$Parameters['@localUpdateID'])
        $State.Deleted.Add([System.Int32]$Parameters['@localUpdateID'])
        1
      } Else {
        ForEach ($Identifier In $State.Left.ToArray()) { [PSCustomObject]@{ LocalUpdateID = $Identifier } }
      }
    }.GetNewClosure()
    $Database = New-FakeSqlConnection -Responder $Responder
    $script:ItemsLeft = 2

    { Invoke-ObsoleteUpdateCleanup -Context (New-Context -Database $Database) } | Should -Throw -ExpectedMessage 'The run was terminated.'
    $State.Deleted | Should -Be @(101, 102)

    $script:ItemsLeft = [System.Int32]::MaxValue
    $Again = Invoke-ObsoleteUpdateCleanup -Context (New-Context -Database $Database)

    $Again.Status | Should -Be 'Success'
    $Again.Counts['Found'] | Should -Be 3
    $State.Deleted | Should -Be @(101, 102, 103, 104, 105)
  }

  It 'declines on the next run only the superseded updates the interrupted run did not reach' {
    $Server = New-FakeUpdateServer -Updates @(
      New-FakeUpdate -Title 'Old one' -Kb @('5000001') -Superseded $True -Created $script:Now.AddDays(-200)
      New-FakeUpdate -Title 'Old two' -Kb @('5000002') -Superseded $True -Created $script:Now.AddDays(-150)
      New-FakeUpdate -Title 'Old three' -Kb @('5000003') -Superseded $True -Created $script:Now.AddDays(-120)
    )
    $script:ItemsLeft = 1

    { Invoke-SupersededDecline -Context (New-Context -Server $Server -Stage 'SupersededDecline') } | Should -Throw -ExpectedMessage 'The run was terminated.'
    $Server.State.DeclinedUpdates | Should -Be @('Old one')

    $script:ItemsLeft = [System.Int32]::MaxValue
    $Again = Invoke-SupersededDecline -Context (New-Context -Server $Server -Stage 'SupersededDecline')

    $Again.Counts['Declined'] | Should -Be 2
    $Server.State.DeclinedUpdates | Should -Be @('Old one', 'Old two', 'Old three')
  }

  It 'deletes on the next run only the declined updates the interrupted run did not reach' {
    $Server = New-FakeUpdateServer -Updates @(
      New-FakeUpdate -Title 'Declined one' -Declined $True
      New-FakeUpdate -Title 'Declined two' -Declined $True
      New-FakeUpdate -Title 'Declined three' -Declined $True
    )
    $script:ItemsLeft = 2

    { Remove-DeclinedUpdate -Context (New-Context -Server $Server -Extra ', "declinedDeletion": { "enabled": true }' -Stage 'DeclinedDeletion') } | Should -Throw -ExpectedMessage 'The run was terminated.'
    $Server.State.DeletedUpdates | Should -Be @('Declined one', 'Declined two')

    $script:ItemsLeft = [System.Int32]::MaxValue
    $Again = Remove-DeclinedUpdate -Context (New-Context -Server $Server -Extra ', "declinedDeletion": { "enabled": true }' -Stage 'DeclinedDeletion')

    $Again.Counts['Found'] | Should -Be 1
    $Server.State.DeletedUpdates | Should -Be @('Declined one', 'Declined two', 'Declined three')
  }

  It 'approves on the next run what the interrupted run did not reach, and nothing twice' {
    $Server = New-FakeUpdateServer -Groups @('Pilot') -Updates @(
      New-FakeUpdate -Title 'First' -Kb @('5000101') -Needed 2 -Created $script:Now.AddDays(-20) -Local $True
      New-FakeUpdate -Title 'Second' -Kb @('5000102') -Needed 2 -Created $script:Now.AddDays(-20) -Local $True
      New-FakeUpdate -Title 'Third' -Kb @('5000103') -Needed 2 -Created $script:Now.AddDays(-20) -Local $True
    )
    $Approval = ', "approval": { "enabled": true, "groups": [ { "name": "Pilot", "delayDays": 7 } ] }'
    $script:ItemsLeft = 1

    { Invoke-DeferredApproval -Context (New-Context -Server $Server -Extra $Approval -Stage 'DeferredApproval') } | Should -Throw -ExpectedMessage 'The run was terminated.'
    $Server.State.Approvals | Should -HaveCount 1

    $script:ItemsLeft = [System.Int32]::MaxValue
    $Again = Invoke-DeferredApproval -Context (New-Context -Server $Server -Extra $Approval -Stage 'DeferredApproval')

    $Again.Counts['Approved'] | Should -Be 2
    $Again.Counts['AlreadyApproved'] | Should -Be 1
    @($Server.State.ApprovalLog | Select-Object -Unique) | Should -HaveCount 3
    $Server.State.ApprovalLog | Should -HaveCount 3
  }

  It 're-evaluates stale computers on the next run and removes only those still there' {
    $Cutoff = $script:Now.AddDays(-90)
    $Computers = @(
      For ($Index = 1; $Index -le 40; $Index++) { New-FakeComputer -Name ('fresh{0:D2}.example' -f $Index) -LastSync $Cutoff.AddDays(1) }
      New-FakeComputer -Name 'a.example' -LastSync $Cutoff.AddDays(-200)
      New-FakeComputer -Name 'b.example' -LastSync $Cutoff.AddDays(-100)
      New-FakeComputer -Name 'c.example' -LastSync $Cutoff.AddDays(-1)
    )
    $Server = New-FakeUpdateServer -Computers $Computers
    $script:ItemsLeft = 1

    { Invoke-StaleComputerCleanup -Context (New-Context -Server $Server -Stage 'StaleComputers') } | Should -Throw -ExpectedMessage 'The run was terminated.'
    $Server.State.Deleted | Should -HaveCount 1

    $script:ItemsLeft = [System.Int32]::MaxValue
    $Again = Invoke-StaleComputerCleanup -Context (New-Context -Server $Server -Stage 'StaleComputers')

    $Again.Status | Should -Be 'Success'
    @($Server.State.Deleted | Sort-Object) | Should -Be @('a.example', 'b.example', 'c.example')
    $Server.State.Computers | Should -HaveCount 40
  }

  It 'removes on the next run the synchronization history the interrupted run left, batch by batch' {
    $State = @{ Left = [System.Int64]25000 }
    $Responder = {
      Param ($Text, $Parameters, $NonQuery)
      If ($NonQuery) {
        $Removed = [System.Math]::Min($State.Left, [System.Int64]$Parameters['@batch'])
        $State.Left = $State.Left - $Removed
        $Removed
      } ElseIf ($Text -match 'COL_LENGTH') {
        [PSCustomObject]@{ Length = 8 }
      } ElseIf ($Text -match 'COUNT_BIG') {
        [PSCustomObject]@{ Total = $State.Left }
      }
    }.GetNewClosure()
    $Database = New-FakeSqlConnection -Responder $Responder
    $script:ChecksLeft = 1

    { Remove-SyncHistory -Context (New-Context -Database $Database) } | Should -Throw -ExpectedMessage 'The run was terminated.'
    $State.Left | Should -Be 15000

    $script:ChecksLeft = [System.Int32]::MaxValue
    $Again = Remove-SyncHistory -Context (New-Context -Database $Database)

    $Again.Counts['Matched'] | Should -Be 15000
    $Again.Counts['Removed'] | Should -Be 15000
    $State.Left | Should -Be 0
  }

  It 'deletes on the next run the old IIS log files the interrupted run did not reach' {
    $Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path $Folder
    ForEach ($Name In @('u_ex250101.log', 'u_ex250102.log', 'u_ex250103.log', 'u_ex261101.log')) {
      $Path = Join-Path -Path $Folder -ChildPath $Name
      [System.IO.File]::WriteAllText($Path, 'x')
      [System.IO.File]::SetLastWriteTimeUtc($Path, $script:Now.AddDays($(If ($Name -eq 'u_ex261101.log') { -1 } Else { -300 })))
    }
    $Extra = ', "iisLogs": { "folder": "' + $Folder.Replace('\', '\\') + '" }'
    $script:ChecksLeft = 1

    { Remove-IisLogFile -Context (New-Context -Extra $Extra -Stage 'IisLogRetention') } | Should -Throw -ExpectedMessage 'The run was terminated.'
    @([System.IO.Directory]::GetFiles($Folder)) | Should -HaveCount 3

    $script:ChecksLeft = [System.Int32]::MaxValue
    $Again = Remove-IisLogFile -Context (New-Context -Extra $Extra -Stage 'IisLogRetention')

    $Again.Counts['Deleted'] | Should -Be 2
    @([System.IO.Directory]::GetFiles($Folder) | ForEach-Object -Process { [System.IO.Path]::GetFileName($PSItem) }) | Should -Be @('u_ex261101.log')
  }

  It 'creates on the next run only the custom index an interrupted run did not create' {
    # The index and its tag are one transaction, so after a termination an index exists with its
    #   tag or not at all: here the first index was finished and the second never started.
    $State = @{ nclLocalizedPropertyID = 1; nclSupercededUpdateID = 0 }
    $Responder = {
      Param ($Text, $Parameters, $NonQuery)
      If ($NonQuery) {
        $State[$Parameters['@name']] = 1
        -1
      } Else {
        [PSCustomObject]@{ TableExists = 1; IndexExists = $State[$Parameters['@name']]; CreatedByScript = $State[$Parameters['@name']] }
      }
    }.GetNewClosure()
    $Database = New-FakeSqlConnection -Responder $Responder

    $Again = Set-SusdbCustomIndex -Context (New-Context -Database $Database)

    $Again.Items | Should -Be @('nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision: already present', 'nclSupercededUpdateID on dbo.tbRevisionSupersedesUpdate: created')
    @($Database.Commands | Where-Object -FilterScript { $PSItem.CommandText -like 'SET XACT_ABORT ON;*' }) | Should -HaveCount 1
    $State['nclSupercededUpdateID'] | Should -Be 1
  }

  It 'replaces the partial backup file of an interrupted backup, keeping one file for the day' {
    $Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path $Folder
    [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath 'SUSDB_20261102.bak'), 'par')
    $Responder = {
      Param ($Text, $Parameters, $NonQuery)
      If ($NonQuery) {
        [System.IO.File]::WriteAllText($Parameters['@path'], ('b' * 10))
        -1
      } Else {
        [PSCustomObject]@{ Edition = 'Express Edition (64-bit)'; ReservedBytes = [System.Int64]1048576 }
      }
    }
    $Database = New-FakeSqlConnection -Responder $Responder
    Mock -CommandName Get-BackupDestinationSpace -MockWith { [System.Int64]100GB }
    Mock -CommandName Test-MaintenanceAclSupport -MockWith { $False }
    $Context = New-Context -Database $Database
    $Context.Configuration.backup.destination = $Folder

    $Again = Backup-Susdb -Context $Context

    $Again.Status | Should -Be 'Success'
    @($Database.Commands | Where-Object -FilterScript { $PSItem.CommandText -like 'BACKUP DATABASE*WITH CHECKSUM, INIT,*' }) | Should -HaveCount 1
    @([System.IO.Directory]::GetFiles($Folder)) | Should -HaveCount 1
    (Get-Item -LiteralPath (Join-Path -Path $Folder -ChildPath 'SUSDB_20261102.bak')).Length | Should -Be 10
  }
}
