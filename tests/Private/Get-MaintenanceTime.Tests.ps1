#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceTime' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'returns the current local time' {
    $Before = [System.DateTime]::Now
    $Result = Get-MaintenanceTime
    $After = [System.DateTime]::Now

    $Result | Should -BeOfType ([System.DateTime])
    $Result.Kind | Should -Be ([System.DateTimeKind]::Local)
    $Result | Should -BeGreaterOrEqual $Before
    $Result | Should -BeLessOrEqual $After
  }
}
