#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceEntryArray' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:Test-Entries {
      Param ([System.String]$Type, [System.String]$Json)
      @(Test-MaintenanceEntryArray -Path 'a' -Type $Type -Value ($Json | ConvertFrom-Json))
    }
  }

  It 'accepts valid <Type> entries' -ForEach @(
    @{ Type = 'IndexArray'; Json = '{ "v": [ { "name": "nclOne", "table": "tbRevision", "columns": [ "RevisionID" ] } ] }' }
    @{ Type = 'GroupArray'; Json = '{ "v": [ { "name": "Architectures", "enabled": false } ] }' }
    @{ Type = 'RuleArray'; Json = '{ "v": [ { "name": "Previews", "enabled": true, "group": "G", "condition": { "field": "Title", "operator": "Contains", "value": "Preview" } } ] }' }
  ) {
    @(Test-MaintenanceEntryArray -Path 'a' -Type $Type -Value (($Json | ConvertFrom-Json).v)) | Should -HaveCount 0
  }

  It 'accepts an empty array' {
    @(Test-MaintenanceEntryArray -Path 'a' -Type 'RuleArray' -Value @()) | Should -HaveCount 0
  }

  It 'refuses a value that is not an array' {
    Test-Entries -Type 'GroupArray' -Json '{ "name": "G", "enabled": true }' | Should -BeLike '*must be an array*'
  }

  It 'refuses an entry that is not an object' {
    @(Test-MaintenanceEntryArray -Path 'a' -Type 'GroupArray' -Value @('G')) | Should -BeLike '*each entry must be an object*'
  }

  It 'reports missing and unknown keys' {
    $Errors = (@(Test-MaintenanceEntryArray -Path 'a' -Type 'RuleArray' -Value (('{ "v": [ { "name": "R", "priority": 1 } ] }' | ConvertFrom-Json).v)) -join "`n")

    $Errors | Should -BeLike '*a`[0`].priority: is not a key of this entry*'
    $Errors | Should -BeLike '*a`[0`].enabled: is required*'
    $Errors | Should -BeLike '*a`[0`].condition: is required*'
  }

  It 'refuses a group or rule name with surrounding whitespace' {
    $Value = ('{ "v": [ { "name": " Previews", "enabled": true } ] }' | ConvertFrom-Json).v

    @(Test-MaintenanceEntryArray -Path 'g' -Type 'GroupArray' -Value @($Value)) | Should -BeLike 'g`[0`].name: has an invalid format*'
  }

  It 'refuses duplicate names regardless of case' {
    $Value = ('{ "v": [ { "name": "Previews", "enabled": true }, { "name": "PREVIEWS", "enabled": true } ] }' | ConvertFrom-Json).v

    @(Test-MaintenanceEntryArray -Path 'declines.groups' -Type 'GroupArray' -Value $Value) | Should -BeLike "*the name 'PREVIEWS' is used more than once*"
  }

  It 'validates each field of an entry' {
    $Value = ('{ "v": [ { "name": "bad name!", "table": "", "columns": [ "A", "A" ] }, { "name": "R", "enabled": "yes", "group": " ", "tier": "Periodic", "condition": { "field": "Nope" } } ] }' | ConvertFrom-Json).v
    $IndexErrors = (@(Test-MaintenanceEntryArray -Path 'i' -Type 'IndexArray' -Value @($Value[0])) -join "`n")
    $RuleErrors = (@(Test-MaintenanceEntryArray -Path 'r' -Type 'RuleArray' -Value @($Value[1])) -join "`n")

    $IndexErrors | Should -BeLike '*i`[0`].name: has an invalid format*'
    $IndexErrors | Should -BeLike '*i`[0`].table: must be a non-empty string*'
    $IndexErrors | Should -BeLike '*i`[0`].columns: contains the duplicate entry*'
    $RuleErrors | Should -BeLike '*r`[0`].enabled: must be true or false*'
    $RuleErrors | Should -BeLike '*r`[0`].group: must be a non-empty string*'
    $RuleErrors | Should -BeLike '*r`[0`].tier: is not a key of this entry.*'
    $RuleErrors | Should -BeLike '*r`[0`].condition.field*'
  }
}
