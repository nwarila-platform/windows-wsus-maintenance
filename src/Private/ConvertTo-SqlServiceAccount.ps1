#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-SqlServiceAccount {
  <#
    .SYNOPSIS
        Names the per-service account of the SQL Server instance that holds SUSDB.

    .DESCRIPTION
        Returns NT SERVICE\MSSQLSERVER for a default instance and NT SERVICE\MSSQL$<instance> for a
        named one, from the SQL Server name WSUS records (host, host\instance, optionally with a port
        after a comma). A backup folder the run creates grants this account full control, because the
        SQL Server service, not the run identity, writes the backup file:
        https://learn.microsoft.com/sql/database-engine/configure-windows/configure-windows-service-accounts-and-permissions

    .PARAMETER SqlServerName
        The SQL Server name, as WSUS setup records it.

    .EXAMPLE
        ConvertTo-SqlServiceAccount -SqlServerName 'WSUS01\SQLEXPRESS'

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-sqlserviceaccount',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
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
    $SqlServerName = ''
  )

  Write-Debug -Message:'[ConvertTo-SqlServiceAccount] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Instance = [System.String]::Empty
  [System.String[]]$Private:Parts = @()
  [System.String]$Private:Result = [System.String]::Empty

  $Parts = [System.String[]]@(($SqlServerName -split ',', 2)[0] -split '\\', 2)
  If ($Parts.Count -gt 1) {
    $Instance = $Parts[1]
  }

  If (([System.String]::IsNullOrEmpty($Instance) -eq $True) -or ($Instance -eq 'MSSQLSERVER')) {
    [System.String]$Result = 'NT SERVICE\MSSQLSERVER'
  } Else {
    [System.String]$Result = 'NT SERVICE\MSSQL${0}' -f $Instance.ToUpperInvariant()
  }

  $Result
  Write-Debug -Message:'[ConvertTo-SqlServiceAccount] Exiting'
}
