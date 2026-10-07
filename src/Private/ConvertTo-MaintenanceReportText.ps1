#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'ConvertTo-MaintenanceReportText.Highest'   = '>>> [{0}] {1}'
  'ConvertTo-MaintenanceReportText.Notice'    = '    [{0}] {1}'
  'ConvertTo-MaintenanceReportText.StageLine' = '{0,2}. {1}: {2}, {3} s'
}

Function ConvertTo-MaintenanceReportText {
  <#
    .SYNOPSIS
        Renders a run report as plain text.

    .DESCRIPTION
        Lays the report out in report order with aligned header fields. The notices of the highest
        severity present are marked prominently: they start with ">>>" and carry their severity in
        capitals. A link is printed as its plain address and a suggested command as an indented block.
        Each stage takes one line with its order, name, status and duration, followed by its reason,
        counts, message, items and any error. Lines end with CR LF.

    .PARAMETER Report
        The report from New-MaintenanceReport.

    .EXAMPLE
        ConvertTo-MaintenanceReportText -Report $Report

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenancereporttext',
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

  Write-Debug -Message:'[ConvertTo-MaintenanceReportText] Entering'

  # Initialize Variable(s)
  [System.Globalization.CultureInfo]$Private:Culture = [System.Globalization.CultureInfo]::InvariantCulture
  [System.String]$Private:Heading = [System.String]::Empty
  [System.String]$Private:Line = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Lines = $Null
  [System.String[]]$Private:Pairs = @()
  [System.Int32]$Private:Width = 0
  [System.String]$Private:Result = [System.String]::Empty

  $Lines = [System.Collections.Generic.List[System.String]]::new()
  $Lines.Add($Report.Title)
  $Lines.Add(('=' * $Report.Title.Length))
  $Lines.Add('')

  ForEach ($Pair In @($Report.Header)) {
    If ($Pair.Label.Length -gt $Width) {
      $Width = $Pair.Label.Length
    }
  }

  ForEach ($Pair In @($Report.Header)) {
    $Lines.Add(('{0} : {1}' -f $Pair.Label.PadRight($Width), $Pair.Value))
  }

  $Lines.Add('')

  If ($Null -ne $Report.Failure) {
    $Lines.Add($Script:Message['New-MaintenanceReport.FailureHeading'].ToUpperInvariant())
    $Lines.Add(('-' * $Script:Message['New-MaintenanceReport.FailureHeading'].Length))
    $Width = [System.Math]::Max([System.Math]::Max($Script:Message['New-MaintenanceReport.WhatHappened'].Length, $Script:Message['New-MaintenanceReport.PointReached'].Length), $Script:Message['New-MaintenanceReport.WhatToDo'].Length)
    $Lines.Add(('{0} : {1}' -f $Script:Message['New-MaintenanceReport.WhatHappened'].PadRight($Width), $Report.Failure.Message))
    $Lines.Add(('{0} : {1}' -f $Script:Message['New-MaintenanceReport.PointReached'].PadRight($Width), $Report.Failure.Point))
    $Lines.Add(('{0} : {1}' -f $Script:Message['New-MaintenanceReport.WhatToDo'].PadRight($Width), $Report.Failure.Guidance))
    $Lines.Add('')
  }

  If ([System.String]::IsNullOrEmpty($Report.HighestSeverity) -eq $True) {
    $Heading = ($Script:Message['New-MaintenanceReport.NoticesHeading'] -f @($Report.Notices).Count).ToUpperInvariant()
  } Else {
    $Heading = ($Script:Message['New-MaintenanceReport.NoticesHighest'] -f @($Report.Notices).Count, $Report.HighestSeverity).ToUpperInvariant()
  }

  $Lines.Add($Heading)
  $Lines.Add(('-' * $Heading.Length))
  If (@($Report.Notices).Count -eq 0) {
    $Lines.Add($Script:Message['New-MaintenanceReport.NoNotices'])
  }

  ForEach ($Item In @($Report.Notices)) {
    If ($Item.IsHighest -eq $True) {
      $Line = $Script:Message['ConvertTo-MaintenanceReportText.Highest'] -f $Item.Severity.ToUpperInvariant(), $Item.Message
    } Else {
      $Line = $Script:Message['ConvertTo-MaintenanceReportText.Notice'] -f $Item.Severity, $Item.Message
    }

    If ([System.String]::IsNullOrEmpty($Item.Stage) -eq $False) {
      $Line = '{0} ({1})' -f $Line, $Item.Stage
    }

    $Lines.Add($Line)
    If ([System.String]::IsNullOrEmpty($Item.Link) -eq $False) {
      $Lines.Add(('      {0}' -f ($Script:Message['New-MaintenanceReport.See'] -f $Item.Link)))
    }

    If ([System.String]::IsNullOrEmpty($Item.Command) -eq $False) {
      $Lines.Add(('      {0}' -f $Script:Message['New-MaintenanceReport.Command']))
      ForEach ($CommandLine In @($Item.Command -split '\r?\n')) {
        $Lines.Add(('          {0}' -f $CommandLine))
      }
    }
  }

  $Lines.Add('')
  $Lines.Add(($Script:Message['New-MaintenanceReport.Connection'] -f $Report.Connection))
  $Lines.Add('')
  $Lines.Add($Script:Message['New-MaintenanceReport.StagesHeading'].ToUpperInvariant())
  $Lines.Add(('-' * $Script:Message['New-MaintenanceReport.StagesHeading'].Length))
  If (@($Report.Stages).Count -eq 0) {
    $Lines.Add($Script:Message['New-MaintenanceReport.NoStage'])
  }

  ForEach ($Section In @($Report.Stages)) {
    $Lines.Add(($Script:Message['ConvertTo-MaintenanceReportText.StageLine'] -f $Section.Order, $Section.Name, $Section.Status, $Section.DurationSeconds.ToString('0.0', $Culture)))
    If ([System.String]::IsNullOrEmpty($Section.Reason) -eq $False) {
      $Lines.Add(('    {0}' -f ($Script:Message['New-MaintenanceReport.Reason'] -f $Section.Reason)))
    }

    If (@($Section.Counts).Count -gt 0) {
      $Pairs = [System.String[]]@(@($Section.Counts) | ForEach-Object -Process:({ '{0}={1}' -f $PSItem.Name, [System.Convert]::ToString($PSItem.Value, [System.Globalization.CultureInfo]::InvariantCulture) }))
      $Lines.Add(('    {0}' -f ($Script:Message['New-MaintenanceReport.Counts'] -f ($Pairs -join ', '))))
    }

    If ([System.String]::IsNullOrEmpty($Section.Message) -eq $False) {
      $Lines.Add(('    {0}' -f ($Script:Message['New-MaintenanceReport.MessageLine'] -f $Section.Message)))
    }

    If ($Section.ItemCount -gt 0) {
      $Lines.Add(('    {0}' -f ($Script:Message['New-MaintenanceReport.ItemsHeading'] -f $Section.ItemCount)))
      ForEach ($Entry In @($Section.Items)) {
        $Lines.Add(('      - {0}' -f $Entry))
      }

      If ($Section.OmittedItems -gt 0) {
        $Lines.Add(('      {0}' -f ($Script:Message['New-MaintenanceReport.Omitted'] -f $Section.OmittedItems)))
      }
    }

    If ([System.String]::IsNullOrEmpty($Section.ErrorMessage) -eq $False) {
      $Lines.Add(('    {0}' -f ($Script:Message['New-MaintenanceReport.ErrorAt'] -f $Section.ErrorMessage, $(If ($Section.ErrorTime -is [System.DateTime]) { $Section.ErrorTime.ToString('yyyy-MM-dd HH:mm:ss', $Culture) } Else { [System.String]$Section.ErrorTime }))))
    }
  }

  $Lines.Add('')
  $Lines.Add(($Script:Message['New-MaintenanceReport.StageTotals'] -f $Report.Totals.Stages.Success, $Report.Totals.Stages.Warning, $Report.Totals.Stages.Error, $Report.Totals.Stages.Skipped, $Report.Totals.Stages.NotRun))
  $Lines.Add(($Script:Message['New-MaintenanceReport.NoticeTotals'] -f $Report.Totals.Notices.Error, $Report.Totals.Notices.High, $Report.Totals.Notices.Warning, $Report.Totals.Notices.Information))
  $Lines.Add(($Script:Message['New-MaintenanceReport.Duration'] -f $Report.DurationSeconds.ToString('0.0', $Culture)))
  $Lines.Add(($Script:Message['New-MaintenanceReport.Status'] -f $Report.Status, $Report.ExitCode))

  [System.String]$Result = ($Lines -join "`r`n") + "`r`n"

  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceReportText] Exiting'
}
