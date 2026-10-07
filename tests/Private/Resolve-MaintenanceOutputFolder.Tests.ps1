#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Resolve-MaintenanceOutputFolder' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Blocked = Join-Path -Path $TestDrive -ChildPath 'blocked'
    Set-Content -LiteralPath $script:Blocked -Value 'x'
  }

  It 'uses the configured folder when it can be written' {
    $Choice = Resolve-MaintenanceOutputFolder -Path (Join-Path -Path $TestDrive -ChildPath 'reports') -DefaultPath (Join-Path -Path $TestDrive -ChildPath 'default') -Purpose 'report'

    $Choice.Path | Should -Be (Join-Path -Path $TestDrive -ChildPath 'reports')
    $Choice.Notice | Should -BeNullOrEmpty
  }

  It 'falls back to the default folder with a warning' {
    $Default = Join-Path -Path $TestDrive -ChildPath 'default'

    $Choice = Resolve-MaintenanceOutputFolder -Path (Join-Path -Path $script:Blocked -ChildPath 'reports') -DefaultPath $Default -Purpose 'summary'

    $Choice.Path | Should -Be $Default
    $Choice.Notice.Severity | Should -Be 'Warning'
    $Choice.Notice.Message | Should -BeLike "The summary folder '*' cannot be used (*); the summary is saved to the default folder '*default' instead."
  }

  It 'saves nothing, with a warning, when the default cannot be written either' {
    $Choice = Resolve-MaintenanceOutputFolder -Path (Join-Path -Path $script:Blocked -ChildPath 'one') -DefaultPath (Join-Path -Path $script:Blocked -ChildPath 'two') -Purpose 'report'

    $Choice.Path | Should -BeNullOrEmpty
    $Choice.Notice.Message | Should -BeLike "The report folder '*one' cannot be used (*); no report file is saved for this run."
  }
}
