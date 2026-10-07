#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceIdentity {
  <#
    .SYNOPSIS
        Returns the name of the identity the run uses.

    .DESCRIPTION
        A seam around System.Security.Principal.WindowsIdentity, so that tests can replace it. Every
        report records the run identity. Where no Windows identity is available the user and domain names
        of the process are used.

    .EXAMPLE
        Get-MaintenanceIdentity

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenanceidentity',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceIdentity] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  Try {
    [System.String]$Result = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  } Catch {
    [System.String]$Result = '{0}\{1}' -f [System.Environment]::UserDomainName, [System.Environment]::UserName
  }

  $Result
  Write-Debug -Message:'[Get-MaintenanceIdentity] Exiting'
}
