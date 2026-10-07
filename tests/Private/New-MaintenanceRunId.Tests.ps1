#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceRunId' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'starts with the run''s start time and ends with eight hexadecimal digits' {
    $RunId = New-MaintenanceRunId -RunStart ([System.DateTime]::new(2026, 11, 1, 2, 0, 5))

    $RunId | Should -Match '^20261101-020005-[0-9a-f]{8}$'
  }

  It 'keeps two runs started in the same second apart' {
    $Start = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)

    New-MaintenanceRunId -RunStart $Start | Should -Not -Be (New-MaintenanceRunId -RunStart $Start)
  }
}
