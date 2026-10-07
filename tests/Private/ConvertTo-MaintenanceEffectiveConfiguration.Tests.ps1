#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'ConvertTo-MaintenanceEffectiveConfiguration' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration'
  }

  It 'fills every key the document omits with its default' {
    $Document = Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json')
    $Effective = ConvertTo-MaintenanceEffectiveConfiguration -Document $Document

    $Effective.schemaVersion | Should -Be 1
    $Effective.backup.destination | Should -Be 'H:\SUSDB'
    $Effective.backup.minimumKept | Should -Be 7
    $Effective.syncHistory.retentionDays | Should -Be 90
    $Effective.backup.maximumAgeDays | Should -Be 7
    $Effective.declines.superseded.ageDays | Should -Be 90
    $Effective.discovery.sqlInstance | Should -BeNullOrEmpty
    $Effective.health.certificateExpiry.warningDays | Should -Be @(60, 30, 14, 7)
    $Effective.eventLog.eventIds.runStarted | Should -Be 1000
    @($Effective.declines.rules) | Should -HaveCount 0
  }

  It 'keeps the document''s values and structures' {
    $Document = Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'full-valid.json')
    $Effective = ConvertTo-MaintenanceEffectiveConfiguration -Document $Document

    $Effective.staleComputers.action | Should -Be 'Move'
    $Effective.declines.rules[0].name | Should -Be 'Itanium and ARM64'
    $Effective.customIndexes.additional[0].columns | Should -Be @('ColumnA', 'ColumnB')
    $Effective.discovery.sqlInstance | Should -Be 'WSUS01\SQLEXPRESS'
  }

  It 'accepts an explicit catalogue' {
    $Rules = @(Get-MaintenanceConfigurationRule | Where-Object -FilterScript { $PSItem.Path -in @('schemaVersion', 'run.dryRun') })
    $Effective = ConvertTo-MaintenanceEffectiveConfiguration -Document ('{ "schemaVersion": 1 }' | ConvertFrom-Json) -Rule $Rules

    @($Effective.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'run')
    $Effective.run.dryRun | Should -BeFalse
  }
}
