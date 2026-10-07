#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceScriptPath {
  <#
    .SYNOPSIS
        Returns the path of the script file that is running.

    .DESCRIPTION
        A seam around the automatic variable PSCommandPath, so that tests can replace it. In the
        installed script it is the path of Invoke-WsusMaintenance.ps1, whose folder the installation
        check examines.

    .EXAMPLE
        Get-MaintenanceScriptPath

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancescriptpath',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceScriptPath] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = $PSCommandPath

  $Result
  Write-Debug -Message:'[Get-MaintenanceScriptPath] Exiting'
}
