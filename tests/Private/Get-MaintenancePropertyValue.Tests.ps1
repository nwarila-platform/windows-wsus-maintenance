#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenancePropertyValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'returns the value of a property the object has' {
    Get-MaintenancePropertyValue -InputObject ([PSCustomObject]@{ Link = 'https://example.invalid' }) -Name 'Link' | Should -Be 'https://example.invalid'
  }

  It 'returns the default for a missing property or a null object' {
    Get-MaintenancePropertyValue -InputObject ([PSCustomObject]@{ Message = 'm' }) -Name 'Link' -Default 'none' | Should -Be 'none'
    Get-MaintenancePropertyValue -InputObject $Null -Name 'Link' | Should -BeNullOrEmpty
  }

  It 'works under strict mode' {
    Set-StrictMode -Version 3.0
    Try {
      Get-MaintenancePropertyValue -InputObject ([PSCustomObject]@{}) -Name 'Command' -Default '' | Should -Be ''
    } Finally {
      Set-StrictMode -Off
    }
  }
}
