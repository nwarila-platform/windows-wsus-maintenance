# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ProjectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$FunctionsFile = Join-Path -Path $ProjectRoot -ChildPath 'build/Invoke-WsusMaintenance.Functions.ps1'
$ReleaseFile = Join-Path -Path $ProjectRoot -ChildPath 'build/Invoke-WsusMaintenance.ps1'

if (-not (Test-Path -LiteralPath $FunctionsFile)) {
  throw ('Functions artifact missing: {0}' -f $FunctionsFile)
}

if (-not (Test-Path -LiteralPath $ReleaseFile)) {
  throw ('Release artifact missing: {0}' -f $ReleaseFile)
}

. $FunctionsFile

@(
  'ConvertTo-MaintenanceConfigurationSchema',
  'ConvertTo-MaintenanceEffectiveConfiguration',
  'Get-MaintenanceConfigurationRule',
  'Get-MaintenanceStageCatalog',
  'Get-MaintenanceStagePlan',
  'Invoke-MaintenanceRun',
  'Invoke-MaintenanceStage',
  'Invoke-WsusMaintenance',
  'New-ErrorRecord',
  'New-MaintenanceReport',
  'New-MaintenanceRunResult',
  'Read-MaintenanceConfiguration',
  'Resolve-MaintenanceOverride',
  'Test-MaintenanceConfiguration',
  'Write-MaintenanceEvent',
  'Write-MaintenanceLog',
  'Write-MaintenanceSummary'
) | ForEach-Object -Process {
  if ($Null -eq (Get-Command -Name $PSItem -CommandType Function -ErrorAction SilentlyContinue)) {
    throw ('Expected function not found: {0}' -f $PSItem)
  }
}

$PowerShellCommandName = 'powershell.exe'
if ($PSVersionTable.PSEdition -eq 'Core') {
  $PowerShellCommandName = 'pwsh'
}

$PowerShellCommand = Get-Command -Name $PowerShellCommandName -ErrorAction Stop

function Invoke-ReleaseScript {
  param (
    [System.String[]]
    $ScriptArgument = @()
  )

  $Arguments = [System.Collections.Generic.List[System.String]]::new()
  $Arguments.Add('-NoLogo')
  $Arguments.Add('-NoProfile')
  $Arguments.Add('-NonInteractive')

  if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    $Arguments.Add('-ExecutionPolicy')
    $Arguments.Add('Bypass')
  }

  $Arguments.Add('-File')
  $Arguments.Add($ReleaseFile)
  foreach ($Item in $ScriptArgument) {
    $Arguments.Add($Item)
  }

  $Null = & $PowerShellCommand.Source @Arguments 2>&1
  $LASTEXITCODE
}

$HelpExitCode = Invoke-ReleaseScript -ScriptArgument @('-?')
if ($HelpExitCode -ne 0) {
  throw ('Release script help smoke failed with exit code {0}.' -f $HelpExitCode)
}

$FixtureRoot = Join-Path -Path $ProjectRoot -ChildPath 'tests/Fixtures/Configuration'
@(
  @{ File = 'full-valid.json'; Expected = 0 }
  @{ File = 'misspelt-key-warning.json'; Expected = 2 }
  @{ File = 'three-errors.json'; Expected = 4 }
  @{ File = 'does-not-exist.json'; Expected = 4 }
) | ForEach-Object -Process {
  $ExitCode = Invoke-ReleaseScript -ScriptArgument @('-ConfigPath', (Join-Path -Path $FixtureRoot -ChildPath $PSItem.File), '-ValidateOnly')
  if ($ExitCode -ne $PSItem.Expected) {
    throw ('Release script -ValidateOnly smoke for {0} exited {1}; expected {2}.' -f $PSItem.File, $ExitCode, $PSItem.Expected)
  }
}

$ExitCode = Invoke-ReleaseScript -ScriptArgument @('-ConfigPath', (Join-Path -Path $FixtureRoot -ChildPath 'minimal-valid.json'), '-Stage', 'NoSuchStage', '-ValidateOnly')
if ($ExitCode -ne 4) {
  throw ('Release script unknown-stage smoke exited {0}; expected 4.' -f $ExitCode)
}

# A real run needs an elevated Windows session on a WSUS server. Without elevation the script
#   stops with PreconditionFailed (3) at the elevation check; elevated on a computer without WSUS
#   it stops with PreconditionFailed (3) at environment discovery. Either way it changes nothing
#   and leaves a log, a failure report and a summary. On another platform no configured Windows
#   folder is usable, so the run stops at its log (3) and writes nothing.
$IsElevatedWindows = $False
if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
  $Principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
  $IsElevatedWindows = $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$IsWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$SmokeRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('wsus-maintenance-smoke-{0}' -f [System.Guid]::NewGuid().ToString('N'))
$Null = New-Item -ItemType Directory -Path $SmokeRoot -Force
try {
  $SmokeConfig = Join-Path -Path $SmokeRoot -ChildPath 'maintenance.json'
  $Configuration = @{
    schemaVersion = 1
    backup        = @{ destination = 'H:\SUSDB' }
    eventLog      = @{ enabled = $False }
  }
  if ($IsWindowsHost) {
    $Configuration['report'] = @{ folder = (Join-Path -Path $SmokeRoot -ChildPath 'Reports') }
    $Configuration['log'] = @{ folder = (Join-Path -Path $SmokeRoot -ChildPath 'Logs') }
    $Configuration['summary'] = @{ folder = (Join-Path -Path $SmokeRoot -ChildPath 'Summaries') }
  }
  Set-Content -LiteralPath $SmokeConfig -Value (ConvertTo-Json -Depth 4 -InputObject $Configuration) -Encoding UTF8

  $HasWsus = $IsWindowsHost -and (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup')
  $ExitCode = Invoke-ReleaseScript -ScriptArgument @('-ConfigPath', $SmokeConfig)
  if (($IsElevatedWindows -and $HasWsus) -eq $False) {
    if ($ExitCode -ne 3) {
      throw ('Release script run smoke exited {0}; expected 3.' -f $ExitCode)
    }
  } elseif ($ExitCode -gt 3) {
    throw ('Release script run smoke on a WSUS server exited {0}; expected 0 to 3.' -f $ExitCode)
  }

  if ($IsWindowsHost) {
    $Written = @(Get-ChildItem -LiteralPath $SmokeRoot -Recurse -File -Filter 'WsusMaintenance-*' | ForEach-Object -Process { $PSItem.Extension })
    # A completed run and a failure report both leave a log, two reports and a summary.
    $ExpectedFiles = @('.html', '.json', '.log', '.txt')
    if ((@($Written | Sort-Object) -join ',') -ne ($ExpectedFiles -join ',')) {
      throw ('Release script run smoke wrote {0}; expected {1}.' -f (@($Written | Sort-Object) -join ','), ($ExpectedFiles -join ','))
    }
  }
} finally {
  Remove-Item -LiteralPath $SmokeRoot -Recurse -Force -ErrorAction SilentlyContinue
}
