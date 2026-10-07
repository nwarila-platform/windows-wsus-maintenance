#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Remove-SyncHistory.All'          = 'of any age (retention 0)'
  'Remove-SyncHistory.Budget'       = 'Time budget reached after removing {0} synchronization-history record(s); the rest are removed on the next run.'
  'Remove-SyncHistory.DrySummary'   = 'Would remove {0} synchronization-history record(s) {1}.'
  'Remove-SyncHistory.NoAge'        = 'Synchronization history was not cleaned: dbo.tbEventInstance has no TimeAtServer column to measure the age of a record by. Set syncHistory.retentionDays to 0 to remove every such record, or disable the stage.'
  'Remove-SyncHistory.NoAgeSummary' = 'not cleaned: record age cannot be determined'
  'Remove-SyncHistory.OlderThan'    = 'older than {0} day(s)'
  'Remove-SyncHistory.Summary'      = 'Removed {0} synchronization-history record(s) {1}.'
}

Function Remove-SyncHistory {
  <#
    .SYNOPSIS
        Deletes old synchronization-history records from SUSDB.

    .DESCRIPTION
        Removes the synchronization-history records Microsoft's manual-maintenance article deletes
        (dbo.tbEventInstance rows of event namespace 2 with event identifiers 381, 382, 384, 386, 387
        and 389) when they are older than syncHistory.retentionDays; zero removes every such record.
        The age is taken from the TimeAtServer column, compared with the current UTC time; when that
        column does not exist the stage deletes nothing and raises a Warning notice. Records are
        deleted in batches of 10,000 so the time budget applies between batches. A dry run only counts.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Remove-SyncHistory -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#remove-synchistory',
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

  Write-Debug -Message:'[Remove-SyncHistory] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Affected = 0
  [System.Int32]$Private:BatchSize = 10000
  [System.Object]$Private:Column = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Object]$Private:Database = $Null
  [System.Int32]$Private:Days = 0
  [System.String]$Private:Filter = 'EventNamespaceID = ''2'' AND EventID IN (''381'', ''382'', ''384'', ''386'', ''387'', ''389'')'
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Collections.Hashtable]$Private:Parameters = $Null
  [System.String]$Private:Scope = [System.String]::Empty
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Int32]$Private:Timeout = 0
  [PSCustomObject]$Private:Result = $Null

  # The record kinds are the ones deleted by the synchronization-history step of
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-automatic-maintenance
  #   Code samples in that article: Copyright (c) Microsoft Corporation, MIT License.
  $Database = Get-SusdbConnection -Context:$Context
  $Timeout = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0)
  $Days = [System.Int32]$Context.Configuration.syncHistory.retentionDays
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  $Counts['Matched'] = [System.Int64]0
  $Counts['Removed'] = [System.Int64]0
  $Parameters = @{ days = $Days; batch = $BatchSize }
  $Scope = $Script:Message['Remove-SyncHistory.All']
  If ($Days -gt 0) {
    $Scope = $Script:Message['Remove-SyncHistory.OlderThan'] -f $Days
  }

  If ($Days -gt 0) {
    $Column = @(Invoke-SusdbCommand -CommandText:'SELECT COL_LENGTH(N''dbo.tbEventInstance'', N''TimeAtServer'') AS Length' -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout) | Select-Object -First:1
    If (($Null -eq $Column) -or ($Null -eq $Column.Length)) {
      $Status = 'Warning'
      $Summary = $Script:Message['Remove-SyncHistory.NoAgeSummary']
      $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Remove-SyncHistory.NoAge'] -Severity:'Warning' -Stage:'SyncHistory'))
    } Else {
      $Filter = '{0} AND TimeAtServer < DATEADD(DAY, -@days, GETUTCDATE())' -f $Filter
    }
  }

  If ($Status -eq 'Success') {
    $Counts['Matched'] = [System.Int64](@(Invoke-SusdbCommand -CommandText:('SELECT COUNT_BIG(*) AS Total FROM dbo.tbEventInstance WHERE {0}' -f $Filter) -Connection:$Database -Log:$Context.Log -Parameter:$Parameters -TimeoutSeconds:$Timeout) | Select-Object -First:1).Total

    If ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Remove-SyncHistory.DrySummary'] -f $Counts['Matched'], $Scope
    } Else {
      Do {
        If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
          $Status = 'Warning'
          $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-SyncHistory.Budget'] -f $Counts['Removed']) -Severity:'Warning' -Stage:'SyncHistory'))
          Break
        }

        $Affected = [System.Int32](Invoke-SusdbCommand -CommandText:('DELETE TOP (@batch) FROM dbo.tbEventInstance WHERE {0}' -f $Filter) -Connection:$Database -Log:$Context.Log -NonQuery -Parameter:$Parameters -TimeoutSeconds:$Timeout)
        $Counts['Removed'] = $Counts['Removed'] + $Affected
      } While ($Affected -ge $BatchSize)

      $Summary = $Script:Message['Remove-SyncHistory.Summary'] -f $Counts['Removed'], $Scope
    }
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Remove-SyncHistory] Exiting'
}
