#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceStagePlan' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Configuration = ConvertTo-MaintenanceEffectiveConfiguration -Document ('{ "schemaVersion": 1, "backup": { "destination": "H:\\B" } }' | ConvertFrom-Json)
    $script:CatalogOrder = @(Get-MaintenanceStageCatalog).Name

    Function script:Get-Entry {
      Param ($Plan, [System.String]$Name)
      $Plan | Where-Object -FilterScript { $PSItem.Name -eq $Name }
    }
  }

  It 'lists every stage in catalogue order, with or without -Stage' -ForEach @(
    @{ Splat = @{} }
    @{ Splat = @{ Stage = @('Reindex', 'Backup') } }
  ) {
    $Plan = @(Get-MaintenanceStagePlan -Configuration $script:Configuration @Splat)

    $Plan.Name | Should -Be $script:CatalogOrder
    For ($Index = 1; $Index -lt $Plan.Count; $Index++) {
      $Plan[$Index].Order | Should -BeGreaterThan $Plan[$Index - 1].Order
    }
  }

  It 'runs every enabled stage on every run' {
    $Plan = @(Get-MaintenanceStagePlan -Configuration $script:Configuration)

    @($Plan | Where-Object -FilterScript { $PSItem.Mode -eq 'Run' }) | Should -HaveCount 13
    @($Plan | Where-Object -FilterScript { $PSItem.Mode -eq 'Skip' }).Name | Should -Be @('AcceleratedDecline', 'RuleDecline', 'DeclinedDeletion')
    (Get-Entry -Plan $Plan -Name 'SupersededDecline').Mode | Should -Be 'Run'
    (Get-Entry -Plan $Plan -Name 'Reindex').Reason | Should -Be 'enabled'
    (Get-Entry -Plan $Plan -Name 'DeclinedDeletion').Reason | Should -Be 'disabled by configuration'
  }

  It 'runs exactly the listed stages and nothing else' {
    $Plan = @(Get-MaintenanceStagePlan -Configuration $script:Configuration -Stage @('SupersededDecline', 'ExpiredDecline'))

    @($Plan | Where-Object -FilterScript { $PSItem.Mode -eq 'Run' }).Name | Should -Be @('SupersededDecline', 'ExpiredDecline')
    (Get-Entry -Plan $Plan -Name 'Backup').Reason | Should -Be 'not listed with -Stage'
    (Get-Entry -Plan $Plan -Name 'ExpiredDecline').Reason | Should -Be 'listed with -Stage'
  }

  It 'skips a listed stage that configuration disables' {
    $Plan = @(Get-MaintenanceStagePlan -Configuration $script:Configuration -Stage @('AcceleratedDecline', 'DeclinedDeletion', 'Reindex'))

    (Get-Entry -Plan $Plan -Name 'AcceleratedDecline').Mode | Should -Be 'Skip'
    (Get-Entry -Plan $Plan -Name 'DeclinedDeletion').Reason | Should -Be 'disabled by configuration'
    (Get-Entry -Plan $Plan -Name 'Reindex').Mode | Should -Be 'Run'
  }

  It 'carries each stage''s backup-gate flag and no cadence' {
    $Plan = @(Get-MaintenanceStagePlan -Configuration $script:Configuration)

    (Get-Entry -Plan $Plan -Name 'ObsoleteUpdates').AltersDatabase | Should -BeTrue
    (Get-Entry -Plan $Plan -Name 'HealthChecks').AltersDatabase | Should -BeFalse
    @($Plan[0].PSObject.Properties.Name) | Should -Be @('Name', 'Order', 'AltersDatabase', 'Mode', 'Reason', 'Missing')
  }

  It 'skips every decline stage on a replica, stating the reason' {
    $Configuration = ConvertTo-MaintenanceEffectiveConfiguration -Document ('{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }, "declines": { "accelerated": { "enabled": true, "classifications": [ "Drivers" ], "ageDays": 30 } }, "declinedDeletion": { "enabled": true } }' | ConvertFrom-Json)

    $Plan = @(Get-MaintenanceStagePlan -Configuration $Configuration -Tier 'Replica')

    ForEach ($Name In @('SupersededDecline', 'AcceleratedDecline', 'ExpiredDecline', 'DeclinedDeletion')) {
      (Get-Entry -Plan $Plan -Name $Name).Mode | Should -Be 'Skip' -Because $Name
      (Get-Entry -Plan $Plan -Name $Name).Reason | Should -Be 'skipped: replica' -Because $Name
    }
    (Get-Entry -Plan $Plan -Name 'ObsoleteUpdates').Mode | Should -Be 'Run'
    (Get-Entry -Plan $Plan -Name 'StaleComputers').Mode | Should -Be 'Run'
  }

  It 'skips the decline stages when the tier is unknown, and gates nothing for other tiers' {
    (Get-Entry -Plan @(Get-MaintenanceStagePlan -Configuration $script:Configuration -Tier 'Unknown') -Name 'SupersededDecline').Reason | Should -Be 'skipped: server role unknown'
    (Get-Entry -Plan @(Get-MaintenanceStagePlan -Configuration $script:Configuration -Tier 'Autonomous') -Name 'SupersededDecline').Mode | Should -Be 'Run'
    (Get-Entry -Plan @(Get-MaintenanceStagePlan -Configuration $script:Configuration -Tier 'TopTier') -Name 'SupersededDecline').Mode | Should -Be 'Run'
  }

  It 'skips the stale-computer stage on a <Tier> server only when it moves computers into a group' -ForEach @(
    @{ Tier = 'Replica'; Reason = 'skipped: replica' }
    @{ Tier = 'Unknown'; Reason = 'skipped: server role unknown' }
  ) {
    $Move = ConvertTo-MaintenanceEffectiveConfiguration -Document ('{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }, "staleComputers": { "action": "Move", "targetGroup": "Stale" } }' | ConvertFrom-Json)

    (Get-Entry -Plan @(Get-MaintenanceStagePlan -Configuration $Move -Tier $Tier) -Name 'StaleComputers').Reason | Should -Be $Reason
    (Get-Entry -Plan @(Get-MaintenanceStagePlan -Configuration $Move -Tier 'Autonomous') -Name 'StaleComputers').Mode | Should -Be 'Run'
    (Get-Entry -Plan @(Get-MaintenanceStagePlan -Configuration $script:Configuration -Tier $Tier) -Name 'StaleComputers').Mode | Should -Be 'Run'
  }

  It 'skips a stage whose database permissions are missing and names them' {
    $Plan = @(Get-MaintenanceStagePlan -Configuration $script:Configuration -MissingPermission @{ Backup = @('BACKUP DATABASE'); DeclinedDeletion = @('EXECUTE on dbo.spDeleteUpdate') })

    (Get-Entry -Plan $Plan -Name 'Backup').Mode | Should -Be 'Skip'
    (Get-Entry -Plan $Plan -Name 'Backup').Reason | Should -Be 'skipped: missing permission: BACKUP DATABASE'
    (Get-Entry -Plan $Plan -Name 'Backup').Missing | Should -Be @('BACKUP DATABASE')
    (Get-Entry -Plan $Plan -Name 'DeclinedDeletion').Reason | Should -Be 'disabled by configuration'
    (Get-Entry -Plan $Plan -Name 'DeclinedDeletion').Missing | Should -HaveCount 0
    (Get-Entry -Plan $Plan -Name 'Reindex').Missing | Should -HaveCount 0
  }
}
