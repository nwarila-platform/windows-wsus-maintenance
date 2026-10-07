#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-SqlConnection {
  <#
    .SYNOPSIS
        Opens a connection to SQL Server.

    .DESCRIPTION
        A seam around System.Data.SqlClient.SqlConnection, which is part of the .NET Framework, so no
        external SQL utility is needed. The connection string carries the instance, the database,
        integrated authentication and the connection time-out. Throws when the connection cannot be
        opened, after releasing it.

    .PARAMETER ConnectionString
        SqlClient connection string.

    .EXAMPLE
        New-SqlConnection -ConnectionString 'Data Source=WSUS01;Initial Catalog=SUSDB;Integrated Security=SSPI;Connect Timeout=30'

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-sqlconnection',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $ConnectionString
  )

  Write-Debug -Message:'[New-SqlConnection] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Connection = $Null
  [System.Object]$Private:Result = $Null

  $Connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
  Try {
    $Connection.Open()
  } Catch {
    $Connection.Dispose()
    Throw
  }

  [System.Object]$Result = $Connection

  $Result
  Write-Debug -Message:'[New-SqlConnection] Exiting'
}
