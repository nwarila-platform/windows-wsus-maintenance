#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'MaintenanceExitCode' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'keeps the published exit-code table' {
    [System.Int32][MaintenanceExitCode]::Success | Should -Be 0
    [System.Int32][MaintenanceExitCode]::StageError | Should -Be 1
    [System.Int32][MaintenanceExitCode]::CompletedWithWarnings | Should -Be 2
    [System.Int32][MaintenanceExitCode]::PreconditionFailed | Should -Be 3
    [System.Int32][MaintenanceExitCode]::ConfigurationInvalid | Should -Be 4
    [System.Int32][MaintenanceExitCode]::LockHeld | Should -Be 5
    [System.Int32][MaintenanceExitCode]::DeliveryFailed | Should -Be 6
  }

  It 'gives every outcome a distinct code' {
    $Values = [System.Int32[]]@([System.Enum]::GetValues([MaintenanceExitCode]))

    $Values | Should -HaveCount 7
    @($Values | Sort-Object -Unique) | Should -HaveCount 7
  }
}
