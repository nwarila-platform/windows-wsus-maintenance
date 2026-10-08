#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Write-MaintenanceSummary.Failed' = "The summary file '{0}' could not be written: {1}"
}

Function Write-MaintenanceSummary {
  <#
    .SYNOPSIS
        Writes the machine-readable JSON summary of one run.

    .DESCRIPTION
        Writes WsusMaintenance-<run identifier>.json into the summary folder. It holds the run
        identifier, server, status, exit code, timings (local time with offset), the stages listed
        with -Stage, any failure, the stage and notice totals, each stage's status, reason, timing,
        counts, message, item count, listed items and error, every notice, and the paths of the
        log and report files. It is made from the same report model as the text and HTML reports,
        so its counts match theirs, and it validates against docs/reference/summary.schema.json.
        Every text in the model has already passed through Protect-MaintenanceText, so the JSON is
        written as serialized. A folder that is not usable arrives empty and nothing is written; a
        write failure is returned in Error and never stops the run.

    .PARAMETER Folder
        Ready summary folder, or empty when none is usable.

    .PARAMETER LogPath
        Path of the run log, if one was written.

    .PARAMETER Report
        The report from New-MaintenanceReport.

    .PARAMETER ReportPath
        Paths of the saved report files.

    .EXAMPLE
        Write-MaintenanceSummary -Folder $Output.SummaryFolder -Report $Report -LogPath $Log.Path -ReportPath $Saved.Paths

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#write-maintenancesummary',
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
    [AllowEmptyString()]
    [System.String]
    $Folder,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $LogPath = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Report,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $ReportPath = @()
  )

  Write-Debug -Message:'[Write-MaintenanceSummary] Entering'

  # Initialize Variable(s)
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Globalization.CultureInfo]$Private:Culture = [System.Globalization.CultureInfo]::InvariantCulture
  [System.Collections.Specialized.OrderedDictionary]$Private:Document = $Null
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Object]$Private:Failure = $Null
  [System.Collections.Generic.List[System.Object]]$Private:Notices = $Null
  [System.String]$Private:Path = [System.String]::Empty
  [System.Collections.Generic.List[System.Object]]$Private:Stages = $Null
  [System.String]$Private:TimeFormat = 'yyyy-MM-ddTHH:mm:ss.fffzzz'
  [PSCustomObject]$Private:Result = $Null

  $Stages = [System.Collections.Generic.List[System.Object]]::new()
  ForEach ($Section In @($Report.Stages)) {
    $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
    ForEach ($Count In @($Section.Counts)) {
      $Counts[$Count.Name] = $Count.Value
    }

    $Stages.Add(
      [ordered]@{
        name            = $Section.Name
        order           = $Section.Order
        status          = $Section.Status
        reason          = $Section.Reason
        startedAt       = $(If ($Section.StartedAt -is [System.DateTime]) { $Section.StartedAt.ToString($TimeFormat, $Culture) } Else { $Null })
        durationSeconds = [System.Math]::Round($Section.DurationSeconds, 3)
        counts          = $Counts
        message         = $Section.Message
        itemCount       = $Section.ItemCount
        items           = [System.String[]]@($Section.Items)
        errorMessage    = $Section.ErrorMessage
        errorTime       = $(If ($Section.ErrorTime -is [System.DateTime]) { $Section.ErrorTime.ToString($TimeFormat, $Culture) } Else { $Null })
      }
    )
  }

  $Notices = [System.Collections.Generic.List[System.Object]]::new()
  ForEach ($Item In @($Report.Notices)) {
    $Notices.Add(
      [ordered]@{
        severity = $Item.Severity
        stage    = $Item.Stage
        message  = $Item.Message
        link     = $Item.Link
        command  = $Item.Command
        raisedAt = $(If ($Item.RaisedAt -is [System.DateTime]) { $Item.RaisedAt.ToString($TimeFormat, $Culture) } Else { $Null })
      }
    )
  }

  $Failure = $Null
  If ($Null -ne $Report.Failure) {
    $Failure = [ordered]@{
      kind     = $Report.Failure.Kind
      point    = $Report.Failure.Point
      message  = $Report.Failure.Message
      guidance = $Report.Failure.Guidance
    }
  }

  $Document = [ordered]@{
    schemaVersion   = 1
    runId           = $Report.RunId
    server          = $Report.Server
    status          = $Report.Status
    exitCode        = $Report.ExitCode
    dryRun          = $Report.DryRun
    startedAt       = $Report.StartedAt.ToString($TimeFormat, $Culture)
    completedAt     = $Report.CompletedAt.ToString($TimeFormat, $Culture)
    durationSeconds = [System.Math]::Round($Report.DurationSeconds, 3)
    stagesRequested = [System.String[]]@($Report.StagesRequested)
    failure         = $Failure
    totals          = [ordered]@{
      stages  = [ordered]@{
        success = $Report.Totals.Stages.Success
        warning = $Report.Totals.Stages.Warning
        error   = $Report.Totals.Stages.Error
        skipped = $Report.Totals.Stages.Skipped
        notRun  = $Report.Totals.Stages.NotRun
      }
      notices = [ordered]@{
        error       = $Report.Totals.Notices.Error
        high        = $Report.Totals.Notices.High
        warning     = $Report.Totals.Notices.Warning
        information = $Report.Totals.Notices.Information
      }
    }
    stages          = $Stages.ToArray()
    notices         = $Notices.ToArray()
    artifacts       = [ordered]@{
      log     = $LogPath
      reports = [System.String[]]@($ReportPath)
    }
  }

  If ([System.String]::IsNullOrEmpty($Folder) -eq $False) {
    $Path = [System.IO.Path]::Combine($Folder, ('WsusMaintenance-{0}.json' -f $Report.RunId))
    Try {
      [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject:$Document -Depth:10), [System.Text.UTF8Encoding]::new($False))
    } Catch {
      $ErrorText = $Script:Message['Write-MaintenanceSummary.Failed'] -f $Path, $PSItem.Exception.GetBaseException().Message
      $Path = [System.String]::Empty
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path  = [System.String]$Path
    Error = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Write-MaintenanceSummary] Exiting'
}
