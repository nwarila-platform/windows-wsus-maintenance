#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceAccountName {
  <#
    .SYNOPSIS
        Names the account behind a security identifier.

    .DESCRIPTION
        Translates the identifier to its account name (for example BUILTIN\Users); when it cannot be
        translated, for example for a deleted account, returns the identifier itself.

    .PARAMETER Sid
        Security identifier to name.

    .EXAMPLE
        ConvertTo-MaintenanceAccountName -Sid ([System.Security.Principal.SecurityIdentifier]'S-1-5-32-545')

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenanceaccountname',
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
    [ValidateNotNull()]
    [System.Security.Principal.SecurityIdentifier]
    $Sid
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceAccountName] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  Try {
    [System.String]$Result = $Sid.Translate([System.Security.Principal.NTAccount]).Value
  } Catch {
    [System.String]$Result = $Sid.Value
  }

  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceAccountName] Exiting'
}
