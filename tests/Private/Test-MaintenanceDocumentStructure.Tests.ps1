#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceDocumentStructure' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Rules = @(Get-MaintenanceConfigurationRule)
  }

  It 'accepts a document that uses only known keys' {
    $Document = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration/full-valid.json') -Raw | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule $script:Rules -UnknownKeyPolicy 'Error'

    $Result.Errors | Should -HaveCount 0
    $Result.Warnings | Should -HaveCount 0
  }

  It 'reports an unknown key as an error under the Error policy' {
    $Document = '{ "backup": { "minimumKpet": 7 } }' | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule $script:Rules -UnknownKeyPolicy 'Error'

    $Result.Errors | Should -Be @('backup.minimumKpet: is not a configuration key.')
  }

  It 'reports an unknown key as a warning under the Warning policy' {
    $Document = '{ "mystery": 1 }' | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule $script:Rules -UnknownKeyPolicy 'Warning'

    $Result.Errors | Should -HaveCount 0
    $Result.Warnings | Should -Be @('mystery: is not a configuration key.')
  }

  It 'suggests the right casing for a near miss' {
    $Document = '{ "run": { "DryRun": true } }' | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule $script:Rules -UnknownKeyPolicy 'Error'

    $Result.Errors | Should -Be @("run.DryRun: is not a configuration key; keys are case-sensitive (did you mean 'dryRun'?).")
  }

  It 'requires sections to be objects' {
    $Document = '{ "backup": [ 1 ] }' | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule $script:Rules -UnknownKeyPolicy 'Error'

    $Result.Errors | Should -Be @('backup: must be an object (got [1]).')
  }

  It 'still refuses a plain-text secret under an unknown key whatever the policy' {
    $Document = '{ "mail": { "password": "hunter2" } }' | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule $script:Rules -UnknownKeyPolicy 'Warning'

    $Result.Errors | Should -HaveCount 1
    $Result.Errors[0] | Should -BeLike 'mail.password: looks like a plain-text secret*'
  }

  It 'reports a deprecated key with its replacement' {
    $Deprecated = [PSCustomObject]@{
      Path = 'run.oldName'; Type = 'Boolean'; Required = $False; HasDefault = $True; Default = $False; Nullable = $False
      Minimum = $Null; Maximum = $Null; AllowedValues = [System.String[]]@(); Pattern = ''; Unique = $False; NonEmpty = $False
      Unit = ''; Description = 'Old name.'; ReplacedBy = 'run.dryRun'
    }
    $Document = '{ "run": { "oldName": true } }' | ConvertFrom-Json
    $Result = Test-MaintenanceDocumentStructure -Node $Document -Rule (@($script:Rules) + @($Deprecated)) -UnknownKeyPolicy 'Error'

    $Result.Errors | Should -HaveCount 0
    $Result.Warnings | Should -Be @("run.oldName: is deprecated; use 'run.dryRun' instead.")
  }
}
