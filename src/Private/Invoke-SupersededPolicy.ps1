#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-SupersededPolicy.AllClassifications' = 'superseded update(s)'
  'Invoke-SupersededPolicy.Budget'             = 'Time budget reached after {0} of {1} decline(s); the rest are declined on the next run.'
  'Invoke-SupersededPolicy.DrySummary'         = 'pending: {0} {1} older than {2} day(s) would be declined; {3} newer kept. {4} update(s) evaluated.'
  'Invoke-SupersededPolicy.FailedNotice'       = '{0} update(s) could not be declined. First failure: {1}'
  'Invoke-SupersededPolicy.InClassifications'  = 'superseded update(s) in {0}'
  'Invoke-SupersededPolicy.Summary'            = 'Declined {0} of {1} {2} older than {3} day(s); {4} newer kept; {5} failed. {6} update(s) evaluated.'
}

Function Invoke-SupersededPolicy {
  <#
    .SYNOPSIS
        Applies a superseded-update decline policy.

    .DESCRIPTION
        Declines the superseded updates that Select-SupersededUpdate selects from the decline catalog,
        with the age threshold and classifications given and the declines.superseded options for
        approved updates and the last level of a supersedence chain. The never-decline list applies. The
        items list each update with its title, Knowledge Base references and creation date; the counts
        include the superseded updates still inside the age threshold. When the update list could not be
        retrieved the policy makes no declines and ends in error. A dry run declines nothing and reports
        the pending declines.

    .PARAMETER AgeDays
        Age threshold in days.

    .PARAMETER Classification
        Classification titles to limit the policy to; empty means all.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-SupersededPolicy -AgeDays 90 -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-supersededpolicy',
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
    [System.Int32]
    $AgeDays,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Classification = @(),

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

  Write-Debug -Message:'[Invoke-SupersededPolicy] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Catalog = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Outcome = $Null
  [System.String]$Private:Scope = [System.String]::Empty
  [System.Int32]$Private:Selected = 0
  [PSCustomObject]$Private:Selection = $Null
  [System.Object]$Private:Settings = $Null
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Catalog = Get-DeclineCatalog -Context:$Context
  If ([System.String]::IsNullOrEmpty($Catalog.Error) -eq $False) {
    [PSCustomObject]$Result = New-DeclineUnavailableResult -Catalog:$Catalog -Stage:$Context.StageName
  } Else {
    $Settings = $Context.Configuration.declines
    $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Selection = Select-SupersededUpdate -AgeDays:$AgeDays -Catalog:$Catalog -Classification:$Classification -IncludeApproved:([System.Boolean]$Settings.superseded.includeApproved) -LastLevelOnly:([System.Boolean]$Settings.superseded.lastLevelOnly) -NeverDecline:([System.String[]]@($Settings.neverDecline)) -Now:$Context.RunStart.ToUniversalTime()
    $Selected = $Selection.Candidates.Count
    $Outcome = Invoke-DeclineSelection -Candidate:$Selection.Candidates -Catalog:$Catalog -Context:$Context

    If ($Outcome.Failed -gt 0) {
      $Status = 'Error'
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-SupersededPolicy.FailedNotice'] -f $Outcome.Failed, $Outcome.Failures[0]) -Severity:'Error' -Stage:$Context.StageName))
    } ElseIf ($Outcome.Stopped -eq $True) {
      $Status = 'Warning'
    }

    If ($Outcome.Stopped -eq $True) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-SupersededPolicy.Budget'] -f $Outcome.Declined, $Selected) -Severity:'Warning' -Stage:$Context.StageName))
    }

    $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
    $Counts['Evaluated'] = [System.Int64]$Catalog.Records.Count
    $Counts['Superseded'] = [System.Int64]$Selection.Superseded
    $Counts['WithinThreshold'] = [System.Int64]$Selection.WithinThreshold
    $Counts['IntermediateKept'] = [System.Int64]$Selection.IntermediateKept
    $Counts['ApprovedKept'] = [System.Int64]$Selection.ApprovedKept
    $Counts['Protected'] = [System.Int64]$Selection.Protected
    $Counts['Selected'] = [System.Int64]$Selected
    $Counts['Declined'] = [System.Int64]$Outcome.Declined
    $Counts['Pending'] = [System.Int64]$Outcome.Pending
    $Counts['Failed'] = [System.Int64]$Outcome.Failed

    $Scope = $Script:Message['Invoke-SupersededPolicy.AllClassifications']
    If ($Classification.Count -gt 0) {
      $Scope = $Script:Message['Invoke-SupersededPolicy.InClassifications'] -f ($Classification -join ', ')
    }

    If ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Invoke-SupersededPolicy.DrySummary'] -f $Outcome.Pending, $Scope, $AgeDays, $Selection.WithinThreshold, $Catalog.Records.Count
    } Else {
      $Summary = $Script:Message['Invoke-SupersededPolicy.Summary'] -f $Outcome.Declined, $Selected, $Scope, $AgeDays, $Selection.WithinThreshold, $Outcome.Failed, $Catalog.Records.Count
    }

    [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Outcome.Items + $Outcome.Failures) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status
  }

  $Result
  Write-Debug -Message:'[Invoke-SupersededPolicy] Exiting'
}
