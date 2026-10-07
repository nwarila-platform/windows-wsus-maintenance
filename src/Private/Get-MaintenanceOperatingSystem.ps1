#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceOperatingSystem {
  <#
    .SYNOPSIS
        Returns the operating system the script runs on.

    .DESCRIPTION
        A seam around System.Environment.OSVersion, so that tests can replace it. The build number
        identifies the Windows Server release: 14393 is Windows Server 2016, 17763 Windows Server 2019,
        20348 Windows Server 2022 and 26100 Windows Server 2025.

    .EXAMPLE
        Get-MaintenanceOperatingSystem

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenanceoperatingsystem',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceOperatingSystem] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = [PSCustomObject]@{
    Platform = [System.String][System.Environment]::OSVersion.Platform
    Major    = [System.Int32][System.Environment]::OSVersion.Version.Major
    Build    = [System.Int32][System.Environment]::OSVersion.Version.Build
  }

  $Result
  Write-Debug -Message:'[Get-MaintenanceOperatingSystem] Exiting'
}
