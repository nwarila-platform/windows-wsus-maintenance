#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Resolve-MaintenanceOutputFolder.Fallback'    = "The {0} folder '{1}' cannot be used ({2}); the {0} is saved to the default folder '{3}' instead."
  'Resolve-MaintenanceOutputFolder.Refused'     = "the {0} folder '{1}': {2}"
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

        With -Protect, both folders are created protected and a folder that other principals can change
        is not used (Initialize-MaintenanceFolder); such a refusal of the configured folder is returned as
        Refused, which the run treats as a failed precondition after saving its failure report in the
        fallback. With -AllowPermissive such a folder is used and the notice is the warning about it.

    .PARAMETER AllowPermissive
        Use a folder that other principals can change, with a warning.

    .PARAMETER DefaultPath
        Built-in default folder.

    .PARAMETER Path
        Configured folder.

    .PARAMETER Protect
        Create the folders protected and refuse one that other principals can change.

    .PARAMETER Purpose
        What the folder holds, for the notice: report or summary.

    .EXAMPLE
        Resolve-MaintenanceOutputFolder -Path $Setting.ReportFolder -DefaultPath $Setting.DefaultReportFolder -Purpose 'report' -Protect

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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $AllowPermissive,

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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $Protect,

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
  [System.String]$Private:Refused = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Attempt = Initialize-MaintenanceFolder -AllowPermissive:$AllowPermissive -Path:$Path -Protect:$Protect

  If ([System.String]::IsNullOrEmpty($Attempt.Error) -eq $True) {
    $Ready = $Attempt.Path
    If ([System.String]::IsNullOrEmpty($Attempt.Warning) -eq $False) {
      $Notice = New-MaintenanceNotice -Message:$Attempt.Warning -Severity:'Warning'
    }
  } Else {
    If ($Attempt.Permissive -eq $True) {
      $Refused = $Script:Message['Resolve-MaintenanceOutputFolder.Refused'] -f $Purpose, $Attempt.Path, $Attempt.Error
    }

    $Fallback = Initialize-MaintenanceFolder -AllowPermissive:$AllowPermissive -Path:$DefaultPath -Protect:$Protect
    If (($Fallback.Path -ne $Attempt.Path) -and ([System.String]::IsNullOrEmpty($Fallback.Error) -eq $True)) {
      $Ready = $Fallback.Path
      $Notice = New-MaintenanceNotice -Message:($Script:Message['Resolve-MaintenanceOutputFolder.Fallback'] -f $Purpose, $Attempt.Path, $Attempt.Error, $Fallback.Path) -Severity:'Warning'
    } Else {
      $Notice = New-MaintenanceNotice -Message:($Script:Message['Resolve-MaintenanceOutputFolder.Unavailable'] -f $Purpose, $Attempt.Path, $Attempt.Error) -Severity:'Warning'
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path    = [System.String]$Ready
    Notice  = $Notice
    Refused = [System.String]$Refused
  }

  $Result
  Write-Debug -Message:'[Resolve-MaintenanceOutputFolder] Exiting'
}
