#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceDefaultConfigurationPath' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'resolves maintenance.json under the common application data folder' {
    $ProgramData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
    $Expected = [System.IO.Path]::Combine($ProgramData, 'NWarila', 'WsusMaintenance', 'maintenance.json')

    Get-MaintenanceDefaultConfigurationPath | Should -Be $Expected
  }
}
