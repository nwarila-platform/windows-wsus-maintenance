#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceEventChannel {
  <#
    .SYNOPSIS
        Prepares the Windows Event Log channel for one run.

    .DESCRIPTION
        Holds the event-log settings for the run together with what the run has learned about them:
        whether the event source can be used (unknown until the first event) and how many events were
        written. Write-MaintenanceEvent checks the source once, so an unregistered source produces a
        single warning in the run log.

    .PARAMETER Log
        The run log, for the unavailable-source warning.

    .PARAMETER Setting
        The EventLog part of Get-MaintenanceOutputSetting.

    .EXAMPLE
        New-MaintenanceEventChannel -Setting $Setting.EventLog -Log $Log

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenanceeventchannel',
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
    [AllowNull()]
    [PSCustomObject]
    $Log,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Setting
  )

  Write-Debug -Message:'[New-MaintenanceEventChannel] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = [PSCustomObject]@{
    Enabled   = [System.Boolean]$Setting.Enabled
    LogName   = [System.String]$Setting.LogName
    Source    = [System.String]$Setting.Source
    EventIds  = $Setting.EventIds
    Log       = $Log
    Available = $Null
    Written   = [System.Int32]0
  }

  $Result
  Write-Debug -Message:'[New-MaintenanceEventChannel] Exiting'
}
