#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceBudget' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 10, 6, 4, 0, 0) }
  }

  It 'is never used up without a deadline' {
    Test-MaintenanceBudget -Deadline $Null | Should -BeFalse
  }

  It 'is used up at and after the deadline only' {
    Test-MaintenanceBudget -Deadline ([System.DateTime]::new(2026, 10, 6, 4, 0, 1)) | Should -BeFalse
    Test-MaintenanceBudget -Deadline ([System.DateTime]::new(2026, 10, 6, 4, 0, 0)) | Should -BeTrue
    Test-MaintenanceBudget -Deadline ([System.DateTime]::new(2026, 10, 6, 3, 0, 0)) | Should -BeTrue
  }
}
