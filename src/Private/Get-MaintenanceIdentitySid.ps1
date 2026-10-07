#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceIdentitySid {
  <#
    .SYNOPSIS
        Returns the security identifier of the run identity.

    .DESCRIPTION
        A seam around System.Security.Principal.WindowsIdentity, so that tests can replace it. Folder
        protection trusts this identifier besides SYSTEM and Administrators.

    .EXAMPLE
        Get-MaintenanceIdentitySid

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenanceidentitysid',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceIdentitySid] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

  $Result
  Write-Debug -Message:'[Get-MaintenanceIdentitySid] Exiting'
}
