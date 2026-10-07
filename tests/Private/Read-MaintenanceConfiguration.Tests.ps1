#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Read-MaintenanceConfiguration' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration'
  }

  It 'parses a JSON object document' {
    $Document = Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json')

    $Document.schemaVersion | Should -Be 1
    $Document.backup.destination | Should -Be 'H:\SUSDB'
  }

  It 'refuses a <Case> document with ConfigurationInvalid' -ForEach @(
    @{ Case = 'missing'; File = 'does-not-exist.json'; Message = '*does not exist*' }
    @{ Case = 'empty'; File = 'empty.json'; Message = '*is empty*' }
    @{ Case = 'malformed'; File = 'not-json.json'; Message = '*is not valid JSON*' }
    @{ Case = 'non-object'; File = 'array-top.json'; Message = '*one JSON object at the top level*' }
  ) {
    $Path = Join-Path -Path $script:FixtureRoot -ChildPath $File

    { Read-MaintenanceConfiguration -Path $Path } |
      Should -Throw -ErrorId 'ConfigurationInvalid,New-ErrorRecord' -ExpectedMessage $Message
  }

  It 'reports an unreadable document with ConfigurationInvalid' {
    Mock -CommandName Get-Content -MockWith {
      Throw 'Access to the path is denied.'
    }

    { Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') } |
      Should -Throw -ErrorId 'ConfigurationInvalid,New-ErrorRecord' -ExpectedMessage '*could not be read*denied*'
  }

  It 'never evaluates expression text inside a value' {
    $Document = Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'expression.json')

    $Document.iisLogs.siteName | Should -BeLike '$(Remove-Item*'
  }
}
