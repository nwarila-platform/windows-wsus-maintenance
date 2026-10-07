#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# The repository ignores everything that .gitignore does not allowlist. A file that is ignored by
#   mistake is silently left out of every commit, so a workflow could call a script that was never
#   committed. These tests ask git which of the repository's source, test, documentation and
#   workflow files, and of the files the workflows refer to, its ignore rules would leave out.
#   `git check-ignore --no-index` judges the rules alone, whether or not a file is tracked yet:
#   https://git-scm.com/docs/git-check-ignore

Describe 'files the repository must track' {
  BeforeAll {
    $script:Root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:InCheckout = $False
    If ($Null -ne (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue)) {
      $Inside = & git -C $script:Root rev-parse --is-inside-work-tree 2>$Null
      $script:InCheckout = ($LASTEXITCODE -eq 0) -and ([System.String]$Inside -eq 'true')
    }

    # Relative, forward-slash paths of the existing files under the given folders.
    Function script:Get-RepositoryFile {
      Param ([System.String[]]$Folder)
      ForEach ($Name In $Folder) {
        $Base = Join-Path -Path $script:Root -ChildPath $Name
        If (Test-Path -LiteralPath $Base) {
          Get-ChildItem -LiteralPath $Base -File -Recurse -Force | ForEach-Object -Process {
            $PSItem.FullName.Substring($script:Root.Length).TrimStart('\', '/').Replace('\', '/')
          }
        }
      }
    }

    # The existing repository files a workflow names, for example a script it runs or a schema it
    #   publishes; build outputs are left out, since they are generated and never tracked.
    Function script:Get-WorkflowReference {
      $Pattern = '(?<![\w$])(?:\.[\\/])?((?:\.github|src|tests|docs|analyzers)[\\/][\w.\\/-]+\.(?:ps1|psm1|psd1|json|ya?ml|md)|build\.ps1)'
      ForEach ($Workflow In @(Get-ChildItem -LiteralPath (Join-Path -Path $script:Root -ChildPath '.github/workflows') -File)) {
        ForEach ($Match In [System.Text.RegularExpressions.Regex]::Matches((Get-Content -LiteralPath $Workflow.FullName -Raw), $Pattern)) {
          $Path = $Match.Groups[1].Value.Replace('\', '/')
          If (Test-Path -LiteralPath (Join-Path -Path $script:Root -ChildPath $Path) -PathType Leaf) {
            $Path
          }
        }
      }
    }

    # The paths among the given ones that the ignore rules leave out.
    Function script:Get-IgnoredPath {
      Param ([System.String[]]$Path)
      $Ignored = @($Path | & git -C $script:Root check-ignore --no-index --stdin)
      # Exit code 1 means no path is ignored, 0 that some are; anything else is a failure of git.
      If (@(0, 1) -notcontains $LASTEXITCODE) {
        Throw ('git check-ignore failed with exit code {0}.' -f $LASTEXITCODE)
      }

      $Ignored | Where-Object -FilterScript { -not [System.String]::IsNullOrWhiteSpace($PSItem) }
    }
  }

  It 'tracks every file under src, tests, docs and .github (skipped outside a git checkout)' {
    If ($script:InCheckout -eq $False) {
      Set-ItResult -Skipped -Because 'the tree is not a git checkout, or git is not installed'
    }

    $Files = @(Get-RepositoryFile -Folder @('src', 'tests', 'docs', '.github'))
    $Files.Count | Should -BeGreaterThan 100
    @(Get-IgnoredPath -Path $Files) | Should -HaveCount 0 -Because 'every one of these files belongs in the repository; allowlist it in .gitignore'
  }

  It 'tracks every repository file a workflow refers to (skipped outside a git checkout)' {
    If ($script:InCheckout -eq $False) {
      Set-ItResult -Skipped -Because 'the tree is not a git checkout, or git is not installed'
    }

    $References = @(Get-WorkflowReference | Select-Object -Unique)
    $References | Should -Contain '.github/scripts/live-lane/Install-SqlExpress.ps1'
    $References | Should -Contain '.github/scripts/Assert-SealedDigest.ps1'
    $References | Should -Contain 'build.ps1'
    @(Get-IgnoredPath -Path $References) | Should -HaveCount 0 -Because 'a workflow must not call a file that is never committed; allowlist it in .gitignore'
  }

  It 'still ignores what is not allowlisted, such as build output (skipped outside a git checkout)' {
    If ($script:InCheckout -eq $False) {
      Set-ItResult -Skipped -Because 'the tree is not a git checkout, or git is not installed'
    }

    @(Get-IgnoredPath -Path @('build/Invoke-WsusMaintenance.ps1', 'notes.txt')) | Should -Be @('build/Invoke-WsusMaintenance.ps1', 'notes.txt')
  }
}
