#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-WsusSetupValue {
  <#
    .SYNOPSIS
        Reads the values WSUS setup records in the registry.

    .DESCRIPTION
        A seam around HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup, so that tests can
        replace it. WSUS setup records there, among other values, the SQL Server instance (SqlServerName)
        and the database name (SqlDatabaseName) that the server uses. Returns null when the key does not
        exist, which means WSUS is not installed on this server.

    .EXAMPLE
        Get-WsusSetupValue

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-wsussetupvalue',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param ()

  Write-Debug -Message:'[Get-WsusSetupValue] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = Get-ItemProperty -LiteralPath:'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup' -ErrorAction:'SilentlyContinue'

  $Result
  Write-Debug -Message:'[Get-WsusSetupValue] Exiting'
}
