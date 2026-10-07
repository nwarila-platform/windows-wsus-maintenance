#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceStageHandler' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    $script:Delivered = [ordered]@{
      Backup          = 'Backup-Susdb'
      CustomIndexes   = 'Set-SusdbCustomIndex'
      DeleteUpdateFix = 'Set-DeleteUpdateProcedureFix'
      ObsoleteUpdates = 'Invoke-ObsoleteUpdateCleanup'
      BuiltInCleanup  = 'Invoke-WsusBuiltInCleanup'
      SyncHistory     = 'Remove-SyncHistory'
      StaleComputers  = 'Invoke-StaleComputerCleanup'
      Reindex         = 'Invoke-SusdbIndexMaintenance'
    }
  }

  It 'hands each delivered stage the context through its function' {
    ForEach ($Stage In $script:Delivered.Keys) {
      $Function = $script:Delivered[$Stage]
      Mock -CommandName $Function -MockWith { [PSCustomObject]@{ Status = 'Success'; From = $Context.StageName } }

      $Handler = Get-MaintenanceStageHandler -Name $Stage
      $Answer = & $Handler ([PSCustomObject]@{ StageName = $Stage })

      $Answer.From | Should -Be $Stage -Because $Stage
      Should -Invoke -CommandName $Function -Times 1 -Exactly
    }
  }

  It 'has no handler yet for the stages a later release delivers' {
    ForEach ($Stage In @(Get-MaintenanceStageCatalog | Where-Object -FilterScript { -not $script:Delivered.Contains($PSItem.Name) })) {
      Get-MaintenanceStageHandler -Name $Stage.Name | Should -BeNullOrEmpty -Because $Stage.Name
    }
  }
}
