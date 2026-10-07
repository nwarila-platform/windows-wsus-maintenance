#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'ConvertTo-MaintenanceDisplayValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'renders null, text, numbers and arrays as compact JSON' {
    ConvertTo-MaintenanceDisplayValue -Value $Null | Should -Be 'null'
    ConvertTo-MaintenanceDisplayValue -Value 'yes' | Should -Be '"yes"'
    ConvertTo-MaintenanceDisplayValue -Value 42 | Should -Be '42'
    ConvertTo-MaintenanceDisplayValue -Value @(7, 14) | Should -Be '[7,14]'
  }

  It 'truncates long values' {
    $Rendered = ConvertTo-MaintenanceDisplayValue -Value ('x' * 200)

    $Rendered.Length | Should -Be 80
    $Rendered | Should -BeLike '*...'
  }
}
