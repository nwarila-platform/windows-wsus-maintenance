#Requires -Version 7.0
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Validates the lane's configuration document and every summary the runs wrote against the
      published schemas.

  .DESCRIPTION
      Uses Test-Json, which PowerShell 7 provides
      (https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/test-json);
      Windows PowerShell 5.1 has no equivalent, so this step runs under pwsh.

  .PARAMETER SchemaFolder
      Folder holding maintenance.schema.json and summary.schema.json.
#>
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $True)][System.String]$SchemaFolder
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'LiveLane.Common.ps1')

Write-LaneNote -Text ''
Write-LaneNote -Text '## Schemas'
$Configuration = Get-Content -LiteralPath $Script:LaneConfigPath -Raw
Assert-LaneCondition -Condition (Test-Json -Json $Configuration -SchemaFile (Join-Path -Path $SchemaFolder -ChildPath 'maintenance.schema.json')) -Message 'the configuration document validates against maintenance.schema.json'

$Summaries = @(Get-ChildItem -LiteralPath (Join-Path -Path $Script:LaneDataFolder -ChildPath 'Summaries') -Filter 'WsusMaintenance-*.json' -File)
Assert-LaneCondition -Condition ($Summaries.Count -gt 0) -Message ('the runs wrote {0} summaries' -f $Summaries.Count)
ForEach ($File In $Summaries) {
  $Valid = Test-Json -Json (Get-Content -LiteralPath $File.FullName -Raw) -SchemaFile (Join-Path -Path $SchemaFolder -ChildPath 'summary.schema.json') -ErrorAction SilentlyContinue
  Assert-LaneCondition -Condition ($Valid -eq $True) -Message ('{0} validates against summary.schema.json' -f $File.Name)
}
