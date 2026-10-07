#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'documentation stays in step with the source' {
  BeforeAll {
    $script:ProjectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path -Path $script:ProjectRoot -ChildPath 'build/Invoke-WsusMaintenance.Functions.ps1')
    $script:ConfigurationText = Get-Content -LiteralPath (Join-Path -Path $script:ProjectRoot -ChildPath 'docs/reference/configuration.md') -Raw
    $script:FunctionsText = Get-Content -LiteralPath (Join-Path -Path $script:ProjectRoot -ChildPath 'docs/reference/functions.md') -Raw
    $script:SourceFiles = @(
      Get-ChildItem -LiteralPath (Join-Path -Path $script:ProjectRoot -ChildPath 'src/Private') -Filter '*.ps1'
      Get-ChildItem -LiteralPath (Join-Path -Path $script:ProjectRoot -ChildPath 'src/Public') -Filter '*.ps1'
    )
  }

  It 'documents every configuration key' {
    ForEach ($Rule In @(Get-MaintenanceConfigurationRule)) {
      $script:ConfigurationText | Should -Match ([System.Text.RegularExpressions.Regex]::Escape(('| `{0}` |' -f $Rule.Path))) -Because $Rule.Path
    }
  }

  It 'gives every function a reference entry that its HelpUri points at' {
    ForEach ($File In $script:SourceFiles) {
      $Text = Get-Content -LiteralPath $File.FullName -Raw
      $Match = [System.Text.RegularExpressions.Regex]::Match($Text, '(?m)^Function ([A-Za-z-]+) \{')
      If ($Match.Success) {
        $Name = $Match.Groups[1].Value
        $script:FunctionsText | Should -Match ('(?m)^## {0}$' -f [System.Text.RegularExpressions.Regex]::Escape($Name)) -Because $Name
        $Text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape(('docs/reference/functions.md#{0}' -f $Name.ToLowerInvariant()))) -Because $Name
      }
    }
  }

  It 'keeps tracked text free of unsupported encodings and carriage returns in source' {
    ForEach ($File In $script:SourceFiles) {
      [System.IO.File]::ReadAllText($File.FullName) | Should -Not -Match "`r" -Because $File.Name
    }
  }
}
