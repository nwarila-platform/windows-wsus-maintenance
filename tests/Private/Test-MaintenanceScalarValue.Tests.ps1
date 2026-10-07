#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceIntegerValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'accepts a whole number in range' {
    @(Test-MaintenanceIntegerValue -Minimum 1 -Maximum 31 -Path 'p' -Value 31) | Should -HaveCount 0
    @(Test-MaintenanceIntegerValue -Minimum 1 -Maximum 31 -Path 'p' -Value ([System.Int64]1)) | Should -HaveCount 0
  }

  It 'accepts any whole number when no bounds are given' {
    @(Test-MaintenanceIntegerValue -Path 'p' -Value (-5)) | Should -HaveCount 0
  }

  It 'refuses <Case>' -ForEach @(
    @{ Case = 'a boolean'; Value = $True }
    @{ Case = 'a fraction'; Value = 1.5 }
    @{ Case = 'quoted digits'; Value = '7' }
    @{ Case = 'null'; Value = $Null }
  ) {
    @(Test-MaintenanceIntegerValue -Minimum 0 -Maximum 10 -Path 'p' -Value $Value) | Should -BeLike '*must be a whole number*'
  }

  It 'refuses values outside the range and names the bounds' {
    Test-MaintenanceIntegerValue -Minimum 1 -Maximum 600 -Path 'run.connectionTimeoutSeconds' -Value 601 |
      Should -Be 'run.connectionTimeoutSeconds: must be from 1 to 600 (got 601).'
    Test-MaintenanceIntegerValue -Minimum 1 -Path 'p' -Value 0 | Should -Be 'p: must be from 1 to any (got 0).'
    Test-MaintenanceIntegerValue -Maximum 5 -Path 'p' -Value 6 | Should -Be 'p: must be from any to 5 (got 6).'
  }
}

Describe 'Test-MaintenanceStringValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'accepts an allowed value and a matching pattern' {
    @(Test-MaintenanceStringValue -AllowedValues @('Replace', 'Append') -Path 'p' -Value 'Append') | Should -HaveCount 0
    @(Test-MaintenanceStringValue -Pattern '^[a-z]+$' -Path 'p' -Value 'en') | Should -HaveCount 0
  }

  It 'refuses an empty, whitespace or non-string value' {
    @(Test-MaintenanceStringValue -Path 'p' -Value '') | Should -BeLike '*non-empty string*'
    @(Test-MaintenanceStringValue -Path 'p' -Value '  ') | Should -BeLike '*non-empty string*'
    @(Test-MaintenanceStringValue -Path 'p' -Value 3) | Should -BeLike '*non-empty string*'
  }

  It 'matches allowed values case-sensitively and never corrects them' {
    Test-MaintenanceStringValue -AllowedValues @('Replace', 'Append') -Path 'backup.sameDay' -Value 'replace' |
      Should -Be 'backup.sameDay: must be one of Replace, Append (got "replace").'
  }

  It 'refuses a value that does not match the pattern' {
    @(Test-MaintenanceStringValue -Pattern '^[a-z]+$' -Path 'p' -Value 'EN') | Should -BeLike '*invalid format*'
  }
}

Describe 'Test-MaintenancePathValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Pattern = (Get-MaintenanceConfigurationRule | Where-Object -FilterScript { $PSItem.Path -eq 'report.folder' }).Pattern
  }

  It 'accepts <Value>' -ForEach @(
    @{ Value = 'H:\SUSDB' }
    @{ Value = 'C:\' }
    @{ Value = '\\server\share\backups' }
    @{ Value = '%ProgramData%\NWarila\WsusMaintenance\Reports' }
    @{ Value = '%ProgramFiles(x86)%\Tool' }
  ) {
    @(Test-MaintenancePathValue -Path 'p' -Pattern $script:Pattern -Value $Value) | Should -HaveCount 0
  }

  It 'refuses <Value>' -ForEach @(
    @{ Value = 'relative\folder' }
    @{ Value = 'H:\logs\*.log' }
    @{ Value = 'H:\logs\..\Windows' }
    @{ Value = 'H:\logs\..' }
    @{ Value = '/var/log' }
    @{ Value = 'H:\a:b' }
    @{ Value = 42 }
  ) {
    @(Test-MaintenancePathValue -Path 'p' -Pattern $script:Pattern -Value $Value) | Should -BeLike '*absolute Windows path*'
  }
}
