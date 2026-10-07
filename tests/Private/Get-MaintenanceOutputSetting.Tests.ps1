#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceOutputSetting' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:ConvertFrom-Document {
      Param ([System.String]$Json)
      $Json | ConvertFrom-Json
    }
  }

  It 'returns the built-in defaults when there is no document' {
    $Setting = Get-MaintenanceOutputSetting

    $Setting.ReportFolder | Should -Be '%ProgramData%\NWarila\WsusMaintenance\Reports'
    $Setting.DefaultReportFolder | Should -Be $Setting.ReportFolder
    $Setting.ReportFormats | Should -Be @('Text', 'Html')
    $Setting.MaxItems | Should -Be 100
    $Setting.LogFolder | Should -Be '%ProgramData%\NWarila\WsusMaintenance\Logs'
    $Setting.LogVerbosity | Should -Be 'Information'
    $Setting.SummaryFolder | Should -Be '%ProgramData%\NWarila\WsusMaintenance\Summaries'
    $Setting.DefaultSummaryFolder | Should -Be $Setting.SummaryFolder
    $Setting.EventLog.Enabled | Should -BeTrue
    $Setting.EventLog.LogName | Should -Be 'Application'
    $Setting.EventLog.Source | Should -Be 'Invoke-WsusMaintenance'
    @($Setting.EventLog.EventIds.PSObject.Properties.Name) | Should -Be @('runStarted', 'runSucceeded', 'runWarning', 'runFailed', 'stageError', 'preconditionFailure', 'configurationInvalid')
    $Setting.EventLog.EventIds.configurationInvalid | Should -Be 1300
  }

  It 'takes every value from a valid configuration' {
    $Configuration = ConvertTo-MaintenanceEffectiveConfiguration -Document (ConvertFrom-Document -Json '{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }, "report": { "folder": "D:\\Reports", "formats": [ "Html" ], "maxItemsPerSection": 5 }, "log": { "verbosity": "Debug" }, "eventLog": { "enabled": false } }')

    $Setting = Get-MaintenanceOutputSetting -Configuration $Configuration -ReportFolder 'E:\Ignored'

    $Setting.ReportFolder | Should -Be 'D:\Reports'
    $Setting.ReportFormats | Should -Be @('Html')
    $Setting.MaxItems | Should -Be 5
    $Setting.LogVerbosity | Should -Be 'Debug'
    $Setting.EventLog.Enabled | Should -BeFalse
  }

  It 'keeps each valid setting of an invalid document and defaults the rest' {
    $Document = ConvertFrom-Document -Json '{ "schemaVersion": 7, "report": { "folder": "D:\\Reports", "formats": [ "Pdf" ] }, "log": { "folder": "relative" }, "eventLog": { "eventIds": { "runStarted": 2000 } } }'

    $Setting = Get-MaintenanceOutputSetting -Document $Document

    $Setting.ReportFolder | Should -Be 'D:\Reports'
    $Setting.ReportFormats | Should -Be @('Text', 'Html')
    $Setting.LogFolder | Should -Be '%ProgramData%\NWarila\WsusMaintenance\Logs'
    $Setting.EventLog.EventIds.runStarted | Should -Be 2000
  }

  It 'applies valid command-line overrides when the configuration is invalid' {
    $Setting = Get-MaintenanceOutputSetting -ReportFolder 'E:\Reports' -ReportFormat @('Text') -Verbosity 'Verbose'

    $Setting.ReportFolder | Should -Be 'E:\Reports'
    $Setting.ReportFormats | Should -Be @('Text')
    $Setting.LogVerbosity | Should -Be 'Verbose'
  }

  It 'ignores invalid command-line overrides' {
    $Setting = Get-MaintenanceOutputSetting -ReportFolder 'relative' -ReportFormat @('Text', 'Text')

    $Setting.ReportFolder | Should -Be '%ProgramData%\NWarila\WsusMaintenance\Reports'
    $Setting.ReportFormats | Should -Be @('Text', 'Html')
  }

  It 'accepts an explicit catalogue' {
    $Setting = Get-MaintenanceOutputSetting -Rule @(Get-MaintenanceConfigurationRule)

    $Setting.MaxItems | Should -Be 100
  }
}
