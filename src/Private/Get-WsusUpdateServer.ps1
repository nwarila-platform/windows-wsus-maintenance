#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-WsusUpdateServer.Missing' = 'The WSUS administration API (Microsoft.UpdateServices.Administration) is not installed on this computer.'
}

Function Get-WsusUpdateServer {
  <#
    .SYNOPSIS
        Connects to the WSUS administration interface.

    .DESCRIPTION
        A seam around Microsoft.UpdateServices.Administration.AdminProxy.GetUpdateServer, so that tests
        can replace it. Without a host name it connects to the local WSUS server; with one it connects to
        that host on the given port, over TLS when asked. Throws when the WSUS administration API is not
        installed or the connection fails.

    .PARAMETER HostName
        Host to connect to; empty for the local WSUS server.

    .PARAMETER Port
        Port, with a host name.

    .PARAMETER UseTls
        Whether to use TLS, with a host name.

    .EXAMPLE
        Get-WsusUpdateServer

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-wsusupdateserver',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Object])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $HostName = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 65535)]
    [System.Int32]
    $Port = 0,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Boolean]
    $UseTls = $False
  )

  Write-Debug -Message:'[Get-WsusUpdateServer] Entering'

  # Initialize Variable(s)
  [System.Type]$Private:Proxy = $Null
  [System.Object]$Private:Result = $Null

  If ($Null -eq [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.UpdateServices.Administration')) {
    Throw $Script:Message['Get-WsusUpdateServer.Missing']
  }

  $Proxy = 'Microsoft.UpdateServices.Administration.AdminProxy' -as [System.Type]
  If ([System.String]::IsNullOrEmpty($HostName) -eq $True) {
    [System.Object]$Result = $Proxy::GetUpdateServer()
  } Else {
    [System.Object]$Result = $Proxy::GetUpdateServer($HostName, $UseTls, $Port)
  }

  $Result
  Write-Debug -Message:'[Get-WsusUpdateServer] Exiting'
}
