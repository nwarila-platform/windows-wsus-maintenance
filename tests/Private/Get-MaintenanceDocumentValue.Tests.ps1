#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceDocumentValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Document = '{ "backup": { "minimumKept": 7, "destination": null }, "schemaVersion": 1 }' | ConvertFrom-Json
  }

  It 'finds a nested value' {
    $Result = Get-MaintenanceDocumentValue -Document $script:Document -Path 'backup.minimumKept'

    $Result.Found | Should -BeTrue
    $Result.Value | Should -Be 7
  }

  It 'finds an explicit null as present' {
    $Result = Get-MaintenanceDocumentValue -Document $script:Document -Path 'backup.destination'

    $Result.Found | Should -BeTrue
    $Result.Value | Should -BeNullOrEmpty
  }

  It 'reports an absent key' {
    (Get-MaintenanceDocumentValue -Document $script:Document -Path 'backup.gate').Found | Should -BeFalse
  }

  It 'matches keys case-sensitively' {
    (Get-MaintenanceDocumentValue -Document $script:Document -Path 'Backup.minimumKept').Found | Should -BeFalse
  }

  It 'reports a path through a non-object value as absent' {
    (Get-MaintenanceDocumentValue -Document $script:Document -Path 'schemaVersion.major').Found | Should -BeFalse
  }
}
