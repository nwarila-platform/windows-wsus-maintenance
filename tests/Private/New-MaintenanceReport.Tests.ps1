#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceReport' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Start = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
    $script:Run = [PSCustomObject]@{ RunId = 'RUN'; Stages = @(); DryRun = $False; StartedAt = $script:Start; CompletedAt = $script:Start.AddSeconds(12.5); DurationSeconds = 12.5; Deadline = $Null; Artifacts = $Null }
    $script:Validation = [PSCustomObject]@{ ConfigurationPath = 'C:\m.json'; Overrides = @() }

    Function script:New-Stage {
      Param ([System.String]$Name, [System.Int32]$Order, [System.String]$Status, $Extra = @{})
      $Outcome = [ordered]@{ Name = $Name; Order = $Order; Status = $Status; Reason = 'enabled'; StartedAt = $script:Start; DurationSeconds = 2.25; Counts = $Null; Message = ''; Items = @(); Notices = @(); ErrorMessage = ''; ErrorTime = $Null }
      ForEach ($Key In $Extra.Keys) {
        $Outcome[$Key] = $Extra[$Key]
      }
      [PSCustomObject]$Outcome
    }

    Function script:New-Report {
      Param ($Stage = @(), $Notice = @(), $Failure = $Null, [System.Int32]$MaxItems = 100, $Run = $script:Run, $Validation = $script:Validation)
      New-MaintenanceReport -ExitCode 1 -Failure $Failure -LogPath 'C:\Logs\run.log' -MaxItems $MaxItems -Notice $Notice -Run $Run -Stage $Stage -Status 'Error' -Validation $Validation
    }
  }

  BeforeEach {
    $Script:MaintenanceSecret.Clear()
  }

  It 'builds the header in report order, with discovery data not yet discovered' {
    $Report = New-Report

    $Report.PSTypeNames[0] | Should -Be 'WsusMaintenance.Report'
    $Report.Header.Label | Should -Be @('Server', 'WSUS version', 'Server role', 'Upstream source', 'Database', 'WSUS endpoint', 'Run identity', 'Database permissions', 'Synchronization', 'Run identifier', 'Profile', 'Dry run', 'Started', 'Configuration', 'Overrides', 'Run log')
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'WSUS version' }).Value | Should -Be 'not yet discovered'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Profile' }).Value | Should -Be 'every enabled stage'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Started' }).Value | Should -Match '^2026-11-01 02:00:00 [+-]\d{2}:\d{2} \(.+\)$'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Overrides' }).Value | Should -Be 'none'
    $Report.Connection | Should -Be 'not yet connected'
    $Report.Server | Should -Be ([System.Environment]::MachineName)
    $Report.DurationSeconds | Should -Be 12.5
    $Report.Failure | Should -BeNullOrEmpty
  }

  It 'fills the header and the connection time from discovery, keeping "not yet discovered" for the rest' {
    $Discovery = [PSCustomObject]@{ WsusVersion = '10.0.20348.2700'; Role = 'Replica downstream server'; Upstream = 'up, port 8531, TLS'; Database = 'SQL Server on this server'; Identity = 'NT AUTHORITY\SYSTEM'; Connection = 'WSUS administration interface at 02:00:01; SUSDB at 02:00:02'; Permissions = '' }

    $Report = New-MaintenanceReport -Discovery $Discovery -ExitCode 0 -MaxItems 10 -Run $script:Run -Status 'Success' -Validation $script:Validation

    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'WSUS version' }).Value | Should -Be '10.0.20348.2700'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Server role' }).Value | Should -Be 'Replica downstream server'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Run identity' }).Value | Should -Be 'NT AUTHORITY\SYSTEM'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Database permissions' }).Value | Should -Be 'not yet discovered'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'WSUS endpoint' }).Value | Should -Be 'not yet discovered'
    $Report.Connection | Should -Be 'WSUS administration interface at 02:00:01; SUSDB at 02:00:02'
  }

  It 'names a stage list, a dry run, the overrides and a missing log in the header' {
    $Run = [PSCustomObject]@{ RunId = 'RUN'; Stages = @('Backup', 'Reindex'); DryRun = $True; StartedAt = $script:Start; CompletedAt = $script:Start; DurationSeconds = 0 }
    $Validation = [PSCustomObject]@{ ConfigurationPath = 'C:\m.json'; Overrides = @('run.dryRun = true (-DryRun)', 'stages = Backup, Reindex (-Stage)') }

    $Report = New-MaintenanceReport -ExitCode 0 -MaxItems 10 -Run $Run -Status 'Success' -Validation $Validation

    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Profile' }).Value | Should -Be 'stage list: Backup, Reindex'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Dry run' }).Value | Should -Be 'yes'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Overrides' }).Value | Should -Be 'run.dryRun = true (-DryRun); stages = Backup, Reindex (-Stage)'
    ($Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Run log' }).Value | Should -Be 'not written'
    $Report.StagesRequested | Should -Be @('Backup', 'Reindex')
  }

  It 'orders notices by severity, highest first, keeping the raised order within a severity' {
    $Notice = @(
      [PSCustomObject]@{ Severity = 'Information'; Message = 'i1' }
      [PSCustomObject]@{ Severity = 'High'; Message = 'h1'; Stage = 'HealthChecks'; Link = 'https://learn.microsoft.com/x'; Command = 'Get-Thing' }
      [PSCustomObject]@{ Severity = 'Warning'; Message = 'w1' }
      [PSCustomObject]@{ Severity = 'High'; Message = 'h2' }
      $Null
      [PSCustomObject]@{ Severity = 'Warning'; Message = 'w2' }
    )

    $Report = New-Report -Notice $Notice

    $Report.Notices.Message | Should -Be @('h1', 'h2', 'w1', 'w2', 'i1')
    $Report.HighestSeverity | Should -Be 'High'
    $Report.Notices.IsHighest | Should -Be @($True, $True, $False, $False, $False)
    $Report.Notices[0].Stage | Should -Be 'HealthChecks'
    $Report.Notices[0].Link | Should -Be 'https://learn.microsoft.com/x'
    $Report.Notices[0].Command | Should -Be 'Get-Thing'
    $Report.Notices[2].Link | Should -BeNullOrEmpty
    $Report.Totals.Notices.High | Should -Be 2
    $Report.Totals.Notices.Warning | Should -Be 2
    $Report.Totals.Notices.Information | Should -Be 1
    $Report.Totals.Notices.Error | Should -Be 0
  }

  It 'gives each stage one section with its status, counts, items and error' {
    $Stage = @(
      New-Stage -Name 'Backup' -Order 1 -Status 'Error' -Extra @{ ErrorMessage = 'disk full'; ErrorTime = $script:Start }
      $Null
      New-Stage -Name 'Reindex' -Order 13 -Status 'Success' -Extra @{ Counts = @{ Reorganized = 5; Rebuilt = 3 }; Items = @('a', $Null, 'b', 'c'); Message = 'done' }
      New-Stage -Name 'HealthChecks' -Order 16 -Status 'Warning' -Extra @{ Counts = [PSCustomObject]@{ Checked = 6; Failed = 1 } }
      New-Stage -Name 'IisLogRetention' -Order 14 -Status 'Skipped' -Extra @{ Counts = [ordered]@{ Zeta = 1; Alpha = 2 } }
    )

    $Report = New-Report -Stage $Stage -MaxItems 2

    $Report.Stages.Name | Should -Be @('Backup', 'Reindex', 'HealthChecks', 'IisLogRetention')
    $Report.Stages[0].ErrorMessage | Should -Be 'disk full'
    $Report.Stages[1].Counts.Name | Should -Be @('Rebuilt', 'Reorganized')
    $Report.Stages[1].Items | Should -Be @('a', 'b')
    $Report.Stages[1].ItemCount | Should -Be 3
    $Report.Stages[1].OmittedItems | Should -Be 1
    $Report.Stages[2].Counts.Name | Should -Be @('Checked', 'Failed')
    $Report.Stages[3].Counts.Name | Should -Be @('Zeta', 'Alpha')
    $Report.Stages[3].Items | Should -HaveCount 0
    $Report.Totals.Stages.Success | Should -Be 1
    $Report.Totals.Stages.Warning | Should -Be 1
    $Report.Totals.Stages.Error | Should -Be 1
    $Report.Totals.Stages.Skipped | Should -Be 1
    $Report.Totals.Stages.NotRun | Should -Be 0
  }

  It 'carries a failure' {
    $Report = New-Report -Failure ([PSCustomObject]@{ Kind = 'PreconditionFailed'; Point = 'elevation check'; Message = 'Not elevated.'; Guidance = 'Elevate.' })

    $Report.Failure.Kind | Should -Be 'PreconditionFailed'
    $Report.Failure.Point | Should -Be 'elevation check'
    $Report.Failure.Message | Should -Be 'Not elevated.'
    $Report.Failure.Guidance | Should -Be 'Elevate.'
  }

  It 'removes registered secrets from every text it takes in' {
    Register-MaintenanceSecret -Value 'hunter2'
    $Stage = @(New-Stage -Name 'Backup' -Order 1 -Status 'Error' -Extra @{ Reason = 'r hunter2'; Message = 'm hunter2'; Items = @('i hunter2'); ErrorMessage = 'e hunter2' })
    $Notice = @([PSCustomObject]@{ Severity = 'Error'; Message = 'n hunter2'; Link = 'https://x/hunter2'; Command = 'c hunter2' })
    $Failure = [PSCustomObject]@{ Kind = 'PreconditionFailed'; Point = 'p'; Message = 'f hunter2'; Guidance = 'g' }
    $Validation = [PSCustomObject]@{ ConfigurationPath = 'C:\hunter2.json'; Overrides = @() }

    $Report = New-Report -Stage $Stage -Notice $Notice -Failure $Failure -Validation $Validation

    (ConvertTo-Json -InputObject $Report -Depth 8) | Should -Not -Match 'hunter2'
  }
}
