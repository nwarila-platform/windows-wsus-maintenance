#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Resolve-MaintenanceOutputFolder.Fallback'    = "The {0} folder '{1}' cannot be used ({2}); the {0} is saved to the default folder '{3}' instead."
  'Resolve-MaintenanceOutputFolder.Unavailable' = "The {0} folder '{1}' cannot be used ({2}); no {0} file is saved for this run."
}

Function Resolve-MaintenanceOutputFolder {
  <#
    .SYNOPSIS
        Chooses the folder a report or summary is saved to.

    .DESCRIPTION
        Uses the configured folder when it can be written. Otherwise falls back to the built-in default
        folder and raises a Warning notice that names both folders and the reason; when the default
        cannot be written either, no file of that kind is saved and the Warning notice says so. The
        decision is made before the report is rendered, so the notice appears in the report itself.

    .PARAMETER DefaultPath
        Built-in default folder.

    .PARAMETER Path
        Configured folder.

    .PARAMETER Purpose
        What the folder holds, for the notice: report or summary.

    .EXAMPLE
        Resolve-MaintenanceOutputFolder -Path $Setting.ReportFolder -DefaultPath $Setting.DefaultReportFolder -Purpose 'report'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#resolve-maintenanceoutputfolder',
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
    $DefaultPath,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Path,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('report', 'summary')]
    [System.String]
    $Purpose
  )

  Write-Debug -Message:'[Resolve-MaintenanceOutputFolder] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Attempt = $Null
  [PSCustomObject]$Private:Fallback = $Null
  [PSCustomObject]$Private:Notice = $Null
  [System.String]$Private:Ready = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Attempt = Initialize-MaintenanceFolder -Path:$Path

  If ([System.String]::IsNullOrEmpty($Attempt.Error) -eq $True) {
    $Ready = $Attempt.Path
  } Else {
    $Fallback = Initialize-MaintenanceFolder -Path:$DefaultPath
    If (($Fallback.Path -ne $Attempt.Path) -and ([System.String]::IsNullOrEmpty($Fallback.Error) -eq $True)) {
      $Ready = $Fallback.Path
      $Notice = New-MaintenanceNotice -Message:($Script:Message['Resolve-MaintenanceOutputFolder.Fallback'] -f $Purpose, $Attempt.Path, $Attempt.Error, $Fallback.Path) -Severity:'Warning'
    } Else {
      $Notice = New-MaintenanceNotice -Message:($Script:Message['Resolve-MaintenanceOutputFolder.Unavailable'] -f $Purpose, $Attempt.Path, $Attempt.Error) -Severity:'Warning'
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path   = [System.String]$Ready
    Notice = $Notice
  }

  $Result
  Write-Debug -Message:'[Resolve-MaintenanceOutputFolder] Exiting'
}
