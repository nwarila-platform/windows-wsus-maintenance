#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Disconnect-MaintenanceServer {
  <#
    .SYNOPSIS
        Closes the SUSDB connection of a run.

    .DESCRIPTION
        Releases the database connection that Connect-MaintenanceServer opened. The WSUS administration
        interface holds no connection to close. Never throws: a failure to close is only written to the
        debug stream.

    .PARAMETER Connection
        The result of Connect-MaintenanceServer, or null.

    .EXAMPLE
        Disconnect-MaintenanceServer -Connection $Connection

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#disconnect-maintenanceserver',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Connection
  )

  Write-Debug -Message:'[Disconnect-MaintenanceServer] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Database = $Null

  $Database = Get-MaintenancePropertyValue -InputObject:$Connection -Name:'Database' -Default:$Null
  If ($Null -ne $Database) {
    Try {
      $Database.Dispose()
    } Catch {
      Write-Debug -Message:('[Disconnect-MaintenanceServer] Close failed: {0}' -f $PSItem.Exception.Message)
    }
  }

  Write-Debug -Message:'[Disconnect-MaintenanceServer] Exiting'
}
