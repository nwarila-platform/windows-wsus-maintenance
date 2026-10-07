#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'ConvertTo-MaintenanceByteText.Bytes' = '{0} bytes'
}

Function ConvertTo-MaintenanceByteText {
  <#
    .SYNOPSIS
        Writes a number of bytes in human-readable units.

    .DESCRIPTION
        Returns whole bytes below 1 KB, and otherwise the value in KB, MB, GB, TB or PB (powers of
        1024) with one decimal, formatted with the invariant culture.

    .PARAMETER Bytes
        Number of bytes.

    .EXAMPLE
        ConvertTo-MaintenanceByteText -Bytes 1610612736

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenancebytetext',
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
    [System.Int64]
    $Bytes
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceByteText] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Index = 0
  [System.String[]]$Private:Units = @('bytes', 'KB', 'MB', 'GB', 'TB', 'PB')
  [System.Double]$Private:Value = 0
  [System.String]$Private:Result = [System.String]::Empty

  $Value = [System.Double]$Bytes
  While (([System.Math]::Abs($Value) -ge 1024) -and ($Index -lt ($Units.Count - 1))) {
    $Value = $Value / 1024
    $Index++
  }

  If ($Index -eq 0) {
    [System.String]$Result = $Script:Message['ConvertTo-MaintenanceByteText.Bytes'] -f $Bytes
  } Else {
    [System.String]$Result = '{0} {1}' -f $Value.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $Units[$Index]
  }

  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceByteText] Exiting'
}
