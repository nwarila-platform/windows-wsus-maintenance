#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceConfiguration' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration'

    Function script:Test-Fixture {
      Param ([System.String]$Name)
      $Document = Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath $Name)
      Test-MaintenanceConfiguration -Document $Document
    }
  }

  It 'accepts the <Name> fixture' -ForEach @(
    @{ Name = 'minimal-valid.json' }
    @{ Name = 'full-valid.json' }
  ) {
    $Result = Test-Fixture -Name $Name

    $Result.PSTypeNames[0] | Should -Be 'WsusMaintenance.ConfigurationValidation'
    $Result.IsValid | Should -BeTrue
    $Result.Errors | Should -HaveCount 0
    $Result.Warnings | Should -HaveCount 0
  }

  It 'reports three independent errors together in one run' {
    $Result = Test-Fixture -Name 'three-errors.json'

    $Result.IsValid | Should -BeFalse
    $Result.Errors | Should -Be @(
      'run.connectionTimeoutSeconds: must be from 1 to 600 (got 601).'
      'backup.minimumKept: must be from 0 to 1000 (got -1).'
      'report.formats[0]: must be one of Text, Html (got "Pdf").'
    )
  }

  It 'rejects a document carrying an expression instead of evaluating it' {
    $Result = Test-Fixture -Name 'expression.json'

    $Result.IsValid | Should -BeFalse
    $Result.Errors -join "`n" | Should -BeLike '*iisLogs.siteName: contains PowerShell expression syntax*'
  }

  It 'rejects a plain-text secret' {
    $Result = Test-Fixture -Name 'plaintext-secret.json'

    $Result.Errors -join "`n" | Should -BeLike '*mail.smtpPassword: looks like a plain-text secret*'
  }

  It 'handles a misspelt key according to the unknown-key policy' {
    $Strict = Test-Fixture -Name 'misspelt-key.json'
    $Lenient = Test-Fixture -Name 'misspelt-key-warning.json'

    $Strict.IsValid | Should -BeFalse
    $Strict.Errors | Should -Be @('backup.minimumKpet: is not a configuration key.')
    $Lenient.IsValid | Should -BeTrue
    $Lenient.Warnings | Should -Be @('backup.minimumKpet: is not a configuration key.')
  }

  It 'reports an unsupported schema version as a version mismatch' {
    (Test-Fixture -Name 'unsupported-version.json').Errors |
      Should -Be @('schemaVersion: version 2 is not supported; this release reads version 1.')
  }

  It 'includes the cross-field rules' {
    $Result = Test-MaintenanceConfiguration -Document ('{ "schemaVersion": 1 }' | ConvertFrom-Json)

    $Result.IsValid | Should -BeFalse
    $Result.Errors | Should -Be @('backup.destination: is required when backup.enabled is true.')
  }

  It 'requires the schema version' {
    $Result = Test-MaintenanceConfiguration -Document ('{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 } }' | ConvertFrom-Json)

    $Result.Errors | Should -Be @('schemaVersion: is required.')
  }

  It 'reports a malformed schema version through its type check' {
    $Result = Test-MaintenanceConfiguration -Document ('{ "schemaVersion": "1", "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 } }' | ConvertFrom-Json)

    $Result.Errors | Should -Be @('schemaVersion: must be a whole number (got "1").')
  }

  It 'accepts an explicit catalogue' {
    $Rules = @(Get-MaintenanceConfigurationRule | Where-Object -FilterScript { $PSItem.Path -eq 'schemaVersion' })

    (Test-MaintenanceConfiguration -Document ('{ "schemaVersion": 1 }' | ConvertFrom-Json) -Rule $Rules).IsValid | Should -BeTrue
  }
}
