#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Collects the lane's evidence for upload: the script's logs, reports and summaries, its
      events, and the SQL Server setup and WSUS post-installation logs.

  .PARAMETER Destination
      Folder the evidence is copied to.
#>
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $True)][System.String]$Destination
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'LiveLane.Common.ps1')
$ErrorActionPreference = 'Continue'

$Null = New-Item -ItemType Directory -Path $Destination -Force
ForEach ($Name In @('Logs', 'Reports', 'Summaries')) {
  $Source = Join-Path -Path $Script:LaneDataFolder -ChildPath $Name
  If (Test-Path -LiteralPath $Source) {
    Copy-Item -LiteralPath $Source -Destination (Join-Path -Path $Destination -ChildPath $Name) -Recurse -Force
  }
}

If (Test-Path -LiteralPath $Script:LaneConfigPath) {
  Copy-Item -LiteralPath $Script:LaneConfigPath -Destination $Destination -Force
}

Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = $Script:LaneEventSource } -ErrorAction SilentlyContinue |
  Sort-Object -Property RecordId |
  Select-Object -Property TimeCreated, Id, LevelDisplayName, Message |
  ConvertTo-Json -Depth 3 |
  Set-Content -LiteralPath (Join-Path -Path $Destination -ChildPath 'events.json') -Encoding UTF8

ForEach ($Pattern In @('C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\Summary.txt', (Join-Path -Path $env:TEMP -ChildPath 'WSUS_PostInstall_*.log'))) {
  Get-ChildItem -Path $Pattern -ErrorAction SilentlyContinue | Copy-Item -Destination $Destination -Force
}
