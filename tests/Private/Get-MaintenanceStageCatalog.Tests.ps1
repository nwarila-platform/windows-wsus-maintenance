#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceStageCatalog' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Catalog = @(Get-MaintenanceStageCatalog)

    Function script:Get-StageOrder {
      Param ([System.String]$Name)
      ($script:Catalog | Where-Object -FilterScript { $PSItem.Name -ceq $Name }).Order
    }
  }

  It 'lists eighteen uniquely named stages in strictly increasing order' {
    $script:Catalog | Should -HaveCount 18
    @($script:Catalog.Name | Sort-Object -Unique) | Should -HaveCount 18
    For ($Index = 1; $Index -lt $script:Catalog.Count; $Index++) {
      $script:Catalog[$Index].Order | Should -BeGreaterThan $script:Catalog[$Index - 1].Order
    }
  }

  It 'puts the backup before every stage that alters SUSDB content' {
    $BackupOrder = Get-StageOrder -Name 'Backup'
    $script:Catalog[0].Name | Should -Be 'Backup'
    ForEach ($Stage In @($script:Catalog | Where-Object -FilterScript { $PSItem.AltersDatabase })) {
      $Stage.Order | Should -BeGreaterThan $BackupOrder
    }
  }

  It 'puts the custom indexes and the procedure fix before obsolete-update deletion' {
    (Get-StageOrder -Name 'CustomIndexes') | Should -BeLessThan (Get-StageOrder -Name 'ObsoleteUpdates')
    (Get-StageOrder -Name 'DeleteUpdateFix') | Should -BeLessThan (Get-StageOrder -Name 'ObsoleteUpdates')
  }

  It 'puts every decline before declined-update deletion and the built-in cleanup' {
    ForEach ($Decline In @('SupersededDecline', 'AcceleratedDecline', 'ExpiredDecline', 'RuleDecline')) {
      (Get-StageOrder -Name $Decline) | Should -BeLessThan (Get-StageOrder -Name 'DeclinedDeletion')
      (Get-StageOrder -Name $Decline) | Should -BeLessThan (Get-StageOrder -Name 'BuiltInCleanup')
    }
  }

  It 'puts content staging and deferred approval after every decline and before declined-update deletion and the built-in cleanup' {
    (Get-StageOrder -Name 'ContentStaging') | Should -BeLessThan (Get-StageOrder -Name 'DeferredApproval')
    ForEach ($Approval In @('ContentStaging', 'DeferredApproval')) {
      ForEach ($Decline In @('SupersededDecline', 'AcceleratedDecline', 'ExpiredDecline', 'RuleDecline')) {
        (Get-StageOrder -Name $Approval) | Should -BeGreaterThan (Get-StageOrder -Name $Decline)
      }
      (Get-StageOrder -Name $Approval) | Should -BeLessThan (Get-StageOrder -Name 'DeclinedDeletion')
      (Get-StageOrder -Name $Approval) | Should -BeLessThan (Get-StageOrder -Name 'BuiltInCleanup')
    }
  }

  It 'puts every cleanup and deletion before re-indexing' {
    ForEach ($Cleanup In @('DeclinedDeletion', 'ObsoleteUpdates', 'BuiltInCleanup', 'SyncHistory', 'StaleComputers')) {
      (Get-StageOrder -Name $Cleanup) | Should -BeLessThan (Get-StageOrder -Name 'Reindex')
    }
  }

  It 'runs the read-only health checks last' {
    $script:Catalog[-1].Name | Should -Be 'HealthChecks'
    $script:Catalog[-1].AltersDatabase | Should -BeFalse
  }

  It 'carries no cadence: every stage runs on every run' {
    @($script:Catalog[0].PSObject.Properties.Name) | Should -Be @('Name', 'Order', 'AltersDatabase')
  }
}
