#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Resolve-MaintenancePath' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'expands a leading environment variable' {
    $env:WSUS_MAINTENANCE_TEST_ROOT = 'D:\Data'
    Try {
      Resolve-MaintenancePath -Path '%WSUS_MAINTENANCE_TEST_ROOT%\State' | Should -Be 'D:\Data\State'
    } Finally {
      Remove-Item -Path 'Env:\WSUS_MAINTENANCE_TEST_ROOT'
    }
  }

  It 'returns a literal path unchanged' {
    Resolve-MaintenancePath -Path 'H:\SUSDB' | Should -Be 'H:\SUSDB'
  }
}
