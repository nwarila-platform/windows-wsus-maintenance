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

        Every folder is created protected, and a folder that principals other than SYSTEM,
        Administrators and the run identity can change is not used (REQ-092). A refused log folder
        is a log that cannot be created; a refused report or summary folder falls back like any
        other unusable folder and is listed in Refused, which the caller turns into a failed
        precondition once the failure report can be saved in the fallback. With
        run.permissiveFolderOverride (PermissiveFolderOverride in the settings) such folders are
        used instead, each with a Warning notice.

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
  [System.Boolean]$Private:AllowPermissive = $False
  [PSCustomObject]$Private:Log = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Collections.Generic.List[System.String]]$Private:Refused = $Null
  [PSCustomObject]$Private:ReportFolder = $Null
  [PSCustomObject]$Private:SummaryFolder = $Null
  [PSCustomObject]$Private:Result = $Null

  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Refused = [System.Collections.Generic.List[System.String]]::new()
  $AllowPermissive = [System.Boolean](Get-MaintenancePropertyValue -InputObject:$Setting -Name:'PermissiveFolderOverride' -Default:$False)
  $Log = New-MaintenanceLog -AllowPermissive:$AllowPermissive -Folder:$Setting.LogFolder -Protect -RunId:$RunId -Verbosity:$Setting.LogVerbosity
  If ([System.String]::IsNullOrEmpty($Log.FolderWarning) -eq $False) {
    $Notices.Add((New-MaintenanceNotice -Message:$Log.FolderWarning -Severity:'Warning'))
  }

  $ReportFolder = Resolve-MaintenanceOutputFolder -AllowPermissive:$AllowPermissive -DefaultPath:$Setting.DefaultReportFolder -Path:$Setting.ReportFolder -Protect -Purpose:'report'
  $SummaryFolder = Resolve-MaintenanceOutputFolder -AllowPermissive:$AllowPermissive -DefaultPath:$Setting.DefaultSummaryFolder -Path:$Setting.SummaryFolder -Protect -Purpose:'summary'
  ForEach ($Choice In @($ReportFolder, $SummaryFolder)) {
    If ($Null -ne $Choice.Notice) {
      $Notices.Add($Choice.Notice)
    }

    If ([System.String]::IsNullOrEmpty($Choice.Refused) -eq $False) {
      $Refused.Add($Choice.Refused)
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
    Refused       = [System.String[]]$Refused.ToArray()
  }

  $Result
  Write-Debug -Message:'[Open-MaintenanceRunOutput] Exiting'
}
