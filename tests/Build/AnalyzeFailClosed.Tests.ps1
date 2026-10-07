#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-Analyze fails closed without PSScriptAnalyzer' {
  BeforeAll {
    $script:ProjectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:BuildPath = Join-Path -Path $script:ProjectRoot -ChildPath 'build.ps1'
    $script:BuildText = Get-Content -LiteralPath $script:BuildPath -Raw

    $Pattern = '(?ms)^Function Invoke-Analyze \{.*?(?=^Function [A-Za-z0-9-]+ \{|\z)'
    $Match = [System.Text.RegularExpressions.Regex]::Match($script:BuildText, $Pattern)
    if (-not $Match.Success) {
      throw 'Invoke-Analyze function not found in build.ps1.'
    }

    $script:AnalyzeBlock = $Match.Value
  }

  It 'throws when PSScriptAnalyzer is absent' {
    # CI always has PSScriptAnalyzer installed, so the absent path is never
    # exercised at runtime; assert on the source so the silent degrade cannot return.
    $script:AnalyzeBlock | Should -Match 'If \(\$Null -eq \$AnalyzerModule\) \{\s+Throw '
    $script:AnalyzeBlock | Should -Match 'PSScriptAnalyzer is required for analysis\. Install PSScriptAnalyzer 1\.25\.0\.'
  }

  It 'does not silently degrade to syntax-only' {
    $script:AnalyzeBlock | Should -Not -Match 'Syntax validation passed\.'
    $script:AnalyzeBlock | Should -Not -Match 'PSScriptAnalyzer is not installed'
  }
}
