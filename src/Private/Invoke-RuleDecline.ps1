#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-RuleDecline.Budget'          = 'Time budget reached while rule {0} was declining; the remaining declines and rules run on the next run.'
  'Invoke-RuleDecline.DryRuleLine'     = 'rule {0}: {1} matched, pending: {2}'
  'Invoke-RuleDecline.DrySummary'      = 'pending: {3} update(s) would be declined by {0} rule(s); {2} matched of {1} update(s) evaluated in language {4}.'
  'Invoke-RuleDecline.FailedNotice'    = '{0} rule decline(s) failed. First failure: {1}'
  'Invoke-RuleDecline.LanguageNotice'  = 'Rule-based declines were skipped: the evaluation language {0} could not be set ({1}). The age- and state-based declines still ran.'
  'Invoke-RuleDecline.LanguageSummary' = 'skipped: the evaluation language could not be set'
  'Invoke-RuleDecline.RuleFailed'      = 'rule {0} could not be evaluated: {1}'
  'Invoke-RuleDecline.RuleLine'        = 'rule {0}: {1} matched, {2} declined, {3} failed'
  'Invoke-RuleDecline.Summary'         = 'Evaluated {0} rule(s) over {1} update(s) in language {5}: {2} matched, {3} declined, {4} failed.'
}

Function Invoke-RuleDecline {
  <#
    .SYNOPSIS
        Declines the updates that the configured decline rules describe.

    .DESCRIPTION
        Evaluates each enabled rule of declines.rules, in order, against the updates in the decline
        catalog that no earlier policy or rule of the run has declined; a rule whose group in
        declines.groups is disabled does not run. Each rule declines the updates its condition matches
        (Test-DeclineRuleCondition), except those on the never-decline list, and the items give per rule
        its name, the number matched and the number declined (pending in a dry run), followed by the
        updates. Titles and category names are those retrieved in declines.evaluationLanguage; when that
        language could not be set, rule-based declines are skipped with an Error notice while the age- and
        state-based policies still run. A rule that cannot be evaluated is reported and the next rule
        runs.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-RuleDecline -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-ruledecline',
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

  Write-Debug -Message:'[Invoke-RuleDecline] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:Candidates = $Null
  [PSCustomObject]$Private:Catalog = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:DisabledGroups = $Null
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Int32]$Private:Matched = 0
  [System.String[]]$Private:NeverDecline = @()
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.DateTime]$Private:Now = [System.DateTime]::MinValue
  [PSCustomObject]$Private:Outcome = $Null
  [System.Object]$Private:Settings = $Null
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Catalog = Get-DeclineCatalog -Context:$Context
  $Settings = $Context.Configuration.declines
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Evaluated', 'Rules', 'Matched', 'Protected', 'Declined', 'Pending', 'Failed')) {
    $Counts[$Name] = [System.Int64]0
  }

  If ([System.String]::IsNullOrEmpty($Catalog.Error) -eq $False) {
    [PSCustomObject]$Result = New-DeclineUnavailableResult -Catalog:$Catalog -Stage:$Context.StageName
  } ElseIf ([System.String]::IsNullOrEmpty($Catalog.LanguageError) -eq $False) {
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-RuleDecline.LanguageNotice'] -f $Catalog.Language, $Catalog.LanguageError) -Severity:'Error' -Stage:$Context.StageName))
    [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Message:$Script:Message['Invoke-RuleDecline.LanguageSummary'] -Notice:$Notices.ToArray() -Status:'Error'
  } Else {
    $NeverDecline = [System.String[]]@($Settings.neverDecline)
    $Now = $Context.RunStart.ToUniversalTime()
    $Items = [System.Collections.Generic.List[System.String]]::new()
    $Failures = [System.Collections.Generic.List[System.String]]::new()
    $DisabledGroups = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    ForEach ($Group In @($Settings.groups)) {
      If (($Null -ne $Group) -and ($Group.enabled -eq $False)) {
        $Null = $DisabledGroups.Add([System.String]$Group.name)
      }
    }

    $Counts['Evaluated'] = [System.Int64]$Catalog.Records.Count
    ForEach ($Rule In @($Settings.rules)) {
      If (($Null -eq $Rule) -or ($Rule.enabled -ne $True)) {
        Continue
      }

      If (($Null -ne $Rule.PSObject.Properties['group']) -and ($DisabledGroups.Contains([System.String]$Rule.group) -eq $True)) {
        Continue
      }

      $Counts['Rules'] = $Counts['Rules'] + 1
      $Candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
      $Matched = 0
      Try {
        ForEach ($Record In $Catalog.Records) {
          If (($Catalog.Claimed.Contains($Record.Id) -eq $False) -and ((Test-DeclineRuleCondition -Condition:$Rule.condition -Now:$Now -Record:$Record) -eq $True)) {
            $Matched++
            If ((Test-UpdateIdentity -Identity:$NeverDecline -Record:$Record) -eq $True) {
              $Counts['Protected'] = $Counts['Protected'] + 1
            } Else {
              $Candidates.Add($Record)
            }
          }
        }
      } Catch {
        $Failures.Add(($Script:Message['Invoke-RuleDecline.RuleFailed'] -f $Rule.name, $PSItem.Exception.Message))
        Continue
      }

      $Outcome = Invoke-DeclineSelection -Candidate:$Candidates.ToArray() -Catalog:$Catalog -Context:$Context -Label:([System.String]$Rule.name)
      $Counts['Matched'] = $Counts['Matched'] + $Matched
      $Counts['Declined'] = $Counts['Declined'] + $Outcome.Declined
      $Counts['Pending'] = $Counts['Pending'] + $Outcome.Pending
      If ($Context.DryRun -eq $True) {
        $Items.Add(($Script:Message['Invoke-RuleDecline.DryRuleLine'] -f $Rule.name, $Matched, $Outcome.Pending))
      } Else {
        $Items.Add(($Script:Message['Invoke-RuleDecline.RuleLine'] -f $Rule.name, $Matched, $Outcome.Declined, $Outcome.Failed))
      }

      ForEach ($Line In $Outcome.Items) {
        $Items.Add($Line)
      }

      ForEach ($Line In $Outcome.Failures) {
        $Failures.Add($Line)
      }

      If ($Outcome.Stopped -eq $True) {
        $Stopped = $True
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-RuleDecline.Budget'] -f $Rule.name) -Severity:'Warning' -Stage:$Context.StageName))
        Break
      }
    }

    $Counts['Failed'] = [System.Int64]$Failures.Count
    If ($Failures.Count -gt 0) {
      $Status = 'Error'
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-RuleDecline.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Error' -Stage:$Context.StageName))
    } ElseIf ($Stopped -eq $True) {
      $Status = 'Warning'
    }

    If ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Invoke-RuleDecline.DrySummary'] -f $Counts['Rules'], $Counts['Evaluated'], $Counts['Matched'], $Counts['Pending'], $Catalog.Language
    } Else {
      $Summary = $Script:Message['Invoke-RuleDecline.Summary'] -f $Counts['Rules'], $Counts['Evaluated'], $Counts['Matched'], $Counts['Declined'], $Counts['Failed'], $Catalog.Language
    }

    [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status
  }

  $Result
  Write-Debug -Message:'[Invoke-RuleDecline] Exiting'
}
