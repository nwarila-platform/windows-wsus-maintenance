#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Remove-DeclinedUpdate.Budget'          = 'Time budget reached after deleting {0} of {1} declined update(s); the rest are deleted on the next run.'
  'Remove-DeclinedUpdate.Deleted'         = 'deleted: {0}'
  'Remove-DeclinedUpdate.DrySummary'      = 'pending: {0} of {1} declined update(s) would be deleted; {2} protected, {3} excluded by classification.'
  'Remove-DeclinedUpdate.Failed'          = 'failed: {0}: {1}'
  'Remove-DeclinedUpdate.FailedNotice'    = '{0} declined update(s) could not be deleted. First failure: {1}'
  'Remove-DeclinedUpdate.LanguageNotice'  = 'No declined update was deleted: the evaluation language {0} could not be set ({1}), so the classification filters could not be applied reliably.'
  'Remove-DeclinedUpdate.LanguageSummary' = 'nothing deleted: the evaluation language could not be set'
  'Remove-DeclinedUpdate.NoList'          = 'The declined updates could not be retrieved, so none was deleted: {0} A common cause is memory exhaustion of the WsusPool application pool in IIS.'
  'Remove-DeclinedUpdate.NoListSummary'   = 'nothing deleted: the declined updates could not be retrieved'
  'Remove-DeclinedUpdate.Pending'         = 'pending: {0}'
  'Remove-DeclinedUpdate.Summary'         = 'Deleted {0} of {1} declined update(s); {2} protected, {3} excluded by classification, {4} failed.'
}

Function Remove-DeclinedUpdate {
  <#
    .SYNOPSIS
        Deletes declined updates from WSUS.

    .DESCRIPTION
        Retrieves the declined updates (Get-WsusUpdateRecord -Declined) and deletes each with
        IUpdateServer.DeleteUpdate, except updates in declinedDeletion.protected (by Knowledge Base number
        or update GUID), updates in declinedDeletion.excludedClassifications and, when
        declinedDeletion.includedClassifications is not empty, updates outside it. A deletion is hard to
        reverse: recovery needs a re-import or a resynchronization. Each failed deletion (for example an
        update still referenced by another) is listed with its error and the next one proceeds; any
        failure ends the stage in error. The time budget is checked before each deletion. When
        classifications filter the deletion and the evaluation language could not be set, nothing is
        deleted, because classification titles could not be compared reliably. A dry run deletes nothing
        and lists the pending deletions. The stage is off by default and does not run on a replica.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Remove-DeclinedUpdate -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#remove-declinedupdate',
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

  Write-Debug -Message:'[Remove-DeclinedUpdate] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:BatchSize = 1
  [System.Collections.Generic.List[PSCustomObject]]$Private:Candidates = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.String[]]$Private:Excluded = @()
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.String[]]$Private:Included = @()
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String[]]$Private:Protected = @()
  [PSCustomObject]$Private:Record = $Null
  [PSCustomObject]$Private:Retrieval = $Null
  [System.Object]$Private:Settings = $Null
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.String]$Private:Text = [System.String]::Empty
  [System.Object]$Private:UpdateServer = $Null
  [PSCustomObject]$Private:Result = $Null

  $UpdateServer = Get-WsusConnection -Context:$Context
  $Settings = $Context.Configuration.declinedDeletion
  $Protected = [System.String[]]@($Settings.protected)
  $Included = [System.String[]]@($Settings.includedClassifications)
  $Excluded = [System.String[]]@($Settings.excludedClassifications)
  $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Failures = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Found', 'Protected', 'ExcludedByClassification', 'Selected', 'Deleted', 'Pending', 'Failed')) {
    $Counts[$Name] = [System.Int64]0
  }

  # Declined updates are deleted with IUpdateServer.DeleteUpdate:
  #   https://learn.microsoft.com/previous-versions/windows/desktop/aa349863(v=vs.85)
  $Retrieval = Get-WsusUpdateRecord -Context:$Context -Declined
  If ([System.String]::IsNullOrEmpty($Retrieval.Error) -eq $False) {
    $Status = 'Error'
    $Summary = $Script:Message['Remove-DeclinedUpdate.NoListSummary']
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-DeclinedUpdate.NoList'] -f $Retrieval.Error) -Severity:'Error' -Stage:$Context.StageName))
  } ElseIf (([System.String]::IsNullOrEmpty($Retrieval.LanguageError) -eq $False) -and (($Included.Count + $Excluded.Count) -gt 0)) {
    $Status = 'Error'
    $Summary = $Script:Message['Remove-DeclinedUpdate.LanguageSummary']
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-DeclinedUpdate.LanguageNotice'] -f $Retrieval.Language, $Retrieval.LanguageError) -Severity:'Error' -Stage:$Context.StageName))
  } Else {
    $Candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    ForEach ($Record In $Retrieval.Records) {
      $Counts['Found'] = $Counts['Found'] + 1
      If ((Test-UpdateIdentity -Identity:$Protected -Record:$Record) -eq $True) {
        $Counts['Protected'] = $Counts['Protected'] + 1
      } ElseIf ((($Included.Count -gt 0) -and ($Included -notcontains $Record.ClassificationTitle)) -or ($Excluded -contains $Record.ClassificationTitle)) {
        $Counts['ExcludedByClassification'] = $Counts['ExcludedByClassification'] + 1
      } Else {
        $Candidates.Add($Record)
      }
    }

    $Counts['Selected'] = [System.Int64]$Candidates.Count
    $Started = Get-MaintenanceTime
    For ($Position = 1; $Position -le $Candidates.Count; $Position++) {
      $Record = $Candidates[$Position - 1]
      $Text = ConvertTo-DeclineItemText -Record:$Record
      If ($Context.DryRun -eq $True) {
        $Counts['Pending'] = $Counts['Pending'] + 1
        $Items.Add(($Script:Message['Remove-DeclinedUpdate.Pending'] -f $Text))
        Continue
      }

      If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
        $Stopped = $True
        Break
      }

      Try {
        $UpdateServer.DeleteUpdate([System.Guid]$Record.Id)
        $Counts['Deleted'] = $Counts['Deleted'] + 1
        $Items.Add(($Script:Message['Remove-DeclinedUpdate.Deleted'] -f $Text))
      } Catch {
        $Failures.Add(($Script:Message['Remove-DeclinedUpdate.Failed'] -f $Text, $PSItem.Exception.Message))
        Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Remove-DeclinedUpdate.Failed'] -f $Text, $PSItem.Exception.Message) -Stage:$Context.StageName
      }

      Write-MaintenanceProgress -BatchSize:$BatchSize -Item:$Record.Title -Log:$Context.Log -Position:$Position -Stage:$Context.StageName -StartedAt:$Started -Total:$Candidates.Count
    }

    $Counts['Failed'] = [System.Int64]$Failures.Count
    If ($Failures.Count -gt 0) {
      $Status = 'Error'
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-DeclinedUpdate.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Error' -Stage:$Context.StageName))
    } ElseIf ($Stopped -eq $True) {
      $Status = 'Warning'
    }

    If ($Stopped -eq $True) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-DeclinedUpdate.Budget'] -f $Counts['Deleted'], $Candidates.Count) -Severity:'Warning' -Stage:$Context.StageName))
    }

    If ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Remove-DeclinedUpdate.DrySummary'] -f $Counts['Pending'], $Counts['Found'], $Counts['Protected'], $Counts['ExcludedByClassification']
    } Else {
      $Summary = $Script:Message['Remove-DeclinedUpdate.Summary'] -f $Counts['Deleted'], $Counts['Found'], $Counts['Protected'], $Counts['ExcludedByClassification'], $Counts['Failed']
    }
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Remove-DeclinedUpdate] Exiting'
}
