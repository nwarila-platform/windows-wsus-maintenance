#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Publish-MaintenanceRunOutput.Completed'  = 'Run {0} completed with status {1} (exit code {2}) in {3} s. Report: {4}.'
  'Publish-MaintenanceRunOutput.Finished'   = 'Run finished with status {0} (exit code {1}) in {2} s. Report: {3}. Summary: {4}.'
  'Publish-MaintenanceRunOutput.Notice'     = 'Notice ({0}): {1}'
  'Publish-MaintenanceRunOutput.NotSaved'   = 'not saved'
  'Publish-MaintenanceRunOutput.StageError' = 'Run {0}: stage {1} failed: {2}'
  'Publish-MaintenanceRunOutput.Stopped'    = 'Run {0} stopped at {1} with exit code {2}: {3} {4} Report: {5}.'
}

Function Publish-MaintenanceRunOutput {
  <#
    .SYNOPSIS
        Writes the report, summary, closing log entries and events of a run.

    .DESCRIPTION
        Builds the report model once and from it saves the text and HTML reports and the JSON
        summary, so the three agree. It then logs every notice (Error as error, High and Warning as
        warning, Information as information), writes a stage-error event for each stage that failed
        and, last, the completion event for the run status or, for a run that stopped on a
        precondition, the precondition-failure or invalid-configuration event, and logs the outcome
        with the paths of the files written. Failures to write a file are logged and never stop the
        run. Called for every run that has opened its output, including one that stops early.

    .PARAMETER Discovery
        Discovered facts for the report header (New-MaintenanceReport), or null.

    .PARAMETER ExitCode
        Exit code of the run.

    .PARAMETER Failure
        Kind, Point, Message and Guidance of a run that stopped early (a failed precondition, an
        invalid configuration or an unexpected error), or null.

    .PARAMETER Notice
        Every notice of the run.

    .PARAMETER Output
        The run output from Open-MaintenanceRunOutput.

    .PARAMETER Run
        The run record (New-MaintenanceRunRecord).

    .PARAMETER Stage
        Stage outcomes in catalogue order.

    .PARAMETER Status
        Run status.

    .PARAMETER Validation
        The validation summary.

    .EXAMPLE
        Publish-MaintenanceRunOutput -Output $Output -Run $Record -Stage $Outcomes -Notice $Notices -Status 'Success' -ExitCode 0 -Validation $Summary

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#publish-maintenancerunoutput',
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
    [AllowNull()]
    [PSCustomObject]
    $Discovery = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 255)]
    [System.Int32]
    $ExitCode,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Failure = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Notice = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Output,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Run,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Stage = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Success', 'Warning', 'Error')]
    [System.String]
    $Status,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Validation
  )

  Write-Debug -Message:'[Publish-MaintenanceRunOutput] Entering'

  # Initialize Variable(s)
  [System.Collections.Hashtable]$Private:CompletionKinds = @{ Success = 'runSucceeded'; Warning = 'runWarning'; Error = 'runFailed' }
  [System.String]$Private:Kind = [System.String]::Empty
  [System.Collections.Hashtable]$Private:NoticeLevels = @{ Error = 'Error'; High = 'Warning'; Warning = 'Warning'; Information = 'Information' }
  [PSCustomObject]$Private:Report = $Null
  [System.String]$Private:ReportList = [System.String]::Empty
  [PSCustomObject]$Private:Saved = $Null
  [PSCustomObject]$Private:Summary = $Null
  [PSCustomObject]$Private:Result = $Null

  $Report = New-MaintenanceReport `
    -Discovery:$Discovery `
    -ExitCode:$ExitCode `
    -Failure:$Failure `
    -LogPath:$Output.Log.Path `
    -MaxItems:$Output.Setting.MaxItems `
    -Notice:$Notice `
    -Run:$Run `
    -Stage:$Stage `
    -Status:$Status `
    -Validation:$Validation

  $Saved = Save-MaintenanceReport `
    -Folder:$Output.ReportFolder `
    -Format:$Output.Setting.ReportFormats `
    -Html:(ConvertTo-MaintenanceReportHtml -Report:$Report) `
    -RunId:$Run.RunId `
    -Text:(ConvertTo-MaintenanceReportText -Report:$Report)
  ForEach ($SaveError In $Saved.Errors) {
    Write-MaintenanceLog -Level:'Error' -Log:$Output.Log -Message:$SaveError
  }

  ForEach ($Item In @($Report.Notices)) {
    Write-MaintenanceLog -Level:$NoticeLevels[$Item.Severity] -Log:$Output.Log -Message:($Script:Message['Publish-MaintenanceRunOutput.Notice'] -f $Item.Severity, $Item.Message) -Stage:$Item.Stage
  }

  $Summary = Write-MaintenanceSummary -Folder:$Output.SummaryFolder -LogPath:$Output.Log.Path -Report:$Report -ReportPath:$Saved.Paths
  If ([System.String]::IsNullOrEmpty($Summary.Error) -eq $False) {
    Write-MaintenanceLog -Level:'Warning' -Log:$Output.Log -Message:$Summary.Error
  }

  ForEach ($Section In @($Report.Stages)) {
    If ($Section.Status -eq 'Error') {
      Write-MaintenanceEvent -Channel:$Output.Events -Kind:'stageError' -Message:($Script:Message['Publish-MaintenanceRunOutput.StageError'] -f $Run.RunId, $Section.Name, $Section.ErrorMessage)
    }
  }

  $ReportList = $Script:Message['Publish-MaintenanceRunOutput.NotSaved']
  If (@($Saved.Paths).Count -gt 0) {
    $ReportList = @($Saved.Paths) -join ', '
  }

  If ($Null -ne $Failure) {
    # An unexpected error that stopped the run is a failed run, not a failed precondition.
    Switch ($Failure.Kind) {
      'ConfigurationInvalid' {
        $Kind = 'configurationInvalid'
      }
      'StageError' {
        $Kind = 'runFailed'
      }
      Default {
        $Kind = 'preconditionFailure'
      }
    }

    Write-MaintenanceEvent -Channel:$Output.Events -Kind:$Kind -Message:($Script:Message['Publish-MaintenanceRunOutput.Stopped'] -f $Run.RunId, $Failure.Point, $ExitCode, $Failure.Message, $Failure.Guidance, $ReportList)
  } Else {
    Write-MaintenanceEvent -Channel:$Output.Events -Kind:$CompletionKinds[$Status] -Message:($Script:Message['Publish-MaintenanceRunOutput.Completed'] -f $Run.RunId, $Status, $ExitCode, $Run.DurationSeconds.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $ReportList)
  }

  Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Publish-MaintenanceRunOutput.Finished'] -f $Status, $ExitCode, $Run.DurationSeconds.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $ReportList, $(If ([System.String]::IsNullOrEmpty($Summary.Path) -eq $True) { $Script:Message['Publish-MaintenanceRunOutput.NotSaved'] } Else { $Summary.Path }))

  [PSCustomObject]$Result = [PSCustomObject]@{
    Report      = $Report
    ReportPaths = [System.String[]]$Saved.Paths
    SummaryPath = [System.String]$Summary.Path
  }

  $Result
  Write-Debug -Message:'[Publish-MaintenanceRunOutput] Exiting'
}
