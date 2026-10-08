#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-WsusConnection.Missing' = 'No WSUS connection is open; the stage needs the discovery steps to have run.'
}

Function Get-WsusConnection {
  <#
    .SYNOPSIS
        Returns the WSUS administration connection a stage works with.

    .DESCRIPTION
        Stages that work through the WSUS administration API take the update server that discovery
        connected from their context. A stage started without one (for example when discovery did not
        run) fails with a clear error instead of a null reference.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Get-WsusConnection -Context $Context

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-wsusconnection',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Object])]
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
    $Context
  )

  Write-Debug -Message:'[Get-WsusConnection] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Result = $Null

  [System.Object]$Result = Get-MaintenancePropertyValue -InputObject:(Get-MaintenancePropertyValue -InputObject:$Context -Name:'Server' -Default:$Null) -Name:'UpdateServer' -Default:$Null
  If ($Null -eq $Result) {
    Throw $Script:Message['Get-WsusConnection.Missing']
  }

  $Result
  Write-Debug -Message:'[Get-WsusConnection] Exiting'
}
