#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceStageHandler' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    $script:Delivered = [ordered]@{
      Backup             = 'Backup-Susdb'
      CustomIndexes      = 'Set-SusdbCustomIndex'
      DeleteUpdateFix    = 'Set-DeleteUpdateProcedureFix'
      SupersededDecline  = 'Invoke-SupersededDecline'
      AcceleratedDecline = 'Invoke-AcceleratedDecline'
      ExpiredDecline     = 'Invoke-ExpiredDecline'
      RuleDecline        = 'Invoke-RuleDecline'
      ContentStaging     = 'Invoke-ContentStaging'
      DeferredApproval   = 'Invoke-DeferredApproval'
      DeclinedDeletion   = 'Remove-DeclinedUpdate'
      ObsoleteUpdates    = 'Invoke-ObsoleteUpdateCleanup'
      BuiltInCleanup     = 'Invoke-WsusBuiltInCleanup'
      SyncHistory        = 'Remove-SyncHistory'
      StaleComputers     = 'Invoke-StaleComputerCleanup'
      Reindex            = 'Invoke-SusdbIndexMaintenance'
      IisLogRetention    = 'Remove-IisLogFile'
      ArtifactRetention  = 'Remove-MaintenanceArtifact'
      HealthChecks       = 'Invoke-HealthCheck'
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

  It 'has a handler for every stage of the catalogue, and none for an unknown name' {
    @($script:Delivered.Keys | Sort-Object) | Should -Be @(@(Get-MaintenanceStageCatalog).Name | Sort-Object)
    Get-MaintenanceStageHandler -Name 'Unknown' | Should -BeNullOrEmpty
  }
}
