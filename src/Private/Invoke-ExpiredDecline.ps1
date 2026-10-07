#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-ExpiredDecline.Budget'       = 'Time budget reached after {0} of {1} decline(s); the rest are declined on the next run.'
  'Invoke-ExpiredDecline.DrySummary'   = 'pending: {0} expired update(s) would be declined. {1} update(s) evaluated.'
  'Invoke-ExpiredDecline.FailedNotice' = '{0} update(s) could not be declined. First failure: {1}'
  'Invoke-ExpiredDecline.Summary'      = 'Declined {0} of {1} expired update(s); {2} failed. {3} update(s) evaluated.'
}

Function Invoke-ExpiredDecline {
  <#
    .SYNOPSIS
        Declines expired updates.

    .DESCRIPTION
        Declines every update in the decline catalog whose publication state is expired and that no
        earlier policy of the run has declined. The never-decline list applies. When the update list
        could not be retrieved the policy makes no declines and ends in error. A dry run declines nothing
        and reports the pending declines.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-ExpiredDecline -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-expireddecline',
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

  Write-Debug -Message:'[Invoke-ExpiredDecline] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:Candidates = $Null
  [PSCustomObject]$Private:Catalog = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Int32]$Private:Expired = 0
  [System.String[]]$Private:NeverDecline = @()
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Outcome = $Null
  [System.Int32]$Private:Protected = 0
  [System.Int32]$Private:Selected = 0
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Catalog = Get-DeclineCatalog -Context:$Context
  If ([System.String]::IsNullOrEmpty($Catalog.Error) -eq $False) {
    [PSCustomObject]$Result = New-DeclineUnavailableResult -Catalog:$Catalog -Stage:$Context.StageName
  } Else {
    $NeverDecline = [System.String[]]@($Context.Configuration.declines.neverDecline)
    $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    ForEach ($Record In $Catalog.Records) {
      If (($Record.IsExpired -eq $True) -and ($Catalog.Claimed.Contains($Record.Id) -eq $False)) {
        $Expired++
        If ((Test-UpdateIdentity -Identity:$NeverDecline -Record:$Record) -eq $True) {
          $Protected++
        } Else {
          $Candidates.Add($Record)
        }
      }
    }

    $Selected = $Candidates.Count
    $Outcome = Invoke-DeclineSelection -Candidate:$Candidates.ToArray() -Catalog:$Catalog -Context:$Context

    If ($Outcome.Failed -gt 0) {
      $Status = 'Error'
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ExpiredDecline.FailedNotice'] -f $Outcome.Failed, $Outcome.Failures[0]) -Severity:'Error' -Stage:$Context.StageName))
    } ElseIf ($Outcome.Stopped -eq $True) {
      $Status = 'Warning'
    }

    If ($Outcome.Stopped -eq $True) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ExpiredDecline.Budget'] -f $Outcome.Declined, $Selected) -Severity:'Warning' -Stage:$Context.StageName))
    }

    $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
    $Counts['Evaluated'] = [System.Int64]$Catalog.Records.Count
    $Counts['Expired'] = [System.Int64]$Expired
    $Counts['Protected'] = [System.Int64]$Protected
    $Counts['Selected'] = [System.Int64]$Selected
    $Counts['Declined'] = [System.Int64]$Outcome.Declined
    $Counts['Pending'] = [System.Int64]$Outcome.Pending
    $Counts['Failed'] = [System.Int64]$Outcome.Failed

    If ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Invoke-ExpiredDecline.DrySummary'] -f $Outcome.Pending, $Catalog.Records.Count
    } Else {
      $Summary = $Script:Message['Invoke-ExpiredDecline.Summary'] -f $Outcome.Declined, $Selected, $Outcome.Failed, $Catalog.Records.Count
    }

    [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Outcome.Items + $Outcome.Failures) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status
  }

  $Result
  Write-Debug -Message:'[Invoke-ExpiredDecline] Exiting'
}
