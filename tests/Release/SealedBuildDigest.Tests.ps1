#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'sealed release build digest' {
  BeforeAll {
    $script:ProjectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:BuildScript = Join-Path -Path $script:ProjectRoot -ChildPath 'build.ps1'
    $script:ReleaseFile = Join-Path -Path $script:ProjectRoot -ChildPath 'build/Invoke-WsusMaintenance.ps1'
    $script:AssertDigestScript = Join-Path -Path $script:ProjectRoot -ChildPath '.github/scripts/Assert-SealedDigest.ps1'

    Function script:Get-ReleaseDigest {
      Param (
        [Parameter(Mandatory = $True)]
        [System.String]
        $Path
      )

      (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    }
  }

  It 'produces deterministic release script bytes across two builds' {
    $TempProjectRoot = Join-Path -Path $TestDrive -ChildPath 'deterministic-project'
    $TempSourceRoot = Join-Path -Path $TempProjectRoot -ChildPath 'src'
    $TempBuildScript = Join-Path -Path $TempProjectRoot -ChildPath 'build.ps1'
    $TempReleaseFile = Join-Path -Path $TempProjectRoot -ChildPath 'build/Invoke-WsusMaintenance.ps1'

    $Null = New-Item -Path $TempProjectRoot -ItemType Directory -Force
    Copy-Item -LiteralPath (Join-Path -Path $script:ProjectRoot -ChildPath 'src') -Destination $TempSourceRoot -Recurse
    Copy-Item -LiteralPath $script:BuildScript -Destination $TempBuildScript

    & $TempBuildScript -Task Build
    $FirstDigest = Get-ReleaseDigest -Path $TempReleaseFile

    & $TempBuildScript -Task Build
    $SecondDigest = Get-ReleaseDigest -Path $TempReleaseFile

    $SecondDigest | Should -Be $FirstDigest
  }

  It 'accepts the sealed release bytes' {
    $Digest = Get-ReleaseDigest -Path $script:ReleaseFile

    { & $script:AssertDigestScript -Path $script:ReleaseFile -ExpectedDigest $Digest } | Should -Not -Throw
  }

  It 'rejects a mutated copy of the sealed release bytes' {
    $Digest = Get-ReleaseDigest -Path $script:ReleaseFile
    $MutatedPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-WsusMaintenance.ps1'
    Copy-Item -LiteralPath $script:ReleaseFile -Destination $MutatedPath -Force
    [System.IO.File]::AppendAllText(
      $MutatedPath,
      "# mutation`n",
      [System.Text.UTF8Encoding]::new($False)
    )

    { & $script:AssertDigestScript -Path $MutatedPath -ExpectedDigest $Digest } |
      Should -Throw -ExpectedMessage '*Sealed digest mismatch*'
  }

  It 'keeps SLSA subject and sealed digest computations in agreement' {
    $Digest = Get-ReleaseDigest -Path $script:ReleaseFile
    $ArtifactName = Split-Path -Path $script:ReleaseFile -Leaf
    $Subject = '{0}  {1}{2}' -f $Digest, $ArtifactName, "`n"
    $Base64Subject = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Subject))
    $DecodedSubject = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64Subject))

    $DecodedSubject | Should -Be $Subject
    (($DecodedSubject -split '\s+')[0]) | Should -Be $Digest
  }
}