#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Wait-MaintenanceInterval {
  <#
    .SYNOPSIS
        Waits for a number of seconds.

    .DESCRIPTION
        A seam around Start-Sleep, so that tests of the synchronization guard can replace the wait and
        run without delay.

    .PARAMETER Seconds
        Seconds to wait.

    .EXAMPLE
        Wait-MaintenanceInterval -Seconds 10

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#wait-maintenanceinterval',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 86400)]
    [System.Int32]
    $Seconds
  )

  Write-Debug -Message:'[Wait-MaintenanceInterval] Entering'

  If ($Seconds -gt 0) {
    Start-Sleep -Seconds:$Seconds
  }

  Write-Debug -Message:'[Wait-MaintenanceInterval] Exiting'
}
