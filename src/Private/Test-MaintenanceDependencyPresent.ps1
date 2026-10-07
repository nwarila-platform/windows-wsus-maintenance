#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceDependencyPresent {
  <#
    .SYNOPSIS
        Tells whether one dependency of the script is present on this server.

    .DESCRIPTION
        A seam around the presence checks, so that tests can replace them. WsusApi: the WSUS
        administration assembly (Microsoft.UpdateServices.Administration), which the WSUS role installs
        in the global assembly cache. SqlClient: the System.Data.SqlClient provider of the .NET
        Framework. IisConfiguration: the IIS configuration file applicationHost.config. Only installed
        components are looked at; nothing is downloaded, installed or loaded from any other location.

    .PARAMETER Name
        The dependency to look for.

    .EXAMPLE
        Test-MaintenanceDependencyPresent -Name 'IisConfiguration'

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancedependencypresent',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('WsusApi', 'SqlClient', 'IisConfiguration')]
    [System.String]
    $Name
  )

  Write-Debug -Message:'[Test-MaintenanceDependencyPresent] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Result = $False

  Switch ($Name) {
    'WsusApi' {
      [System.Boolean]$Result = $Null -ne [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.UpdateServices.Administration')
    }
    'SqlClient' {
      [System.Boolean]$Result = $Null -ne ('System.Data.SqlClient.SqlConnection' -as [System.Type])
    }
    Default {
      [System.Boolean]$Result = [System.IO.File]::Exists([System.Environment]::ExpandEnvironmentVariables('%windir%\System32\inetsrv\config\applicationHost.config'))
    }
  }

  $Result
  Write-Debug -Message:'[Test-MaintenanceDependencyPresent] Exiting'
}
