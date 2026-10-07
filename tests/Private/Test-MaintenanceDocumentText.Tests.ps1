#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceDocumentText' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'accepts ordinary data, including regular expressions with anchors' {
    $Value = '{ "rules": [ { "value": "^KB[0-9]+$" } ], "folder": "%ProgramData%\\x", "count": 3, "on": true, "none": null }' | ConvertFrom-Json

    @(Test-MaintenanceDocumentText -Path '' -Value $Value) | Should -HaveCount 0
  }

  It 'refuses expression syntax anywhere in the tree and locates it' {
    $Value = '{ "a": { "b": [ "fine", "${env:SystemRoot}" ] }, "c": "$(Get-Date)" }' | ConvertFrom-Json
    $Errors = @(Test-MaintenanceDocumentText -Path '' -Value $Value)

    $Errors | Should -HaveCount 2
    $Errors[0] | Should -BeLike 'a.b`[1`]: contains PowerShell expression syntax*'
    $Errors[1] | Should -BeLike 'c: contains PowerShell expression syntax*'
  }

  It 'refuses credential-named keys that hold text' {
    $Value = '{ "smtp": { "password": "hunter2", "apiKey": "abc", "tokenName": "", "privateKey": null } }' | ConvertFrom-Json
    $Errors = @(Test-MaintenanceDocumentText -Path 'root' -Value $Value)

    $Errors | Should -HaveCount 2
    $Errors[0] | Should -BeLike 'root.smtp.password: looks like a plain-text secret*'
    $Errors[1] | Should -BeLike 'root.smtp.apiKey: looks like a plain-text secret*'
  }
}
