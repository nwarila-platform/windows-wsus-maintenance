#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceDisplayValue {
  <#
    .SYNOPSIS
        Renders a configuration value for a validation message.

    .DESCRIPTION
        Formats any parsed JSON value as compact JSON text, truncated so one oversized
        value cannot flood the error list.

    .PARAMETER Value
        The value to render.

    .EXAMPLE
        ConvertTo-MaintenanceDisplayValue -Value 42

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenancedisplayvalue',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Value
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceDisplayValue] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Rendered = [System.String]::Empty
  [System.String]$Private:Result = [System.String]::Empty

  If ($Null -eq $Value) {
    $Rendered = 'null'
  } Else {
    $Rendered = ConvertTo-Json -InputObject:$Value -Compress -Depth:4
  }

  If ($Rendered.Length -gt 80) {
    $Rendered = $Rendered.Substring(0, 77) + '...'
  }

  [System.String]$Result = $Rendered
  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceDisplayValue] Exiting'
}
