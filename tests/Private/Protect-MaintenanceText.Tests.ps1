#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Protect-MaintenanceText and Register-MaintenanceSecret' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  BeforeEach {
    $Script:MaintenanceSecret.Clear()
  }

  It 'returns text without secrets unchanged' {
    Protect-MaintenanceText -Text 'Reindex rebuilt 3 indexes.' | Should -Be 'Reindex rebuilt 3 indexes.'
  }

  It 'returns an empty string for empty or null text' {
    Protect-MaintenanceText -Text '' | Should -Be ''
    Protect-MaintenanceText -Text $Null | Should -Be ''
  }

  It 'replaces every registered secret, the longest first' {
    Register-MaintenanceSecret -Value 'pa55'
    Register-MaintenanceSecret -Value 'pa55word!'
    Register-MaintenanceSecret -Value ''

    Protect-MaintenanceText -Text 'a pa55word! b pa55 c' | Should -Be 'a [REDACTED] b [REDACTED] c'
    $Script:MaintenanceSecret.Count | Should -Be 2
  }

  It 'redacts a password in connection-string form up to the end of its value' -ForEach @(
    @{ Text = 'Server=db;Password=abc;Database=SUSDB'; Expected = 'Server=db;Password=[REDACTED];Database=SUSDB' }
    @{ Text = 'pwd = "a;b" next'; Expected = 'pwd = [REDACTED] next' }
    @{ Text = "line one Password=x`r`nline two"; Expected = "line one Password=[REDACTED]`r`nline two" }
  ) {
    Protect-MaintenanceText -Text $Text | Should -Be $Expected
  }

  It 'redacts the value of a credential-named JSON key' {
    $Json = '{"mail":{"smtpPassword":"x\"y","apiToken":"t"},"name":"keep"}'

    Protect-MaintenanceText -Text $Json | Should -Be '{"mail":{"smtpPassword":"[REDACTED]","apiToken":"[REDACTED]"},"name":"keep"}'
  }
}
