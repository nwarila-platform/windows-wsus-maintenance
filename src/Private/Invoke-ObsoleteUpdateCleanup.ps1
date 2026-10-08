#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-ObsoleteUpdateCleanup.Budget'          = 'Time budget reached after deleting {0} of {1} selected obsolete updates; the rest are deleted on the next run.'
  'Invoke-ObsoleteUpdateCleanup.Capped'          = 'Cap reached: obsoleteUpdates.maxDeletions allows {0} deletions per run and {1} obsolete updates were found; the rest are deleted on later runs.'
  'Invoke-ObsoleteUpdateCleanup.DrySummary'      = 'Would delete {0} of {1} obsolete update(s).'
  'Invoke-ObsoleteUpdateCleanup.FailedItem'      = '{0}: deletion failed: {1}'
  'Invoke-ObsoleteUpdateCleanup.FailedNotice'    = '{0} obsolete update(s) could not be deleted. First failure: {1}'
  'Invoke-ObsoleteUpdateCleanup.Progress'        = 'update {0} deleted in {1} s'
  'Invoke-ObsoleteUpdateCleanup.ProgressFailed'  = 'update {0} failed after {1} s'
  'Invoke-ObsoleteUpdateCleanup.Rejected'        = 'The database rejected the deletion of obsolete updates, as expected on a replica (rejected by server role): {0}'
  'Invoke-ObsoleteUpdateCleanup.RejectedSummary' = 'rejected by server role'
  'Invoke-ObsoleteUpdateCleanup.Summary'         = 'Found {0} obsolete update(s); deleted {1}; {2} failed.'
}

Function Invoke-ObsoleteUpdateCleanup {
  <#
    .SYNOPSIS
        Deletes obsolete updates one at a time with the SUSDB procedures Microsoft documents.

    .DESCRIPTION
        Asks dbo.spGetObsoleteUpdatesToCleanup for the obsolete updates and deletes them one at a time
        with dbo.spDeleteUpdate, so every finished deletion persists even if the run is interrupted. Each
        deletion is logged with its position, the number selected, the update identifier and how long it
        took (run.progressBatchSize sets how often). obsoleteUpdates.maxDeletions caps the deletions per
        run: when more are found, exactly that many are deleted and a Warning notice says the cap was
        reached. The time budget is checked before each deletion; what is left runs next time. A failed
        deletion is recorded with the identifier and the error, and the next one proceeds; the stage
        then ends in error. On a replica a refusal is reported as "rejected by server role", a warning,
        and the stage stops. A dry run deletes nothing and reports how many would be deleted.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-ObsoleteUpdateCleanup -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-obsoleteupdatecleanup',
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

  Write-Debug -Message:'[Invoke-ObsoleteUpdateCleanup] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:BatchSize = 1
  [System.Int32]$Private:Cap = 0
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Object]$Private:Database = $Null
  [System.Int32]$Private:Deleted = 0
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.Int32]$Private:Identifier = 0
  [System.Collections.Generic.List[System.Int32]]$Private:Identifiers = [System.Collections.Generic.List[System.Int32]]::new()
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.DateTime]$Private:ItemStarted = [System.DateTime]::MinValue
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String]$Private:ProgressFormat = [System.String]::Empty
  [System.Boolean]$Private:Rejected = $False
  [System.Int32]$Private:Selected = 0
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.String]$Private:Tier = [System.String]::Empty
  [System.Int32]$Private:Timeout = 0
  [PSCustomObject]$Private:Result = $Null

  $Database = Get-SusdbConnection -Context:$Context
  $Timeout = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0)
  $Cap = [System.Int32]$Context.Configuration.obsoleteUpdates.maxDeletions
  $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
  $Tier = [System.String](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'Tier' -Default:'')
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Failures = [System.Collections.Generic.List[System.String]]::new()

  # The procedures and the one-update-at-a-time order are the ones Microsoft documents:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide
  ForEach ($Row In @(Invoke-SusdbCommand -CommandText:'EXEC dbo.spGetObsoleteUpdatesToCleanup' -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout)) {
    $Identifiers.Add([System.Int32](@($Row.PSObject.Properties)[0].Value))
  }

  $Selected = $Identifiers.Count
  If (($Cap -gt 0) -and ($Identifiers.Count -gt $Cap)) {
    $Selected = $Cap
  }

  $Started = Get-MaintenanceTime
  For ($Position = 1; $Position -le $Selected; $Position++) {
    $Identifier = $Identifiers[$Position - 1]
    If ($Context.DryRun -eq $True) {
      $Items.Add([System.String]$Identifier)
      Continue
    }

    If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
      $Stopped = $True
      Break
    }

    $ItemStarted = Get-MaintenanceTime
    $ProgressFormat = $Script:Message['Invoke-ObsoleteUpdateCleanup.Progress']
    Try {
      $Null = Invoke-SusdbCommand -CommandText:'EXEC dbo.spDeleteUpdate @localUpdateID = @localUpdateID' -Connection:$Database -Log:$Context.Log -NonQuery -Parameter:@{ localUpdateID = $Identifier } -TimeoutSeconds:$Timeout
      $Deleted++
      $Items.Add([System.String]$Identifier)
    } Catch {
      $ProgressFormat = $Script:Message['Invoke-ObsoleteUpdateCleanup.ProgressFailed']
      If ($Tier -eq 'Replica') {
        $Rejected = $True
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ObsoleteUpdateCleanup.Rejected'] -f $PSItem.Exception.Message) -Severity:'Warning' -Stage:'ObsoleteUpdates'))
        Break
      }

      $Failures.Add(($Script:Message['Invoke-ObsoleteUpdateCleanup.FailedItem'] -f $Identifier, $PSItem.Exception.Message))
      Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-ObsoleteUpdateCleanup.FailedItem'] -f $Identifier, $PSItem.Exception.Message) -Stage:'ObsoleteUpdates'
    }

    Write-MaintenanceProgress -BatchSize:$BatchSize -Item:($ProgressFormat -f $Identifier, [System.Math]::Max([System.Double]0, ((Get-MaintenanceTime) - $ItemStarted).TotalSeconds).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)) -Log:$Context.Log -Position:$Position -Stage:'ObsoleteUpdates' -StartedAt:$Started -Total:$Selected
  }

  If ($Failures.Count -gt 0) {
    $Status = 'Error'
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ObsoleteUpdateCleanup.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Error' -Stage:'ObsoleteUpdates'))
  } ElseIf ($Rejected -eq $True) {
    $Status = 'Warning'
  }

  If (($Selected -lt $Identifiers.Count) -and ($Rejected -eq $False)) {
    If ($Status -eq 'Success') {
      $Status = 'Warning'
    }

    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ObsoleteUpdateCleanup.Capped'] -f $Cap, $Identifiers.Count) -Severity:'Warning' -Stage:'ObsoleteUpdates'))
  }

  If ($Stopped -eq $True) {
    If ($Status -eq 'Success') {
      $Status = 'Warning'
    }

    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ObsoleteUpdateCleanup.Budget'] -f $Deleted, $Selected) -Severity:'Warning' -Stage:'ObsoleteUpdates'))
  }

  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  $Counts['Found'] = $Identifiers.Count
  $Counts['Selected'] = $Selected
  $Counts['Deleted'] = $Deleted
  $Counts['Failed'] = $Failures.Count

  If ($Context.DryRun -eq $True) {
    $Summary = $Script:Message['Invoke-ObsoleteUpdateCleanup.DrySummary'] -f $Selected, $Identifiers.Count
  } ElseIf ($Rejected -eq $True) {
    $Summary = $Script:Message['Invoke-ObsoleteUpdateCleanup.RejectedSummary']
  } Else {
    $Summary = $Script:Message['Invoke-ObsoleteUpdateCleanup.Summary'] -f $Identifiers.Count, $Deleted, $Failures.Count
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Invoke-ObsoleteUpdateCleanup] Exiting'
}
