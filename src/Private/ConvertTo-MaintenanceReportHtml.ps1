#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'ConvertTo-MaintenanceReportHtml.Columns' = '#|Stage|Status|Duration|Details'
}

Function ConvertTo-MaintenanceReportHtml {
  <#
    .SYNOPSIS
        Renders a run report as a self-contained HTML page.

    .DESCRIPTION
        Lays the report out in report order. Every text is HTML-encoded. Notices are coloured by
        severity, and those of the highest severity present are also set in bold. A link is rendered
        as a hyperlink when it is an http or https address and as plain text otherwise, and a
        suggested command as preformatted text. Each stage takes one table row with its order, name,
        status, duration and details. The page has no external resources and no branding.

    .PARAMETER Report
        The report from New-MaintenanceReport.

    .EXAMPLE
        ConvertTo-MaintenanceReportHtml -Report $Report

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenancereporthtml',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Report
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceReportHtml] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Body = [System.String]::Empty
  [System.String]$Private:Class = [System.String]::Empty
  [System.Globalization.CultureInfo]$Private:Culture = [System.Globalization.CultureInfo]::InvariantCulture
  [System.Collections.Generic.List[System.String]]$Private:Details = $Null
  [System.String]$Private:Heading = [System.String]::Empty
  [System.String[]]$Private:ItemList = @()
  [System.Collections.Generic.List[System.String]]$Private:Lines = $Null
  [System.String[]]$Private:Pairs = @()
  [System.String]$Private:Style = 'body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1b1b1b}h1{font-size:1.5em}h2{font-size:1.2em;margin-top:24px}table{border-collapse:collapse;margin:8px 0}th,td{border:1px solid #c8c6c4;padding:4px 8px;text-align:left;vertical-align:top}ul.notices{list-style:none;padding:0}.notice{margin:4px 0;padding:6px 10px;border-left:6px solid #8a8886}.sev-error{border-color:#a4262c;background:#fde7e9}.sev-high{border-color:#ca5010;background:#fff4ce}.sev-warning{border-color:#c19c00;background:#fffbe6}.sev-information{border-color:#0078d4;background:#eff6fc}.highest{font-weight:bold}.severity{font-weight:bold;margin-right:6px}.failure{border:2px solid #a4262c;padding:8px 12px}.status-success{color:#107c10}.status-warning{color:#8a6d00}.status-error{color:#a4262c}.status-skipped,.status-notrun{color:#605e5c}pre{background:#f3f2f1;padding:6px;white-space:pre-wrap;margin:4px 0}'
  [System.String]$Private:Result = [System.String]::Empty

  $Lines = [System.Collections.Generic.List[System.String]]::new()
  $Lines.Add('<!DOCTYPE html>')
  $Lines.Add('<html lang="en">')
  $Lines.Add('<head>')
  $Lines.Add('<meta charset="utf-8">')
  $Lines.Add(('<title>{0}</title>' -f [System.Net.WebUtility]::HtmlEncode(('{0} - {1} - {2}' -f $Report.Title, $Report.Server, $Report.RunId))))
  $Lines.Add(('<style>{0}</style>' -f $Style))
  $Lines.Add('</head>')
  $Lines.Add('<body>')
  $Lines.Add(('<h1>{0}</h1>' -f [System.Net.WebUtility]::HtmlEncode($Report.Title)))
  $Lines.Add('<table class="header">')
  ForEach ($Pair In @($Report.Header)) {
    $Lines.Add(('<tr><th>{0}</th><td>{1}</td></tr>' -f [System.Net.WebUtility]::HtmlEncode($Pair.Label), [System.Net.WebUtility]::HtmlEncode($Pair.Value)))
  }

  $Lines.Add('</table>')

  If ($Null -ne $Report.Failure) {
    $Lines.Add('<section class="failure">')
    $Lines.Add(('<h2>{0}</h2>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.FailureHeading'])))
    $Lines.Add('<table>')
    $Lines.Add(('<tr><th>{0}</th><td>{1}</td></tr>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.WhatHappened']), [System.Net.WebUtility]::HtmlEncode($Report.Failure.Message)))
    $Lines.Add(('<tr><th>{0}</th><td>{1}</td></tr>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.PointReached']), [System.Net.WebUtility]::HtmlEncode($Report.Failure.Point)))
    $Lines.Add(('<tr><th>{0}</th><td>{1}</td></tr>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.WhatToDo']), [System.Net.WebUtility]::HtmlEncode($Report.Failure.Guidance)))
    $Lines.Add('</table>')
    $Lines.Add('</section>')
  }

  If ([System.String]::IsNullOrEmpty($Report.HighestSeverity) -eq $True) {
    $Heading = $Script:Message['New-MaintenanceReport.NoticesHeading'] -f @($Report.Notices).Count
  } Else {
    $Heading = $Script:Message['New-MaintenanceReport.NoticesHighest'] -f @($Report.Notices).Count, $Report.HighestSeverity
  }

  $Lines.Add(('<h2>{0}</h2>' -f [System.Net.WebUtility]::HtmlEncode($Heading)))
  If (@($Report.Notices).Count -eq 0) {
    $Lines.Add(('<p>{0}</p>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.NoNotices'])))
  } Else {
    $Lines.Add('<ul class="notices">')
    ForEach ($Item In @($Report.Notices)) {
      $Class = 'notice sev-{0}' -f $Item.Severity.ToLowerInvariant()
      If ($Item.IsHighest -eq $True) {
        $Class = '{0} highest' -f $Class
      }

      $Body = '<span class="severity">{0}</span>{1}' -f [System.Net.WebUtility]::HtmlEncode($Item.Severity), [System.Net.WebUtility]::HtmlEncode($Item.Message)
      If ([System.String]::IsNullOrEmpty($Item.Stage) -eq $False) {
        $Body = '{0} <span class="stage">({1})</span>' -f $Body, [System.Net.WebUtility]::HtmlEncode($Item.Stage)
      }

      If ($Item.Link -match '^https?://') {
        $Body = '{0}<br><a href="{1}">{1}</a>' -f $Body, [System.Net.WebUtility]::HtmlEncode($Item.Link)
      } ElseIf ([System.String]::IsNullOrEmpty($Item.Link) -eq $False) {
        $Body = '{0}<br>{1}' -f $Body, [System.Net.WebUtility]::HtmlEncode($Item.Link)
      }

      If ([System.String]::IsNullOrEmpty($Item.Command) -eq $False) {
        $Body = '{0}<pre>{1}</pre>' -f $Body, [System.Net.WebUtility]::HtmlEncode($Item.Command)
      }

      $Lines.Add(('<li class="{0}">{1}</li>' -f $Class, $Body))
    }

    $Lines.Add('</ul>')
  }

  $Lines.Add(('<p class="connection">{0}</p>' -f [System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.Connection'] -f $Report.Connection))))
  $Lines.Add(('<h2>{0}</h2>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.StagesHeading'])))
  If (@($Report.Stages).Count -eq 0) {
    $Lines.Add(('<p>{0}</p>' -f [System.Net.WebUtility]::HtmlEncode($Script:Message['New-MaintenanceReport.NoStage'])))
  } Else {
    $Lines.Add('<table class="stages">')
    $Lines.Add(('<thead><tr><th>{0}</th></tr></thead>' -f (@($Script:Message['ConvertTo-MaintenanceReportHtml.Columns'] -split '\|' | ForEach-Object -Process:({ [System.Net.WebUtility]::HtmlEncode($PSItem) })) -join '</th><th>')))
    $Lines.Add('<tbody>')
    ForEach ($Section In @($Report.Stages)) {
      $Details = [System.Collections.Generic.List[System.String]]::new()
      If ([System.String]::IsNullOrEmpty($Section.Reason) -eq $False) {
        $Details.Add([System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.Reason'] -f $Section.Reason)))
      }

      If (@($Section.Counts).Count -gt 0) {
        $Pairs = [System.String[]]@(@($Section.Counts) | ForEach-Object -Process:({ '{0}={1}' -f $PSItem.Name, [System.Convert]::ToString($PSItem.Value, [System.Globalization.CultureInfo]::InvariantCulture) }))
        $Details.Add([System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.Counts'] -f ($Pairs -join ', '))))
      }

      If ([System.String]::IsNullOrEmpty($Section.Message) -eq $False) {
        $Details.Add([System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.MessageLine'] -f $Section.Message)))
      }

      If ($Section.ItemCount -gt 0) {
        $ItemList = [System.String[]]@(@($Section.Items) | ForEach-Object -Process:({ '<li>{0}</li>' -f [System.Net.WebUtility]::HtmlEncode($PSItem) }))
        $Details.Add(('{0}<ul>{1}</ul>' -f [System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.ItemsHeading'] -f $Section.ItemCount)), ($ItemList -join '')))
        If ($Section.OmittedItems -gt 0) {
          $Details.Add([System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.Omitted'] -f $Section.OmittedItems)))
        }
      }

      If ([System.String]::IsNullOrEmpty($Section.ErrorMessage) -eq $False) {
        $Details.Add([System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.ErrorAt'] -f $Section.ErrorMessage, $(If ($Section.ErrorTime -is [System.DateTime]) { $Section.ErrorTime.ToString('yyyy-MM-dd HH:mm:ss', $Culture) } Else { [System.String]$Section.ErrorTime }))))
      }

      $Lines.Add(('<tr class="status-{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4} s</td><td>{5}</td></tr>' -f $Section.Status.ToLowerInvariant(), $Section.Order, [System.Net.WebUtility]::HtmlEncode($Section.Name), [System.Net.WebUtility]::HtmlEncode($Section.Status), $Section.DurationSeconds.ToString('0.0', $Culture), ($Details -join '<br>')))
    }

    $Lines.Add('</tbody>')
    $Lines.Add('</table>')
  }

  $Lines.Add(('<p class="totals">{0}<br>{1}<br>{2}</p>' -f [System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.StageTotals'] -f $Report.Totals.Stages.Success, $Report.Totals.Stages.Warning, $Report.Totals.Stages.Error, $Report.Totals.Stages.Skipped, $Report.Totals.Stages.NotRun)), [System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.NoticeTotals'] -f $Report.Totals.Notices.Error, $Report.Totals.Notices.High, $Report.Totals.Notices.Warning, $Report.Totals.Notices.Information)), [System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.Duration'] -f $Report.DurationSeconds.ToString('0.0', $Culture)))))
  $Lines.Add(('<p class="run-status status-{0}">{1}</p>' -f $Report.Status.ToLowerInvariant(), [System.Net.WebUtility]::HtmlEncode(($Script:Message['New-MaintenanceReport.Status'] -f $Report.Status, $Report.ExitCode))))
  $Lines.Add('</body>')
  $Lines.Add('</html>')

  [System.String]$Result = ($Lines -join "`r`n") + "`r`n"

  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceReportHtml] Exiting'
}
