#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Connect-MaintenanceServer.ApiFailed'      = 'The WSUS administration interface could not be reached: {0}'
  'Connect-MaintenanceServer.DatabaseFailed' = "SUSDB could not be opened on '{0}' (database {1}): {2}"
  'Connect-MaintenanceServer.Endpoint'       = '{0}, port {1}, {2}'
  'Connect-MaintenanceServer.NoTls'          = 'no TLS'
}

Function Connect-MaintenanceServer {
  <#
    .SYNOPSIS
        Connects to the WSUS administration interface and to SUSDB.

    .DESCRIPTION
        Connects to the local WSUS server through its administration interface, or, when any of
        discovery.wsusHostName, discovery.wsusPort or discovery.wsusUseTls is set, to that host (default:
        this computer), port (default: 8531 with TLS, 8530 without) and TLS setting. The returned strings
        are requested in declines.evaluationLanguage. It then opens SUSDB with integrated authentication
        and the run.connectionTimeoutSeconds connection time-out. The time each connection was
        established is recorded. A failure is returned in Error, with Point naming the connection that
        failed (Api or Database); the caller stops the run with the precondition-failure code.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER Environment
        Result of Get-WsusEnvironment, without problems.

    .EXAMPLE
        Connect-MaintenanceServer -Configuration $Effective -Environment $Environment

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#connect-maintenanceserver',
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
    [PSCustomObject]
    $Configuration,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Environment
  )

  Write-Debug -Message:'[Connect-MaintenanceServer] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:ApiConnectedAt = $Null
  [System.Object]$Private:Database = $Null
  [System.Object]$Private:DatabaseConnectedAt = $Null
  [System.String]$Private:Endpoint = [System.String]::Empty
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.String]$Private:HostName = [System.String]::Empty
  [System.String]$Private:Point = [System.String]::Empty
  [System.Int32]$Private:Port = 0
  [System.Object]$Private:UpdateServer = $Null
  [System.Boolean]$Private:UseTls = $False
  [PSCustomObject]$Private:Result = $Null

  If (($Null -ne $Configuration.discovery.wsusHostName) -or ($Null -ne $Configuration.discovery.wsusPort) -or ($Null -ne $Configuration.discovery.wsusUseTls)) {
    $HostName = [System.Environment]::MachineName
    If ($Null -ne $Configuration.discovery.wsusHostName) {
      $HostName = [System.String]$Configuration.discovery.wsusHostName
    }

    If ($Null -ne $Configuration.discovery.wsusUseTls) {
      $UseTls = [System.Boolean]$Configuration.discovery.wsusUseTls
    }

    If ($Null -ne $Configuration.discovery.wsusPort) {
      $Port = [System.Int32]$Configuration.discovery.wsusPort
    } ElseIf ($UseTls -eq $True) {
      $Port = 8531
    } Else {
      $Port = 8530
    }
  }

  Try {
    $UpdateServer = Get-WsusUpdateServer -HostName:$HostName -Port:$Port -UseTls:$UseTls
    $UpdateServer.PreferredCulture = [System.String]$Configuration.declines.evaluationLanguage
    $ApiConnectedAt = Get-MaintenanceTime
    $Endpoint = $Script:Message['Connect-MaintenanceServer.Endpoint'] -f (Get-MaintenancePropertyValue -InputObject:$UpdateServer -Name:'Name' -Default:$HostName), (Get-MaintenancePropertyValue -InputObject:$UpdateServer -Name:'PortNumber' -Default:$Port), $(If ((Get-MaintenancePropertyValue -InputObject:$UpdateServer -Name:'IsConnectionSecureForApiRemoting' -Default:$UseTls) -eq $True) { 'TLS' } Else { $Script:Message['Connect-MaintenanceServer.NoTls'] })
  } Catch {
    $ErrorText = $Script:Message['Connect-MaintenanceServer.ApiFailed'] -f $PSItem.Exception.GetBaseException().Message
    $Point = 'Api'
  }

  If ([System.String]::IsNullOrEmpty($ErrorText) -eq $True) {
    Try {
      $Database = New-SqlConnection -ConnectionString:('Data Source={0};Initial Catalog={1};Integrated Security=SSPI;Connect Timeout={2};Application Name=Invoke-WsusMaintenance' -f $Environment.SqlServerName, $Environment.DatabaseName, $Configuration.run.connectionTimeoutSeconds)
      $DatabaseConnectedAt = Get-MaintenanceTime
    } Catch {
      $ErrorText = $Script:Message['Connect-MaintenanceServer.DatabaseFailed'] -f $Environment.SqlServerName, $Environment.DatabaseName, $PSItem.Exception.GetBaseException().Message
      $Point = 'Database'
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    UpdateServer        = $UpdateServer
    Endpoint            = [System.String]$Endpoint
    ApiConnectedAt      = $ApiConnectedAt
    Database            = $Database
    DatabaseConnectedAt = $DatabaseConnectedAt
    Error               = [System.String]$ErrorText
    Point               = [System.String]$Point
  }

  $Result
  Write-Debug -Message:'[Connect-MaintenanceServer] Exiting'
}
