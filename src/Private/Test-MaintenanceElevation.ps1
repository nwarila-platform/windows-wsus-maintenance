#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceElevation {
  <#
    .SYNOPSIS
        Reports whether the run is elevated or runs as LocalSystem.

    .DESCRIPTION
        True when the current Windows identity is LocalSystem or holds the built-in
        Administrators role in its token. The WSUS administration interface, IIS
        configuration reads and the protected data folders all require one of the two.
        Throws where no Windows identity exists, which the caller reports as a
        precondition failure.

    .EXAMPLE
        Test-MaintenanceElevation

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceelevation',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param ()

  Write-Debug -Message:'[Test-MaintenanceElevation] Entering'

  # Initialize Variable(s)
  [System.Security.Principal.WindowsIdentity]$Private:Identity = $Null
  [System.Security.Principal.WindowsPrincipal]$Private:Principal = $Null
  [System.Boolean]$Private:Result = $False

  $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)

  [System.Boolean]$Result = (
    $Identity.IsSystem -or
    $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  )
  $Result
  Write-Debug -Message:'[Test-MaintenanceElevation] Exiting'
}
