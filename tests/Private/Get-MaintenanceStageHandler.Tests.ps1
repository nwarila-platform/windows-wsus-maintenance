#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceStageHandler' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'has no handler yet for any stage in this release' {
    ForEach ($Stage In @(Get-MaintenanceStageCatalog)) {
      Get-MaintenanceStageHandler -Name $Stage.Name | Should -BeNullOrEmpty -Because $Stage.Name
    }
  }
}
