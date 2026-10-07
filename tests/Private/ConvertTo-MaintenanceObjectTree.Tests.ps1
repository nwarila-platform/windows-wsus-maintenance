#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'ConvertTo-MaintenanceObjectTree' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'converts nested ordered dictionaries and keeps key order and leaf values' {
    $Root = [ordered]@{ b = [ordered]@{ z = 1; a = @(1, 2) }; a = 'x' }
    $Tree = ConvertTo-MaintenanceObjectTree -InputObject $Root

    $Tree | Should -BeOfType ([System.Management.Automation.PSCustomObject])
    @($Tree.PSObject.Properties.Name) | Should -Be @('b', 'a')
    @($Tree.b.PSObject.Properties.Name) | Should -Be @('z', 'a')
    $Tree.b.a | Should -Be @(1, 2)
    $Tree.a | Should -Be 'x'
  }
}
