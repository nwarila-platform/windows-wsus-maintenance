#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:CanValidate = $Null -ne (Get-Command -Name 'Test-Json' -ErrorAction SilentlyContinue)
}

Describe 'Write-MaintenanceSummary' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:SchemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../../docs/reference/summary.schema.json'
    $script:Start = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
    $script:Run = [PSCustomObject]@{ RunId = '20261101-020000-0a1b2c3d'; Stages = @('Backup'); DryRun = $True; StartedAt = $script:Start; CompletedAt = $script:Start.AddSeconds(3.25); DurationSeconds = 3.25 }
    $script:Validation = [PSCustomObject]@{ ConfigurationPath = 'C:\m.json'; Overrides = @() }
    $script:Stages = @(
      [PSCustomObject]@{ Name = 'Backup'; Order = 1; Status = 'Error'; Reason = 'stage error'; StartedAt = $script:Start; DurationSeconds = 1.5; Counts = [ordered]@{ Files = 2; Mode = 'Full'; Verified = $True }; Message = ''; Items = @('a', 'b'); ErrorMessage = 'disk full'; ErrorTime = $script:Start.AddSeconds(1) }
      [PSCustomObject]@{ Name = 'Reindex'; Order = 13; Status = 'NotRun'; Reason = 'time budget reached before the stage could start'; StartedAt = $Null; DurationSeconds = 0; Counts = $Null; Message = ''; Items = @(); ErrorMessage = ''; ErrorTime = $Null }
    )
    $script:Notices = @(
      New-MaintenanceNotice -Severity 'Warning' -Message 'w' -Link 'https://learn.microsoft.com/x'
      [PSCustomObject]@{ Severity = 'Error'; Message = 'e' }
    )

    Function script:Write-Summary {
      Param ($Report, [System.String]$Folder)
      Write-MaintenanceSummary -Folder $Folder -LogPath 'C:\Logs\run.log' -Report $Report -ReportPath @('C:\Reports\r.txt')
    }
  }

  BeforeEach {
    $script:Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path $script:Folder
    $script:Report = New-MaintenanceReport -ExitCode 1 -MaxItems 1 -Notice $script:Notices -Run $script:Run -Stage $script:Stages -Status 'Error' -Validation $script:Validation
  }

  It 'writes the summary named after the run identifier, with counts that match the report' {
    $Written = Write-Summary -Report $script:Report -Folder $script:Folder
    $Summary = Get-Content -LiteralPath $Written.Path -Raw | ConvertFrom-Json

    $Written.Error | Should -BeNullOrEmpty
    $Written.Path | Should -Be (Join-Path -Path $script:Folder -ChildPath 'WsusMaintenance-20261101-020000-0a1b2c3d.json')
    $Summary.schemaVersion | Should -Be 1
    $Summary.runId | Should -Be '20261101-020000-0a1b2c3d'
    $Summary.status | Should -Be 'Error'
    $Summary.exitCode | Should -Be 1
    $Summary.dryRun | Should -BeTrue
    $Summary.durationSeconds | Should -Be 3.25
    @($Summary.stagesRequested) | Should -Be @('Backup')
    $Summary.totals.stages.error | Should -Be $script:Report.Totals.Stages.Error
    $Summary.totals.stages.notRun | Should -Be $script:Report.Totals.Stages.NotRun
    $Summary.totals.notices.error | Should -Be $script:Report.Totals.Notices.Error
    $Summary.totals.notices.warning | Should -Be $script:Report.Totals.Notices.Warning
    @($Summary.stages) | Should -HaveCount 2
    $Summary.stages[0].counts.Files | Should -Be 2
    $Summary.stages[0].counts.Mode | Should -Be 'Full'
    $Summary.stages[0].itemCount | Should -Be 2
    $Summary.stages[1].startedAt | Should -BeNullOrEmpty
    @($Summary.notices).severity | Should -Be @('Error', 'Warning')
    $Summary.artifacts.log | Should -Be 'C:\Logs\run.log'
    @($Summary.artifacts.reports) | Should -Be @('C:\Reports\r.txt')
    $Summary.failure | Should -BeNullOrEmpty
  }

  It 'writes times as local time with offset' {
    $Written = Write-Summary -Report $script:Report -Folder $script:Folder

    (Get-Content -LiteralPath $Written.Path -Raw) | Should -Match '"startedAt":\s*"2026-11-01T02:00:00\.000[+-]\d{2}:\d{2}"'
  }

  It 'validates against the published schema, with and without a failure' -Skip:(-not $script:CanValidate) {
    $Failed = New-MaintenanceReport -ExitCode 4 -Failure ([PSCustomObject]@{ Kind = 'ConfigurationInvalid'; Point = 'configuration validation'; Message = 'm'; Guidance = 'g' }) -MaxItems 1 -Run $script:Run -Status 'Error' -Validation $script:Validation
    $Unexpected = New-MaintenanceReport -ExitCode 1 -Failure ([PSCustomObject]@{ Kind = 'StageError'; Point = 'stage run'; Message = 'm'; Guidance = 'g' }) -MaxItems 1 -Run $script:Run -Status 'Error' -Validation $script:Validation

    ForEach ($Report In @($script:Report, $Failed, $Unexpected)) {
      $Written = Write-Summary -Report $Report -Folder $script:Folder
      Test-Json -Json (Get-Content -LiteralPath $Written.Path -Raw) -SchemaFile $script:SchemaPath | Should -BeTrue
    }
  }

  It 'is rejected by the schema when it breaks the format' -Skip:(-not $script:CanValidate) {
    Test-Json -Json '{ "schemaVersion": 2 }' -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue | Should -BeFalse
  }

  It 'writes nothing without a usable folder' {
    $Written = Write-Summary -Report $script:Report -Folder ''

    $Written.Path | Should -BeNullOrEmpty
    $Written.Error | Should -BeNullOrEmpty
  }

  It 'reports a summary that cannot be written' {
    $Written = Write-Summary -Report $script:Report -Folder (Join-Path -Path $TestDrive -ChildPath 'missing')

    $Written.Path | Should -BeNullOrEmpty
    $Written.Error | Should -BeLike "The summary file '*' could not be written: *"
  }
}
