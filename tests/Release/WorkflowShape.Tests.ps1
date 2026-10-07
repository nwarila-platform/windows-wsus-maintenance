#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'release workflow shape' {
  BeforeAll {
    $script:ProjectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:WorkflowPath = Join-Path -Path $script:ProjectRoot -ChildPath '.github/workflows/release.yaml'
    $script:WorkflowText = Get-Content -LiteralPath $script:WorkflowPath -Raw
    $script:JobNames = [System.String[]]@('seal', 'validate', 'release', 'provenance')

    Function script:Get-WorkflowJobBlock {
      Param (
        [Parameter(Mandatory = $True)]
        [System.String]
        $Name
      )

      $EscapedName = [System.Text.RegularExpressions.Regex]::Escape($Name)
      $Pattern = '(?ms)^  ' + $EscapedName + ':\r?\n.*?(?=^  [A-Za-z0-9_-]+:\r?\n|\z)'
      $Match = [System.Text.RegularExpressions.Regex]::Match($script:WorkflowText, $Pattern)
      if (-not $Match.Success) {
        throw ('Workflow job not found: {0}' -f $Name)
      }

      $Match.Value
    }
  }

  It 'keeps seal read-only and module-free' {
    $Seal = Get-WorkflowJobBlock -Name 'seal'

    $Seal | Should -Match '(?ms)permissions:\s*\r?\n\s+contents:\s+read'
    $Seal | Should -Not -Match 'Install-Module'
    $Seal | Should -Match 'build\.ps1 -Task Build'
  }

  It 'keeps validate as the only module-installing job' {
    $JobsWithInstall = foreach ($JobName in $script:JobNames) {
      if ((Get-WorkflowJobBlock -Name $JobName) -match 'Install-Module') {
        $JobName
      }
    }

    $JobsWithInstall = [System.String[]]@($JobsWithInstall)
    $JobsWithInstall | Should -HaveCount 1
    $JobsWithInstall[0] | Should -Be 'validate'
  }

  It 'keeps validation and release on downloaded release candidates' {
    $Validate = Get-WorkflowJobBlock -Name 'validate'
    $Release = Get-WorkflowJobBlock -Name 'release'

    $Validate | Should -Match 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
    $Validate | Should -Match 'name:\s+release-candidate'
    $Release | Should -Match 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093'
    $Release | Should -Match 'name:\s+release-candidate'
  }

  It 'uploads release candidates only from seal' {
    $Seal = Get-WorkflowJobBlock -Name 'seal'

    $Seal | Should -Match 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
    $Seal | Should -Match 'name:\s+release-candidate'

    foreach ($JobName in @('validate', 'release')) {
      (Get-WorkflowJobBlock -Name $JobName) | Should -Not -Match 'actions/upload-artifact@'
    }
  }

  It 'keeps the load-bearing job graph' {
    (Get-WorkflowJobBlock -Name 'validate') | Should -Match 'needs:\s+seal'
    (Get-WorkflowJobBlock -Name 'release') | Should -Match 'needs:\s+\[seal,\s*validate\]'
    (Get-WorkflowJobBlock -Name 'provenance') | Should -Match 'needs:\s+\[seal,\s*release\]'
  }

  It 'publishes a non-draft release on ubuntu via native gh bound to the sealed digest' {
    $Release = Get-WorkflowJobBlock -Name 'release'

    # The release job does no Windows work (download + verify + publish), so it runs on ubuntu
    # with bash and the native gh CLI -- the PowerShell wrapper was what crashed gh's stderr probe.
    $Release | Should -Match 'runs-on:\s+ubuntu-latest'
    $Release | Should -Match 'set -euo pipefail'
    $Release | Should -Match 'gh release create'
    $Release | Should -Not -Match 'softprops/action-gh-release'
    $Release | Should -Not -Match '--draft'

    # The sealed-digest binding is preserved natively: sha256sum -c against the seal's digest.
    $Release | Should -Match 'sha256sum -c'
    $Release | Should -Match 'SEALED_DIGEST'
    $Release | Should -Match 'needs\.seal\.outputs\.digest'

    $Release | Should -Match 'build/Invoke-WsusMaintenance\.ps1'
    $Release | Should -Match 'build/Invoke-WsusMaintenance\.ps1\.sha256'
  }

  It 'lets the generator attach provenance to the published release' {
    # With upload-assets: true + upload-tag-name the SLSA generator's own softprops step attaches
    # the .intoto.jsonl to the tag's release (already published by the release job) without
    # clobbering the notes or the .ps1/.sha256, so no bespoke finalize job is needed.
    $Provenance = Get-WorkflowJobBlock -Name 'provenance'

    $Provenance | Should -Match 'generator_generic_slsa3\.yml@v2\.1\.0'
    $Provenance | Should -Match 'base64-subjects:\s+\$\{\{\s*needs\.seal\.outputs\.hashes\s*\}\}'
    $Provenance | Should -Match 'upload-assets:\s+true'
    $Provenance | Should -Not -Match 'upload-assets:\s+false'
    $Provenance | Should -Match 'upload-tag-name:\s+\$\{\{\s*github\.ref_name\s*\}\}'
    $Provenance | Should -Match 'needs:\s+\[seal,\s*release\]'
    $Provenance | Should -Match 'contents:\s+write'
  }
}
