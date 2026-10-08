#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Synchronization guard' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    Function script:New-Configuration {
      Param ([System.String]$Extra = '')
      $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }, "syncGuard": { "pollIntervalSeconds": 10, "waitSeconds": 25, "retryDelaySeconds": 60, "maxAttempts": 2 }' + $Extra + ' }'
      Get-FakeConfiguration -Json $Json
    }
  }

  BeforeEach {
    $script:Waits = [System.Collections.Generic.List[System.Int32]]::new()
    Mock -CommandName Wait-MaintenanceInterval -MockWith { $script:Waits.Add($Seconds) }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  Context 'Invoke-SynchronizationGuard' {
    It 'passes at once when no synchronization runs, and later restarts nothing (REQ-044 c)' {
      $Server = New-FakeUpdateServer -Statuses @('NotProcessing')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration) -UpdateServer $Server -Log $script:Log
      $Restore = Restore-Synchronization -Guard $Guard -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeTrue
      $Guard.Found | Should -BeFalse
      $Guard.StopRequested | Should -BeFalse
      $Guard.Summary | Should -Be 'not running'
      $script:Waits | Should -HaveCount 0
      $Restore.Restarted | Should -BeFalse
      $Server.State.StartCalls | Should -Be 0
      $Restore.Summary | Should -Be 'not running'
    }

    It 'stops a running synchronization, polling until it stops, and restarts it afterwards (REQ-044 a)' {
      $Server = New-FakeUpdateServer -Statuses @('Running', 'Stopping', 'NotProcessing')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration) -UpdateServer $Server -Log $script:Log
      $Restore = Restore-Synchronization -Guard $Guard -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeTrue
      $Guard.Found | Should -BeTrue
      $Guard.StopRequested | Should -BeTrue
      $Server.State.StopCalls | Should -Be 1
      $script:Waits | Should -Be @(10, 10)
      $Guard.Summary | Should -Be 'running at start; stopped by the run (attempt 1)'
      $Restore.Restarted | Should -BeTrue
      $Server.State.StartCalls | Should -Be 1
      $Restore.Summary | Should -Be 'running at start; stopped by the run (attempt 1); restarted after the run'
      $Restore.Notices | Should -HaveCount 0
      $Log = Get-Content -LiteralPath $script:Log.Path -Raw
      $Log | Should -Match 'Synchronization status at start: Running\.'
      $Log | Should -Match 'Synchronization guard attempt 1: stop requested\.'
      $Log | Should -Match 'Synchronization restarted\.'
    }

    It 'gives up after the configured attempts when the synchronization never stops (REQ-044 b)' {
      $Server = New-FakeUpdateServer -Statuses @('Running')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration) -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeFalse
      $Guard.Attempts | Should -Be 2
      $Server.State.StopCalls | Should -Be 2
      $script:Waits | Should -Be @(10, 10, 5, 60, 10, 10, 5)
      $Guard.Summary | Should -Be 'Running at start; still Running after 2 attempt(s)'
      (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Synchronization guard attempt 2 of 2 failed; status Running\.'
    }

    It 'counts a status it does not recognize as a failed attempt' {
      $Server = New-FakeUpdateServer -Statuses @('Paused', 'NotProcessing')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration) -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeTrue
      $Guard.Attempts | Should -Be 2
      $script:Waits | Should -Be @(60)
      $Server.State.StopCalls | Should -Be 0
      (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Synchronization status Paused is not recognized; the attempt counts as failed\.'
    }

    It 'waits for a synchronization that is already stopping, without stopping or restarting it' {
      $Server = New-FakeUpdateServer -Statuses @('Stopping', 'NotProcessing')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration) -UpdateServer $Server -Log $script:Log
      $Restore = Restore-Synchronization -Guard $Guard -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeTrue
      $Guard.StopRequested | Should -BeFalse
      $Guard.Summary | Should -Be 'Stopping at start; finished before the stages'
      $Server.State.StartCalls | Should -Be 0
      $Restore.Restarted | Should -BeFalse
    }

    It 'only observes in a dry run' {
      $Server = New-FakeUpdateServer -Statuses @('Running')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration -Extra ', "run": { "dryRun": true }, "syncGuard": { "suspendSchedule": true }') -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeTrue
      $Guard.Found | Should -BeTrue
      $Guard.ScheduleSuspended | Should -BeFalse
      $Server.State.StopCalls | Should -Be 0
      $Server.State.Saves | Should -Be 0
      $Guard.Summary | Should -Be 'Running at start; left alone (dry run)'
    }

    It 'suspends the automatic schedule for the run and restores it' {
      $Server = New-FakeUpdateServer -Statuses @('NotProcessing')

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration -Extra ', "syncGuard": { "suspendSchedule": true }') -UpdateServer $Server -Log $script:Log
      $AfterGuard = $Server.Subscription.SynchronizeAutomatically
      $Restore = Restore-Synchronization -Guard $Guard -UpdateServer $Server -Log $script:Log

      $Guard.ScheduleSuspended | Should -BeTrue
      $AfterGuard | Should -BeFalse
      $Guard.Summary | Should -Be 'not running; automatic synchronization suspended for the run'
      $Restore.ScheduleRestored | Should -BeTrue
      $Server.Subscription.SynchronizeAutomatically | Should -BeTrue
      $Server.State.Saves | Should -Be 2
      $Restore.Summary | Should -Be 'not running; automatic synchronization suspended for the run; automatic synchronization restored'
    }

    It 'leaves a schedule that was already off alone' {
      $Server = New-FakeUpdateServer -SynchronizeAutomatically $False

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration -Extra ', "syncGuard": { "suspendSchedule": true }') -UpdateServer $Server -Log $script:Log

      $Guard.ScheduleSuspended | Should -BeFalse
      $Server.State.Saves | Should -Be 0
    }

    It 'fails when the status cannot be read' {
      $Server = [PSCustomObject]@{}
      $Server | Add-Member -MemberType ScriptMethod -Name GetSubscription -Value { Throw 'The WSUS service is not responding.' }

      $Guard = Invoke-SynchronizationGuard -Configuration (New-Configuration) -UpdateServer $Server -Log $script:Log

      $Guard.Succeeded | Should -BeFalse
      $Guard.Error | Should -Be 'The WSUS service is not responding.'
      $Guard.Summary | Should -Be 'not established: The WSUS service is not responding.'
    }
  }

  Context 'Restore-Synchronization' {
    It 'leaves a synchronization that is still running alone' {
      $Server = New-FakeUpdateServer -Statuses @('Running')
      $Guard = [PSCustomObject]@{ StopRequested = $True; ScheduleSuspended = $False; Summary = 'Running at start; still Running after 2 attempt(s)' }

      $Restore = Restore-Synchronization -Guard $Guard -UpdateServer $Server -Log $script:Log

      $Restore.Restarted | Should -BeFalse
      $Server.State.StartCalls | Should -Be 0
      $Restore.Summary | Should -Be 'Running at start; still Running after 2 attempt(s); not restarted: status Running'
    }

    It 'raises a warning when the restart or the schedule restore fails' {
      $Server = New-FakeUpdateServer -StartFails $True -SaveFails $True
      $Guard = [PSCustomObject]@{ StopRequested = $True; ScheduleSuspended = $True; Summary = 's' }

      $Restore = Restore-Synchronization -Guard $Guard -UpdateServer $Server -Log $script:Log

      $Restore.Notices.Severity | Should -Be @('Warning', 'Warning')
      $Restore.Notices[0].Message | Should -Be 'The synchronization the run stopped could not be restarted: The synchronization could not be started.'
      $Restore.Notices[1].Message | Should -Be 'The automatic synchronization schedule could not be switched back on: The subscription could not be saved.'
      $Restore.Summary | Should -Be 's; restart failed: The synchronization could not be started.; automatic synchronization not restored: The subscription could not be saved.'
    }
  }
}
