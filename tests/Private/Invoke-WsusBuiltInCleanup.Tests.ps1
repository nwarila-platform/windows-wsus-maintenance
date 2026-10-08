#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-WsusBuiltInCleanup' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    $script:Flags = @('DeclineSupersededUpdates', 'DeclineExpiredUpdates', 'CleanupObsoleteUpdates', 'CompressUpdates', 'CleanupObsoleteComputers', 'CleanupUnneededContentFiles')

    # The one option each recorded cleanup scope selected, in call order.
    Function script:Get-ScopeOption {
      Param ($Server)
      ForEach ($Scope In $Server.State.CleanupScopes) {
        @($script:Flags | Where-Object -FilterScript { $Scope.$PSItem -eq $True }) -join '+'
      }
    }

    Function script:Invoke-Cleanup {
      Param ($Server, [System.String]$Extra = '', [System.String]$Tier = 'Autonomous', [System.Boolean]$DryRun = $False)
      Invoke-WsusBuiltInCleanup -Context (New-FakeStageContext -UpdateServer $Server -Extra $Extra -Tier $Tier -DryRun $DryRun -Log $script:Log)
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    Mock -CommandName New-WsusAdministrationObject -MockWith { New-FakeWsusObject -TypeName $TypeName }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'runs each enabled option alone, in order, and keeps only that option''s counter' {
    $Server = New-FakeUpdateServer -Cleanup { Param ($Scope) New-FakeCleanupResult -Scope $Scope -All $True }

    $Result = Invoke-Cleanup -Server $Server

    $Result.Status | Should -Be 'Success'
    Get-ScopeOption -Server $Server | Should -Be @('DeclineSupersededUpdates', 'DeclineExpiredUpdates', 'CleanupObsoleteUpdates', 'CompressUpdates', 'CleanupUnneededContentFiles')
    $Result.Counts['SupersededUpdatesDeclined'] | Should -Be 4
    $Result.Counts['ExpiredUpdatesDeclined'] | Should -Be 1
    $Result.Counts['ObsoleteUpdatesDeleted'] | Should -Be 2
    $Result.Counts['UpdatesCompressed'] | Should -Be 3
    $Result.Counts['ObsoleteComputersDeleted'] | Should -Be 0
    $Result.Counts['DiskSpaceFreed'] | Should -Be 1610612736
    $Result.Counts['OptionsRun'] | Should -Be 5
    $Result.Counts['Attempts'] | Should -Be 5
    $Result.Items | Should -Be @(
      'superseded-update decline: 4 update(s) declined in 0.0 s (attempt 1)'
      'expired-update decline: 1 update(s) declined in 0.0 s (attempt 1)'
      'obsolete updates: 2 update(s) deleted in 0.0 s (attempt 1)'
      'obsolete update revisions: 3 update(s) with obsolete revisions removed in 0.0 s (attempt 1)'
      'obsolete computers: off'
      'unneeded content files: 1.5 GB freed in 0.0 s (attempt 1)'
    )
    $Result.Message | Should -Be 'Ran 5 of 5 built-in cleanup option(s); 0 failed; 1.5 GB freed. Unneeded content file cleanup also deletes update files imported manually from the Microsoft Update Catalog.'
    $Result.Notices | Should -HaveCount 0
    (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'BuiltInCleanup: obsolete updates: 2 update\(s\) deleted'
  }

  It 'runs only the options configuration enables' {
    $Server = New-FakeUpdateServer -Cleanup { Param ($Scope) New-FakeCleanupResult -Scope $Scope -All $True }
    $Extra = ', "builtInCleanup": { "declineSupersededUpdates": false, "declineExpiredUpdates": false, "obsoleteUpdates": false, "compressUpdates": true, "unneededContentFiles": false, "obsoleteComputers": true }'

    $Result = Invoke-Cleanup -Server $Server -Extra $Extra

    Get-ScopeOption -Server $Server | Should -Be @('CompressUpdates', 'CleanupObsoleteComputers')
    $Result.Counts['UpdatesCompressed'] | Should -Be 3
    $Result.Counts['ObsoleteComputersDeleted'] | Should -Be 5
    $Result.Counts['SupersededUpdatesDeclined'] | Should -Be 0
    $Result.Counts['DiskSpaceFreed'] | Should -Be 0
    $Result.Message | Should -Be 'Ran 2 of 2 built-in cleanup option(s); 0 failed; 0 bytes freed.'
  }

  It 'suppresses the decline options on a server whose role is <Tier>' -ForEach @(
    @{ Tier = 'Replica'; Reason = 'skipped: replica' }
    @{ Tier = 'Unknown'; Reason = 'skipped: server role unknown' }
  ) {
    $Server = New-FakeUpdateServer

    $Result = Invoke-Cleanup -Server $Server -Tier $Tier

    Get-ScopeOption -Server $Server | Should -Be @('CleanupObsoleteUpdates', 'CompressUpdates', 'CleanupUnneededContentFiles')
    $Result.Items[0] | Should -Be ('superseded-update decline: {0}' -f $Reason)
    $Result.Items[1] | Should -Be ('expired-update decline: {0}' -f $Reason)
    $Result.Status | Should -Be 'Success'
    $Result.Message | Should -BeLike 'Ran 3 of 3 built-in cleanup option(s)*'
  }

  It 'retries a time-out <Retries> time(s), then records the option as failed and runs the rest' -ForEach @(
    @{ Retries = 2 }
    @{ Retries = 0 }
  ) {
    $Server = New-FakeUpdateServer -Cleanup {
      Param ($Scope)
      If ($Scope.CompressUpdates) { Throw [System.TimeoutException]::new('The operation has timed out.') }
      New-FakeCleanupResult -Scope $Scope
    }

    $Result = Invoke-Cleanup -Server $Server -Extra (', "builtInCleanup": { "timeoutRetries": ' + $Retries + ' }')

    @(Get-ScopeOption -Server $Server | Where-Object -FilterScript { $PSItem -eq 'CompressUpdates' }) | Should -HaveCount ($Retries + 1)
    Get-ScopeOption -Server $Server | Select-Object -Last 1 | Should -Be 'CleanupUnneededContentFiles'
    $Result.Status | Should -Be 'Error'
    $Result.Counts['OptionsFailed'] | Should -Be 1
    $Result.Counts['Attempts'] | Should -Be (5 + $Retries)
    $Result.Items[3] | Should -BeLike ('obsolete update revisions: failed after {0} attempt(s): *timed out*' -f ($Retries + 1))
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Error'
    $Result.Notices[0].Message | Should -BeLike ('The built-in cleanup option obsolete update revisions failed after {0} attempt(s): *' -f ($Retries + 1))
    $Log = Get-Content -LiteralPath $script:Log.Path -Raw
    ([System.Text.RegularExpressions.Regex]::Matches($Log, 'timed out on attempt \d of \d')).Count | Should -Be $Retries
  }

  It 'reports the option once a retry after a time-out succeeds' {
    $script:Calls = 0
    $Server = New-FakeUpdateServer -Cleanup {
      Param ($Scope)
      $script:Calls++
      If ($script:Calls -eq 1) { Throw 'The operation has timed out.' }
      New-FakeCleanupResult -Scope $Scope
    }

    $Result = Invoke-Cleanup -Server $Server

    $Result.Status | Should -Be 'Success'
    $Result.Items[0] | Should -Be 'superseded-update decline: 4 update(s) declined in 0.0 s (attempt 2)'
    (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Warning\s+\[RUN\] BuiltInCleanup: Built-in cleanup option superseded-update decline timed out on attempt 1 of 3:'
  }

  It 'does not retry a failure that is not a time-out' {
    $Server = New-FakeUpdateServer -Cleanup {
      Param ($Scope)
      If ($Scope.CleanupObsoleteUpdates) { Throw 'The request failed with HTTP status 401: Unauthorized.' }
      New-FakeCleanupResult -Scope $Scope
    }

    $Result = Invoke-Cleanup -Server $Server

    @(Get-ScopeOption -Server $Server | Where-Object -FilterScript { $PSItem -eq 'CleanupObsoleteUpdates' }) | Should -HaveCount 1
    $Result.Status | Should -Be 'Error'
    $Result.Items[2] | Should -BeLike 'obsolete updates: failed after 1 attempt(s): *401*'
  }

  It 'reports a refusal on a replica as rejected by server role and runs the other options' {
    $Server = New-FakeUpdateServer -Cleanup {
      Param ($Scope)
      If ($Scope.CleanupObsoleteUpdates) { Throw 'This operation is not allowed on a replica server.' }
      New-FakeCleanupResult -Scope $Scope
    }

    $Result = Invoke-Cleanup -Server $Server -Tier 'Replica'

    $Result.Status | Should -Be 'Warning'
    $Result.Counts['OptionsFailed'] | Should -Be 0
    $Result.Items[2] | Should -BeLike 'obsolete updates: rejected by server role: *not allowed on a replica*'
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -BeLike 'The built-in cleanup option obsolete updates was refused, as expected on a replica (rejected by server role): *'
    Get-ScopeOption -Server $Server | Should -Contain 'CleanupUnneededContentFiles'
  }

  It 'starts no option once the time budget is reached and says which will run next time' {
    $Server = New-FakeUpdateServer
    $script:BudgetChecks = 0
    Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 2 }

    $Result = Invoke-Cleanup -Server $Server

    Get-ScopeOption -Server $Server | Should -Be @('DeclineSupersededUpdates', 'DeclineExpiredUpdates')
    $Result.Status | Should -Be 'Warning'
    $Result.Items[2] | Should -Be 'obsolete updates: not started: time budget reached'
    $Result.Notices[0].Message | Should -Be 'Time budget reached before the built-in cleanup option(s) obsolete updates, obsolete update revisions, unneeded content files could start; they run on the next run.'
  }

  It 'calls nothing in a dry run and lists the options that would run' {
    $Server = New-FakeUpdateServer

    $Result = Invoke-Cleanup -Server $Server -DryRun $True

    $Server.State.CleanupScopes | Should -HaveCount 0
    $Result.Items[0] | Should -Be 'superseded-update decline: would run'
    $Result.Message | Should -BeLike 'Would run 5 built-in cleanup option(s); nothing was changed. Unneeded content file cleanup also deletes*'
  }

  It 'needs the WSUS connection discovery opens' {
    { Invoke-WsusBuiltInCleanup -Context (New-FakeStageContext) } | Should -Throw -ExpectedMessage 'No WSUS connection is open; the stage needs the discovery steps to have run.'
  }
}
