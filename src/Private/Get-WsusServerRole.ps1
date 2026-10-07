#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-WsusServerRole.Autonomous'      = 'Autonomous downstream server'
  'Get-WsusServerRole.MicrosoftUpdate' = 'Microsoft Update'
  'Get-WsusServerRole.NoTls'           = 'no TLS'
  'Get-WsusServerRole.Replica'         = 'Replica downstream server'
  'Get-WsusServerRole.TopTier'         = 'Top-tier server'
  'Get-WsusServerRole.Unknown'         = 'not determined: {0}'
  'Get-WsusServerRole.Upstream'        = '{0}, port {1}, {2}'
}

Function Get-WsusServerRole {
  <#
    .SYNOPSIS
        Detects the server tier: top tier, autonomous downstream or replica downstream.

    .DESCRIPTION
        Reads IsReplicaServer and SyncFromMicrosoftUpdate from the server configuration on every run:
        a replica is a replica downstream server, a server that synchronizes from Microsoft Update is a
        top-tier server, and any other server is an autonomous downstream server. The upstream source is
        Microsoft Update or the upstream server's name, port and TLS setting. The script only reads these
        settings and never changes the replica setting. When the configuration cannot be read the tier is
        Unknown and Error says why; every action that declines updates or changes approvals or computer
        groups is then skipped.

    .PARAMETER UpdateServer
        The connected WSUS server (IUpdateServer).

    .EXAMPLE
        Get-WsusServerRole -UpdateServer $Connection.UpdateServer

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-wsusserverrole',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [System.Object]
    $UpdateServer
  )

  Write-Debug -Message:'[Get-WsusServerRole] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Configuration = $Null
  [System.String]$Private:Description = [System.String]::Empty
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Boolean]$Private:FromMicrosoftUpdate = $False
  [System.Boolean]$Private:IsReplica = $False
  [System.String]$Private:Tier = 'Unknown'
  [System.String]$Private:Upstream = [System.String]::Empty
  [System.String]$Private:Version = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Version = [System.String](Get-MaintenancePropertyValue -InputObject:$UpdateServer -Name:'Version' -Default:'')

  Try {
    $Configuration = $UpdateServer.GetConfiguration()
    $IsReplica = [System.Boolean]$Configuration.IsReplicaServer
    $FromMicrosoftUpdate = [System.Boolean]$Configuration.SyncFromMicrosoftUpdate

    If ($FromMicrosoftUpdate -eq $True) {
      $Upstream = $Script:Message['Get-WsusServerRole.MicrosoftUpdate']
    } Else {
      $Upstream = $Script:Message['Get-WsusServerRole.Upstream'] -f $Configuration.UpstreamWsusServerName, $Configuration.UpstreamWsusServerPortNumber, $(If ([System.Boolean]$Configuration.UpstreamWsusServerUseSsl -eq $True) { 'TLS' } Else { $Script:Message['Get-WsusServerRole.NoTls'] })
    }

    If ($IsReplica -eq $True) {
      $Tier = 'Replica'
    } ElseIf ($FromMicrosoftUpdate -eq $True) {
      $Tier = 'TopTier'
    } Else {
      $Tier = 'Autonomous'
    }

    $Description = $Script:Message[('Get-WsusServerRole.{0}' -f $Tier)]
  } Catch {
    $Tier = 'Unknown'
    $ErrorText = $PSItem.Exception.GetBaseException().Message
    $Description = $Script:Message['Get-WsusServerRole.Unknown'] -f $ErrorText
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Tier                    = [System.String]$Tier
    IsReplica               = [System.Boolean]$IsReplica
    SyncFromMicrosoftUpdate = [System.Boolean]$FromMicrosoftUpdate
    Upstream                = [System.String]$Upstream
    Version                 = [System.String]$Version
    Description             = [System.String]$Description
    Error                   = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Get-WsusServerRole] Exiting'
}
