#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Write-MaintenanceEventEntry {
  <#
    .SYNOPSIS
        Writes one entry to the Windows Event Log.

    .DESCRIPTION
        A seam around System.Diagnostics.EventLog.WriteEntry, so that tests can replace it. The source
        must already be registered (Test-MaintenanceEventSource); this function never registers one.

    .PARAMETER EntryType
        Entry type.

    .PARAMETER EventId
        Event identifier.

    .PARAMETER Message
        Entry text.

    .PARAMETER Source
        Registered event source.

    .EXAMPLE
        Write-MaintenanceEventEntry -Source 'Invoke-WsusMaintenance' -EventId 1000 -EntryType 'Information' -Message 'Run started.'

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#write-maintenanceevententry',
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
    [ValidateSet('Information', 'Warning', 'Error')]
    [System.String]
    $EntryType,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(1, 65535)]
    [System.Int32]
    $EventId,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Message,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Source
  )

  Write-Debug -Message:'[Write-MaintenanceEventEntry] Entering'

  [System.Diagnostics.EventLog]::WriteEntry($Source, $Message, [System.Diagnostics.EventLogEntryType]$EntryType, $EventId)

  Write-Debug -Message:'[Write-MaintenanceEventEntry] Exiting'
}
