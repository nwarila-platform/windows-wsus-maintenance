#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:CanValidate = $Null -ne (Get-Command -Name 'Test-Json' -ErrorAction SilentlyContinue)
}

Describe 'Invoke-WsusMaintenance reporting guarantees' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration'
    $script:SchemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../../docs/reference/summary.schema.json'
    $script:Secret = 'P1anted-Secret!'

    Function script:New-FakeLock {
      $Lock = [PSCustomObject]@{}
      $Lock | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value { }
      $Lock | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
      $Lock
    }

    Function script:Invoke-Run {
      Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json')
    }
  }

  BeforeEach {
    $Script:MaintenanceSecret.Clear()
    $script:Root = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $script:Events = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Test-MaintenanceElevation -MockWith { $True }
    $script:UpdateServer = New-FakeUpdateServer
    $script:Database = New-FakeSqlConnection -Rows @(New-PermissionRow)
    Mock -CommandName Get-MaintenanceIdentity -MockWith { 'NT AUTHORITY\SYSTEM' }
    Mock -CommandName Get-MaintenanceOperatingSystem -MockWith { [PSCustomObject]@{ Platform = 'Win32NT'; Major = 10; Build = 20348 } }
    Mock -CommandName Get-WsusSetupValue -MockWith { [PSCustomObject]@{ SqlServerName = [System.Environment]::MachineName; SqlDatabaseName = 'SUSDB' } }
    Mock -CommandName Get-WsusUpdateServer -MockWith { $script:UpdateServer }
    Mock -CommandName New-SqlConnection -MockWith { $script:Database }
    Mock -CommandName Wait-MaintenanceInterval -MockWith { }
    # Every component is present, and folder protection is exercised in its own tests.
    Mock -CommandName Test-MaintenanceDependencyPresent -MockWith { $True }
    Mock -CommandName Test-MaintenanceAclSupport -MockWith { $False }
    Mock -CommandName New-MaintenanceLock -MockWith { New-FakeLock }
    Mock -CommandName Resolve-MaintenancePath -MockWith { Join-Path -Path $script:Root -ChildPath ($Path -replace '[^A-Za-z0-9]+', '_') }
    Mock -CommandName Test-MaintenanceEventSource -MockWith { $True }
    Mock -CommandName Write-MaintenanceEventEntry -MockWith {
      $script:Events.Add([PSCustomObject]@{ EventId = $EventId; EntryType = $EntryType; Message = $Message })
    }

    # Three stages carry handlers: one fails, one warns and raises notices, one succeeds; the
    #   rest have none yet. The planted secret appears in every kind of text a stage returns.
    Register-MaintenanceSecret -Value $script:Secret
    Mock -CommandName Get-MaintenanceStageHandler -MockWith { $Null }
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'Backup' } -MockWith {
      { Throw ('Backup target refused the login with {0}.' -f $script:Secret) }
    }
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'Reindex' } -MockWith {
      {
        [PSCustomObject]@{
          Status  = 'Warning'
          Counts  = [ordered]@{ Rebuilt = 2; Reorganized = 7 }
          Items   = @('idx1', ('idx-{0}' -f $script:Secret))
          Message = ('Re-indexed with {0}.' -f $script:Secret)
          Notices = @(
            New-MaintenanceNotice -Severity 'Information' -Message 'Statistics updated.' -Stage 'Reindex'
            New-MaintenanceNotice -Severity 'High' -Message ('Fragmentation stays high ({0}).' -f $script:Secret) -Stage 'Reindex' -Command ('Invoke-Thing -Key {0}' -f $script:Secret)
            New-MaintenanceNotice -Severity 'Warning' -Message 'Two indexes were skipped.' -Stage 'Reindex'
          )
        }
      }
    }
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'HealthChecks' } -MockWith {
      { [PSCustomObject]@{ Status = 'Success'; Counts = @{ Checked = 6 } } }
    }

    # An earlier backup is recent enough, so the failed backup above does not close the gate.
    Mock -CommandName Test-BackupGate -MockWith { [PSCustomObject]@{ Satisfied = $True; Mode = 'Required'; Detail = 'last full backup finished 2026-11-02 00:30' } }

    $script:Result = Invoke-Run
    $script:Text = Get-Content -LiteralPath ($script:Result.Run.Artifacts.Reports | Where-Object -FilterScript { $PSItem -like '*.txt' }) -Raw
    $script:Html = Get-Content -LiteralPath ($script:Result.Run.Artifacts.Reports | Where-Object -FilterScript { $PSItem -like '*.html' }) -Raw
    $script:SummaryText = Get-Content -LiteralPath $script:Result.Run.Artifacts.Summary -Raw
    $script:Summary = $script:SummaryText | ConvertFrom-Json
    $script:LogText = Get-Content -LiteralPath $script:Result.Run.Artifacts.Log -Raw
  }

  It 'lists every stage exactly once, with its status and duration, in both renderings' {
    ForEach ($Outcome In $script:Result.Stages) {
      $TextPattern = '(?m)^\s*{0}\. {1}: {2}, \d+\.\d s\r?$' -f $Outcome.Order, $Outcome.Name, $Outcome.Status
      $HtmlPattern = '<td>{0}</td><td>{1}</td><td>{2}</td><td>\d+\.\d s</td>' -f $Outcome.Order, $Outcome.Name, $Outcome.Status
      @([System.Text.RegularExpressions.Regex]::Matches($script:Text, $TextPattern)) | Should -HaveCount 1 -Because $Outcome.Name
      @([System.Text.RegularExpressions.Regex]::Matches($script:Html, $HtmlPattern)) | Should -HaveCount 1 -Because $Outcome.Name
    }
    $script:Result.Stages | Should -HaveCount 18
  }

  It 'orders the notices by severity in both renderings' {
    $TextOrder = @([System.Text.RegularExpressions.Regex]::Matches($script:Text, '(?m)^(?:>>>|   ) \[([A-Za-z]+)\]') | ForEach-Object -Process { $PSItem.Groups[1].Value.ToUpperInvariant() })
    $HtmlOrder = @([System.Text.RegularExpressions.Regex]::Matches($script:Html, 'class="notice sev-([a-z]+)') | ForEach-Object -Process { $PSItem.Groups[1].Value.ToUpperInvariant() })

    $TextOrder | Should -Be @('HIGH', 'WARNING', 'INFORMATION')
    $HtmlOrder | Should -Be @('HIGH', 'WARNING', 'INFORMATION')
    $script:Text | Should -Match '>>> \[HIGH\] Fragmentation stays high'
  }

  It 'keeps the planted secret out of the log, both reports, the summary and every event' {
    $script:LogText | Should -Not -Match ([System.Text.RegularExpressions.Regex]::Escape($script:Secret))
    $script:Text | Should -Not -Match ([System.Text.RegularExpressions.Regex]::Escape($script:Secret))
    $script:Html | Should -Not -Match ([System.Text.RegularExpressions.Regex]::Escape($script:Secret))
    $script:SummaryText | Should -Not -Match ([System.Text.RegularExpressions.Regex]::Escape($script:Secret))
    ForEach ($Entry In $script:Events) {
      $Entry.Message | Should -Not -Match ([System.Text.RegularExpressions.Regex]::Escape($script:Secret))
    }
    $script:LogText | Should -Match ([System.Text.RegularExpressions.Regex]::Escape('[REDACTED]'))
    $script:Text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape('Backup target refused the login with [REDACTED].'))
  }

  It 'writes a summary that validates against its schema' -Skip:(-not $script:CanValidate) {
    Test-Json -Json $script:SummaryText -SchemaFile $script:SchemaPath | Should -BeTrue
  }

  It 'writes summary counts that match the report' {
    $Stages = [System.Text.RegularExpressions.Regex]::Match($script:Text, 'Stage totals: (\d+) succeeded, (\d+) with warnings, (\d+) failed, (\d+) skipped, (\d+) not run')
    $Notices = [System.Text.RegularExpressions.Regex]::Match($script:Text, 'Notice totals: (\d+) error, (\d+) high, (\d+) warning, (\d+) information')

    $Stages.Success | Should -BeTrue
    @($script:Summary.totals.stages.success, $script:Summary.totals.stages.warning, $script:Summary.totals.stages.error, $script:Summary.totals.stages.skipped, $script:Summary.totals.stages.notRun) |
      Should -Be @(1..5 | ForEach-Object -Process { [System.Int32]$Stages.Groups[$PSItem].Value })
    @($script:Summary.totals.notices.error, $script:Summary.totals.notices.high, $script:Summary.totals.notices.warning, $script:Summary.totals.notices.information) |
      Should -Be @(1..4 | ForEach-Object -Process { [System.Int32]$Notices.Groups[$PSItem].Value })
    @($script:Summary.stages) | Should -HaveCount 18
    @($script:Summary.notices) | Should -HaveCount 3
  }

  It 'reports one stage error consistently in the report, the summary, the events and the exit code' {
    $script:Result.Status | Should -Be 'Error'
    $script:Result.ExitCode | Should -Be 1
    $script:Text | Should -Match 'Run status: Error \(exit code 1\)'
    $script:Summary.status | Should -Be 'Error'
    $script:Summary.exitCode | Should -Be 1
    $script:Events.EventId | Should -Be @(1000, 1100, 1003)
    $script:Events[1].Message | Should -BeLike '*stage Backup failed: Backup target refused the login with `[REDACTED`].'
  }

  It 'traces every report item to a log entry carrying the same run identifier' {
    $RunId = [System.Text.RegularExpressions.Regex]::Escape($script:Result.Run.RunId)
    ForEach ($Outcome In $script:Result.Stages) {
      $script:LogText | Should -Match ('\[{0}\] {1}: Stage (finished|skipped|not run)' -f $RunId, $Outcome.Name) -Because $Outcome.Name
    }
    $script:LogText | Should -Match ('\[{0}\] Reindex: Notice \(High\): Fragmentation stays high' -f $RunId)
    $script:LogText | Should -Match ('\[{0}\] Reindex: Item: idx1' -f $RunId)
    $script:Text | Should -Match ('Run identifier\s+: {0}' -f $RunId)
    $script:Summary.runId | Should -Be $script:Result.Run.RunId
  }
}
