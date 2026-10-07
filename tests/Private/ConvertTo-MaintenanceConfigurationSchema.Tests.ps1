#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'ConvertTo-MaintenanceConfigurationSchema' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:PublishedPath = Join-Path -Path $PSScriptRoot -ChildPath '../../docs/reference/maintenance.schema.json'
    $script:Schema = ConvertTo-MaintenanceConfigurationSchema | ConvertFrom-Json

    Function script:Get-SchemaNode {
      Param ([System.String]$Path)
      $Node = $script:Schema
      ForEach ($Segment In $Path.Split('.')) {
        $Node = $Node.properties.$Segment
      }
      $Node
    }
  }

  It 'matches the published schema document exactly' {
    # Compared after one parse and re-serialization in the same runtime, so indentation and
    #   escaping differences between PowerShell editions cannot mask or fake a change.
    $Generated = ConvertTo-MaintenanceConfigurationSchema | ConvertFrom-Json | ConvertTo-Json -Depth 64 -Compress
    $Published = Get-Content -LiteralPath $script:PublishedPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 64 -Compress

    $Published | Should -Be $Generated
  }

  It 'declares draft-07, a closed top level and the required schema version' {
    $script:Schema.'$schema' | Should -Be 'http://json-schema.org/draft-07/schema#'
    $script:Schema.additionalProperties | Should -BeFalse
    $script:Schema.required | Should -Be @('schemaVersion')
  }

  It 'describes every catalogue key' {
    ForEach ($Rule In @(Get-MaintenanceConfigurationRule)) {
      Get-SchemaNode -Path $Rule.Path | Should -Not -BeNullOrEmpty -Because $Rule.Path
    }
  }

  It 'renders types, ranges, enumerations, units, nullability and defaults' {
    (Get-SchemaNode -Path 'backup.minimumKept').minimum | Should -Be 0
    (Get-SchemaNode -Path 'backup.minimumKept').maximum | Should -Be 1000
    (Get-SchemaNode -Path 'backup.minimumKept').default | Should -Be 7
    (Get-SchemaNode -Path 'backup.minimumKept').description | Should -BeLike '*Unit: files.'
    (Get-SchemaNode -Path 'backup.gate').enum | Should -Be @('Required', 'Advisory', 'Off')
    (Get-SchemaNode -Path 'backup.destination').type | Should -Be @('string', 'null')
    (Get-SchemaNode -Path 'report.formats').minItems | Should -Be 1
    (Get-SchemaNode -Path 'health.certificateExpiry.warningDays').items.maximum | Should -Be 3650
    $script:Schema.definitions.declineRule.properties.PSObject.Properties.Name | Should -Be @('name', 'enabled', 'group', 'condition')
    (Get-SchemaNode -Path 'declines.rules').items.'$ref' | Should -Be '#/definitions/declineRule'
    (Get-SchemaNode -Path 'declines.groups').items.'$ref' | Should -Be '#/definitions/declineGroup'
    (Get-SchemaNode -Path 'customIndexes.additional').items.'$ref' | Should -Be '#/definitions/customIndex'
    $script:Schema.definitions.condition.oneOf | Should -HaveCount 6
  }

  It 'marks a deprecated key with its replacement' {
    $Deprecated = [PSCustomObject]@{
      Path = 'run.oldName'; Type = 'Boolean'; Required = $False; HasDefault = $False; Default = $Null; Nullable = $False
      Minimum = $Null; Maximum = $Null; AllowedValues = [System.String[]]@(); Pattern = ''; Unique = $False; NonEmpty = $False
      Unit = ''; Description = 'Old name.'; ReplacedBy = 'run.dryRun'
    }
    $Schema = ConvertTo-MaintenanceConfigurationSchema -Rule @($Deprecated) | ConvertFrom-Json

    $Schema.properties.run.properties.oldName.description | Should -Be 'Old name. Deprecated: use run.dryRun.'
    $Schema.required | Should -HaveCount 0
  }
}
