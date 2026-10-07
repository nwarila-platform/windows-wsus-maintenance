#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-IisConfiguration {
  <#
    .SYNOPSIS
        Reads the IIS configuration of this server.

    .DESCRIPTION
        A seam around %windir%\System32\inetsrv\config\applicationHost.config, so that tests can replace
        it. Returns the document as XML, read only; nothing is written. Throws when IIS is not
        installed or the file cannot be read.

    .EXAMPLE
        Get-IisConfiguration

    .OUTPUTS
        [System.Xml.XmlDocument]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-iisconfiguration',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Xml.XmlDocument])]
  Param ()

  Write-Debug -Message:'[Get-IisConfiguration] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Path = [System.String]::Empty
  [System.Xml.XmlDocument]$Private:Result = $Null

  $Path = [System.Environment]::ExpandEnvironmentVariables('%windir%\System32\inetsrv\config\applicationHost.config')
  [System.Xml.XmlDocument]$Result = [System.Xml.XmlDocument]::new()
  $Result.Load($Path)

  $Result
  Write-Debug -Message:'[Get-IisConfiguration] Exiting'
}
