#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceEventSource {
  <#
    .SYNOPSIS
        Tells whether an event source is registered in a given event log.

    .DESCRIPTION
        A seam around System.Diagnostics.EventLog, so that tests can replace it. The source must exist
        and belong to the named log; deployment registers it. Throws where the event log is not
        available, for example on another platform, or when the run identity cannot read the event
        log registrations.

    .PARAMETER LogName
        Event log the source must belong to.

    .PARAMETER Source
        Event source name.

    .EXAMPLE
        Test-MaintenanceEventSource -LogName 'Application' -Source 'Invoke-WsusMaintenance'

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceeventsource',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
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
    $LogName,

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

  Write-Debug -Message:'[Test-MaintenanceEventSource] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Result = $False

  If ([System.Diagnostics.EventLog]::SourceExists($Source) -eq $True) {
    [System.Boolean]$Result = [System.Diagnostics.EventLog]::LogNameFromSourceName($Source, '.') -eq $LogName
  }

  $Result
  Write-Debug -Message:'[Test-MaintenanceEventSource] Exiting'
}
