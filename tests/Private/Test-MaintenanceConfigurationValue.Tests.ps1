#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceConfigurationValue' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Rules = @(Get-MaintenanceConfigurationRule)

    Function script:Test-Value {
      Param ([System.String]$Path, [System.Object]$Value)
      $Rule = $script:Rules | Where-Object -FilterScript { $PSItem.Path -ceq $Path }
      @(Test-MaintenanceConfigurationValue -Path $Path -Rule $Rule -Value $Value)
    }

    Function script:ConvertFrom-JsonValue {
      Param ([System.String]$Json)
      # The comma keeps an array value intact instead of letting the pipeline unroll it.
      , ('{ "v": ' + $Json + ' }' | ConvertFrom-Json).v
    }
  }

  It 'accepts null only for nullable keys' {
    Test-Value -Path 'backup.destination' -Value $Null | Should -HaveCount 0
    Test-Value -Path 'backup.enabled' -Value $Null | Should -BeLike '*must not be null*'
  }

  It 'checks booleans strictly' {
    Test-Value -Path 'backup.enabled' -Value $False | Should -HaveCount 0
    Test-Value -Path 'backup.enabled' -Value 'false' | Should -BeLike '*must be true or false*'
    Test-Value -Path 'backup.enabled' -Value 0 | Should -BeLike '*must be true or false*'
  }

  It 'checks integers, strings and paths through their validators' {
    Test-Value -Path 'backup.minimumKept' -Value 1001 | Should -BeLike '*from 0 to 1000*'
    Test-Value -Path 'backup.compression' -Value 'Sometimes' | Should -BeLike '*must be one of Auto, Always, Never*'
    Test-Value -Path 'report.folder' -Value 'reports' | Should -BeLike '*absolute Windows path*'
    Test-Value -Path 'discovery.sqlInstance' -Value 'WSUS01\SQLEXPRESS' | Should -HaveCount 0
    Test-Value -Path 'discovery.sqlInstance' -Value 'WSUS01\9bad' | Should -BeLike '*invalid format*'
  }

  It 'checks string arrays for type, allowed values, emptiness and duplicates' {
    Test-Value -Path 'report.formats' -Value (ConvertFrom-JsonValue -Json '[ "Text", "Html" ]') | Should -HaveCount 0
    Test-Value -Path 'report.formats' -Value 'Text' | Should -BeLike '*must be an array*'
    Test-Value -Path 'report.formats' -Value (ConvertFrom-JsonValue -Json '[]') | Should -BeLike '*must not be empty*'
    Test-Value -Path 'report.formats' -Value (ConvertFrom-JsonValue -Json '[ "Text", "Pdf" ]') | Should -BeLike 'report.formats`[1`]: must be one of*'
    Test-Value -Path 'declines.neverDecline' -Value (ConvertFrom-JsonValue -Json '[ "0000000A-0000-0000-0000-000000000001", "0000000a-0000-0000-0000-000000000001" ]') | Should -BeLike '*duplicate entry*'
  }

  It 'checks integer arrays for type, range, emptiness and duplicates' {
    Test-Value -Path 'health.certificateExpiry.warningDays' -Value (ConvertFrom-JsonValue -Json '[ 30, 7 ]') | Should -HaveCount 0
    Test-Value -Path 'health.certificateExpiry.warningDays' -Value 30 | Should -BeLike '*must be an array*'
    Test-Value -Path 'health.certificateExpiry.warningDays' -Value (ConvertFrom-JsonValue -Json '[ 0 ]') | Should -BeLike '*from 1 to 3650*'
    Test-Value -Path 'health.certificateExpiry.warningDays' -Value (ConvertFrom-JsonValue -Json '[ 7, 7 ]') | Should -BeLike '*duplicate entry 7*'
    Test-Value -Path 'health.certificateExpiry.warningDays' -Value (ConvertFrom-JsonValue -Json '[]') | Should -BeLike '*must not be empty*'
  }


  It 'delegates structured arrays to the entry validator' {
    Test-Value -Path 'declines.groups' -Value (ConvertFrom-JsonValue -Json '[ { "name": "G" } ]') | Should -BeLike '*enabled: is required*'
    Test-Value -Path 'customIndexes.additional' -Value (ConvertFrom-JsonValue -Json '{}') | Should -BeLike '*must be an array*'
  }
}
