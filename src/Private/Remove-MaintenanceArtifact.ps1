#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Remove-MaintenanceArtifact.Deleted'      = 'deleted: {0}'
  'Remove-MaintenanceArtifact.DrySummary'   = 'pending: {0} artifact file(s) would be deleted.'
  'Remove-MaintenanceArtifact.Failed'       = 'failed: {0}: {1}'
  'Remove-MaintenanceArtifact.FailedNotice' = '{0} artifact file(s) could not be deleted and are retried on the next run. First failure: {1}'
  'Remove-MaintenanceArtifact.Pending'      = 'pending: {0}'
  'Remove-MaintenanceArtifact.Summary'      = 'Deleted {0} run log(s), {1} report file(s) and {2} summary file(s) beyond the retention; {3} failed.'
}

Function Remove-MaintenanceArtifact {
  <#
    .SYNOPSIS
        Applies the retention to the run logs, reports and summaries this script wrote.

    .DESCRIPTION
        For each kind of artifact (run logs, saved reports in either format, run summaries), looks
        directly in its configured folder and in its built-in default folder for files named
        WsusMaintenance-<run identifier> with that kind's extension, which only this script writes, and
        groups them by run (the text and HTML report of one run count as one report). Runs older than
        retention.<kind>.maxAgeDays days, by the time in their run identifier, and runs beyond the
        retention.<kind>.maxCount newest are deleted; zero turns either limit off. Other files and
        sub-folders are never touched, and neither is the current run's log. A file that cannot be
        deleted is a warning. A dry run deletes nothing and lists the files.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Remove-MaintenanceArtifact -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#remove-maintenanceartifact',
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
    [ValidateNotNull()]
    [PSCustomObject]
    $Context
  )

  Write-Debug -Message:'[Remove-MaintenanceArtifact] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Configured = [System.String]::Empty
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.String]$Private:CurrentLog = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:Folders = $Null
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.String]$Private:Key = [System.String]::Empty
  [PSCustomObject[]]$Private:Kinds = @()
  [System.Object]$Private:Limits = $Null
  [System.Text.RegularExpressions.Match]$Private:Match = $Null
  [System.Int32]$Private:MaxAge = 0
  [System.Int32]$Private:MaxCount = 0
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Boolean]$Private:Old = $False
  [System.String[]]$Private:Ordered = @()
  [System.Boolean]$Private:Parsed = $False
  [System.String]$Private:Pattern = [System.String]::Empty
  [System.Object]$Private:Runs = $Null
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Boolean]$Private:Surplus = $False
  [System.DateTime]$Private:Time = [System.DateTime]::MinValue
  [PSCustomObject]$Private:Result = $Null

  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Failures = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  $CurrentLog = [System.String](Get-MaintenancePropertyValue -InputObject:$Context.Log -Name:'Path' -Default:'')
  $Kinds = @(
    [PSCustomObject]@{ Name = 'logs'; Folder = 'log.folder'; Extension = '(?:log)' }
    [PSCustomObject]@{ Name = 'reports'; Folder = 'report.folder'; Extension = '(?:txt|html)' }
    [PSCustomObject]@{ Name = 'summaries'; Folder = 'summary.folder'; Extension = '(?:json)' }
  )

  ForEach ($Kind In $Kinds) {
    $Counts[('{0}Deleted' -f $Kind.Name)] = [System.Int64]0
    $Limits = $Context.Configuration.retention.($Kind.Name)
    $MaxAge = [System.Int32]$Limits.maxAgeDays
    $MaxCount = [System.Int32]$Limits.maxCount
    $Pattern = '^WsusMaintenance-(?<id>(?<time>[0-9]{8}-[0-9]{6})-[0-9a-f]{8})\.' + $Kind.Extension + '$'
    $Folders = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Configured = [System.String](Get-MaintenancePropertyValue -InputObject:$Context.Configuration.($Kind.Folder.Split('.')[0]) -Name:'folder' -Default:'')
    ForEach ($Candidate In @($Configured, [System.String]@(Get-MaintenanceConfigurationRule | Where-Object -FilterScript:({ $PSItem.Path -eq $Kind.Folder }))[0].Default)) {
      If ([System.String]::IsNullOrEmpty($Candidate) -eq $False) {
        $Null = $Folders.Add((Resolve-MaintenancePath -Path:$Candidate))
      }
    }

    $Runs = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.String]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    ForEach ($Folder In $Folders) {
      If ([System.IO.Directory]::Exists($Folder) -eq $False) {
        Continue
      }

      ForEach ($Path In [System.IO.Directory]::GetFiles($Folder)) {
        $Match = [System.Text.RegularExpressions.Regex]::Match([System.IO.Path]::GetFileName($Path), $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        If ($Match.Success -eq $True) {
          $Key = '{0}|{1}' -f $Match.Groups['time'].Value, $Match.Groups['id'].Value.ToLowerInvariant()
          If ($Runs.ContainsKey($Key) -eq $False) {
            $Runs[$Key] = [System.Collections.Generic.List[System.String]]::new()
          }

          $Runs[$Key].Add($Path)
        }
      }
    }

    $Ordered = [System.String[]]@($Runs.Keys)
    [System.Array]::Reverse($Ordered)
    For ($Index = 0; $Index -lt $Ordered.Count; $Index++) {
      $Time = [System.DateTime]::MinValue
      $Parsed = [System.DateTime]::TryParseExact($Ordered[$Index].Split('|')[0], 'yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Time)
      $Old = ($MaxAge -gt 0) -and ($Parsed -eq $True) -and ($Time -lt $Context.RunStart.AddDays(-$MaxAge))
      $Surplus = ($MaxCount -gt 0) -and ($Index -ge $MaxCount)
      If ((($Old -eq $False) -and ($Surplus -eq $False)) -or ($Time -ge $Context.RunStart)) {
        Continue
      }

      ForEach ($Path In $Runs[$Ordered[$Index]]) {
        If ([System.String]::Equals($Path, $CurrentLog, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
          Continue
        }

        If ($Context.DryRun -eq $True) {
          $Items.Add(($Script:Message['Remove-MaintenanceArtifact.Pending'] -f $Path))
          Continue
        }

        Try {
          [System.IO.File]::Delete($Path)
          $Counts[('{0}Deleted' -f $Kind.Name)] = $Counts[('{0}Deleted' -f $Kind.Name)] + 1
          $Items.Add(($Script:Message['Remove-MaintenanceArtifact.Deleted'] -f $Path))
        } Catch {
          $Failures.Add(($Script:Message['Remove-MaintenanceArtifact.Failed'] -f $Path, $PSItem.Exception.GetBaseException().Message))
        }
      }
    }
  }

  ForEach ($Line In $Items) {
    Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:$Line -Stage:$Context.StageName
  }

  $Counts['Failed'] = [System.Int64]$Failures.Count
  If ($Failures.Count -gt 0) {
    $Status = 'Warning'
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-MaintenanceArtifact.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Warning' -Stage:$Context.StageName))
  }

  If ($Context.DryRun -eq $True) {
    $Summary = $Script:Message['Remove-MaintenanceArtifact.DrySummary'] -f $Items.Count
  } Else {
    $Summary = $Script:Message['Remove-MaintenanceArtifact.Summary'] -f $Counts['logsDeleted'], $Counts['reportsDeleted'], $Counts['summariesDeleted'], $Failures.Count
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Remove-MaintenanceArtifact] Exiting'
}
