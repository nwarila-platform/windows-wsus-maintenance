#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $True)]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $Path,

  [Parameter(Mandatory = $True)]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $ExpectedDigest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
  throw ('Sealed artifact not found: {0}' -f $Path)
}

$ExpectedDigestNormalized = $ExpectedDigest.Trim().ToLowerInvariant()
if ($ExpectedDigestNormalized -notmatch '^[0-9a-f]{64}$') {
  throw ('Expected SHA-256 digest must be 64 lowercase hexadecimal characters after normalization: {0}' -f $ExpectedDigest)
}

$ActualDigest = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
if ($ActualDigest -ne $ExpectedDigestNormalized) {
  throw ('Sealed digest mismatch for {0}: expected {1}; actual {2}.' -f $Path, $ExpectedDigestNormalized, $ActualDigest)
}