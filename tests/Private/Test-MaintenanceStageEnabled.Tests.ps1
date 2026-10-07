#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceStageEnabled' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:New-Configuration {
      Param ([System.String]$Json = '{}')
      $Document = $Json | ConvertFrom-Json
      $Document | Add-Member -NotePropertyName 'schemaVersion' -NotePropertyValue 1 -Force
      If ($Null -eq $Document.PSObject.Properties['backup']) {
        $Document | Add-Member -NotePropertyName 'backup' -NotePropertyValue ([PSCustomObject]@{ destination = 'H:\B' })
      }
      ConvertTo-MaintenanceEffectiveConfiguration -Document $Document
    }
  }

  It 'enables every stage the defaults turn on, and only those' {
    $Configuration = New-Configuration
    $Enabled = @(Get-MaintenanceStageCatalog | Where-Object -FilterScript { Test-MaintenanceStageEnabled -Configuration $Configuration -Name $PSItem.Name }).Name

    $Enabled | Should -Be @('Backup', 'CustomIndexes', 'DeleteUpdateFix', 'SupersededDecline', 'ExpiredDecline', 'ObsoleteUpdates', 'BuiltInCleanup', 'SyncHistory', 'StaleComputers', 'Reindex', 'IisLogRetention', 'ArtifactRetention', 'HealthChecks')
  }

  It 'follows each stage''s own switch' {
    $Configuration = New-Configuration -Json '{ "backup": { "enabled": false }, "reindex": { "enabled": false }, "declinedDeletion": { "enabled": true }, "declines": { "accelerated": { "enabled": true, "classifications": [ "Definition Updates" ], "ageDays": 1 } } }'

    Test-MaintenanceStageEnabled -Configuration $Configuration -Name 'Backup' | Should -BeFalse
    Test-MaintenanceStageEnabled -Configuration $Configuration -Name 'Reindex' | Should -BeFalse
    Test-MaintenanceStageEnabled -Configuration $Configuration -Name 'DeclinedDeletion' | Should -BeTrue
    Test-MaintenanceStageEnabled -Configuration $Configuration -Name 'AcceleratedDecline' | Should -BeTrue
  }

  It 'enables the built-in cleanup only when an option is on' {
    $Off = New-Configuration -Json '{ "builtInCleanup": { "declineSupersededUpdates": false, "declineExpiredUpdates": false, "obsoleteUpdates": false, "compressUpdates": false, "obsoleteComputers": false, "unneededContentFiles": false } }'
    $One = New-Configuration -Json '{ "builtInCleanup": { "declineSupersededUpdates": false, "declineExpiredUpdates": false, "obsoleteUpdates": false, "compressUpdates": true, "obsoleteComputers": false, "unneededContentFiles": false } }'

    Test-MaintenanceStageEnabled -Configuration $Off -Name 'BuiltInCleanup' | Should -BeFalse
    Test-MaintenanceStageEnabled -Configuration $One -Name 'BuiltInCleanup' | Should -BeTrue
  }

  It 'enables the health checks only when a check is on' {
    $Off = New-Configuration -Json '{ "health": { "tls": { "enabled": false }, "certificateExpiry": { "enabled": false }, "strongCrypto": { "enabled": false }, "appPool": { "enabled": false }, "supersededCount": { "enabled": false }, "processorCount": { "enabled": false } } }'

    Test-MaintenanceStageEnabled -Configuration $Off -Name 'HealthChecks' | Should -BeFalse
  }

  It 'enables rule declines only for an enabled rule outside a disabled group' {
    $NoRules = New-Configuration
    $Ungrouped = New-Configuration -Json '{ "declines": { "rules": [ { "name": "A", "enabled": true, "condition": { "field": "Title", "operator": "Contains", "value": "x" } } ] } }'
    $DisabledRule = New-Configuration -Json '{ "declines": { "rules": [ { "name": "A", "enabled": false, "condition": { "field": "Title", "operator": "Contains", "value": "x" } } ] } }'
    $DisabledGroup = New-Configuration -Json '{ "declines": { "groups": [ { "name": "G", "enabled": false } ], "rules": [ { "name": "A", "enabled": true, "group": "g", "condition": { "field": "Title", "operator": "Contains", "value": "x" } } ] } }'
    $EnabledGroup = New-Configuration -Json '{ "declines": { "groups": [ { "name": "G", "enabled": true } ], "rules": [ { "name": "A", "enabled": true, "group": "G", "condition": { "field": "Title", "operator": "Contains", "value": "x" } } ] } }'

    Test-MaintenanceStageEnabled -Configuration $NoRules -Name 'RuleDecline' | Should -BeFalse
    Test-MaintenanceStageEnabled -Configuration $Ungrouped -Name 'RuleDecline' | Should -BeTrue
    Test-MaintenanceStageEnabled -Configuration $DisabledRule -Name 'RuleDecline' | Should -BeFalse
    Test-MaintenanceStageEnabled -Configuration $DisabledGroup -Name 'RuleDecline' | Should -BeFalse
    Test-MaintenanceStageEnabled -Configuration $EnabledGroup -Name 'RuleDecline' | Should -BeTrue
  }

  It 'reports an unknown stage as disabled' {
    Test-MaintenanceStageEnabled -Configuration (New-Configuration) -Name 'Defrag' | Should -BeFalse
  }
}
