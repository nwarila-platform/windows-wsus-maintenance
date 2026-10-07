#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceTrustedSid {
  <#
    .SYNOPSIS
        Lists the principals that may change the folders of the script.

    .DESCRIPTION
        Returns the security identifiers of SYSTEM (S-1-5-18), the local Administrators group
        (S-1-5-32-544) and the run identity, without repeats. Folders the script creates grant full
        control to exactly these, and an existing folder that lets anybody else write is not used.

    .EXAMPLE
        Get-MaintenanceTrustedSid

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancetrustedsid',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceTrustedSid] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Trusted = $Null
  [System.String[]]$Private:Result = @()

  $Trusted = [System.Collections.Generic.List[System.String]]::new()
  ForEach ($Sid In @('S-1-5-18', 'S-1-5-32-544', (Get-MaintenanceIdentitySid))) {
    If ($Trusted.Contains($Sid) -eq $False) {
      $Trusted.Add($Sid)
    }
  }

  [System.String[]]$Result = $Trusted.ToArray()

  $Result
  Write-Debug -Message:'[Get-MaintenanceTrustedSid] Exiting'
}
