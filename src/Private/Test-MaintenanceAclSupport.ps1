#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceAclSupport {
  <#
    .SYNOPSIS
        Tells whether this host has Windows access control lists.

    .DESCRIPTION
        A seam around the platform check that folder protection depends on. The script runs on Windows,
        where this is always true; the test suite replaces it to exercise folder protection on any
        platform with stand-ins for the access-control seams.

    .EXAMPLE
        Test-MaintenanceAclSupport

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceaclsupport',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param ()

  Write-Debug -Message:'[Test-MaintenanceAclSupport] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Result = $False

  [System.Boolean]$Result = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

  $Result
  Write-Debug -Message:'[Test-MaintenanceAclSupport] Exiting'
}
