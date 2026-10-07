#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceDefaultConfigurationPath {
  <#
    .SYNOPSIS
        Returns the fixed default location of the configuration document.

    .DESCRIPTION
        The configuration document is read from -ConfigPath when it is given and from
        this one fixed path otherwise: maintenance.json under
        %ProgramData%\NWarila\WsusMaintenance.

    .EXAMPLE
        Get-MaintenanceDefaultConfigurationPath

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancedefaultconfigurationpath',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceDefaultConfigurationPath] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ProgramData = [System.String]::Empty
  [System.String]$Private:Result = [System.String]::Empty

  $ProgramData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)

  [System.String]$Result = [System.IO.Path]::Combine($ProgramData, 'NWarila', 'WsusMaintenance', 'maintenance.json')
  $Result
  Write-Debug -Message:'[Get-MaintenanceDefaultConfigurationPath] Exiting'
}
