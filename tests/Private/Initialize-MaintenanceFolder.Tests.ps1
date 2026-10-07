#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Initialize-MaintenanceFolder' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'creates a missing folder and leaves no probe file behind' {
    $Path = Join-Path -Path $TestDrive -ChildPath 'new/nested'

    $Ready = Initialize-MaintenanceFolder -Path $Path

    $Ready.Error | Should -BeNullOrEmpty
    $Ready.Path | Should -Be $Path
    Test-Path -LiteralPath $Path -PathType Container | Should -BeTrue
    @(Get-ChildItem -LiteralPath $Path -Force) | Should -HaveCount 0
  }

  It 'refuses a path that is not absolute on this host without touching the file system' {
    Mock -CommandName Resolve-MaintenancePath -MockWith { 'relative\folder' }

    $Ready = Initialize-MaintenanceFolder -Path '%NoSuchVariable%\folder'

    $Ready.Error | Should -Be "'relative\folder' is not an absolute path on this host."
  }

  It 'reports a folder that cannot be created' {
    $File = Join-Path -Path $TestDrive -ChildPath 'a-file'
    Set-Content -LiteralPath $File -Value 'x'

    $Ready = Initialize-MaintenanceFolder -Path (Join-Path -Path $File -ChildPath 'sub')

    $Ready.Error | Should -Not -BeNullOrEmpty
  }
}
