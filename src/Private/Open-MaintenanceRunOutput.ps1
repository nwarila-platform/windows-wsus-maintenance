#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Open-MaintenanceRunOutput {
  <#
    .SYNOPSIS
        Opens the run log and prepares the event channel and the report and summary folders.

    .DESCRIPTION
        Creates the run log (New-MaintenanceLog), the event channel (New-MaintenanceEventChannel) and
        chooses the report and summary folders (Resolve-MaintenanceOutputFolder). A folder that falls
        back to its default, or cannot be used at all, yields a Warning notice in Notices, which the
        caller adds to the run's notices before the report is rendered. A log that cannot be created
        is returned with its Error set; the caller must then stop the run with the
        precondition-failure code.

    .PARAMETER RunId
        Run identifier.

    .PARAMETER Setting
        Output settings from Get-MaintenanceOutputSetting.

    .EXAMPLE
        Open-MaintenanceRunOutput -RunId $RunId -Setting $Setting

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#open-maintenancerunoutput',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $RunId,

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

  Write-Debug -Message:'[Open-MaintenanceRunOutput] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Log = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:ReportFolder = $Null
  [PSCustomObject]$Private:SummaryFolder = $Null
  [PSCustomObject]$Private:Result = $Null

  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Log = New-MaintenanceLog -Folder:$Setting.LogFolder -RunId:$RunId -Verbosity:$Setting.LogVerbosity
  $ReportFolder = Resolve-MaintenanceOutputFolder -DefaultPath:$Setting.DefaultReportFolder -Path:$Setting.ReportFolder -Purpose:'report'
  $SummaryFolder = Resolve-MaintenanceOutputFolder -DefaultPath:$Setting.DefaultSummaryFolder -Path:$Setting.SummaryFolder -Purpose:'summary'
  ForEach ($Choice In @($ReportFolder, $SummaryFolder)) {
    If ($Null -ne $Choice.Notice) {
      $Notices.Add($Choice.Notice)
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    RunId         = [System.String]$RunId
    Setting       = $Setting
    Log           = $Log
    Events        = New-MaintenanceEventChannel -Log:$Log -Setting:$Setting.EventLog
    ReportFolder  = [System.String]$ReportFolder.Path
    SummaryFolder = [System.String]$SummaryFolder.Path
    Notices       = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Open-MaintenanceRunOutput] Exiting'
}
