#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-SusdbIndexMaintenance.Budget'                = 'Time budget reached before every selected index was handled; statistics were not updated. The rest is done on the next run.'
  'Invoke-SusdbIndexMaintenance.DrySummary'            = 'Would defragment {0} index(es) and then update statistics.'
  'Invoke-SusdbIndexMaintenance.FailedItem'            = '{0}: failed: {1}'
  'Invoke-SusdbIndexMaintenance.FailedNotice'          = '{0} index(es) could not be defragmented; statistics were not updated for this run.'
  'Invoke-SusdbIndexMaintenance.Item'                  = '{0} on {1}: {2} (fragmentation {3}%, page density {4}%)'
  'Invoke-SusdbIndexMaintenance.NotOwner'              = 'Statistics were not updated: login {0} is neither the SUSDB owner nor sysadmin, which sp_updatestats requires. Make the run identity the database owner or a sysadmin.'
  'Invoke-SusdbIndexMaintenance.OwnerCommand'          = 'ALTER AUTHORIZATION ON DATABASE::{0} TO {1};'
  'Invoke-SusdbIndexMaintenance.Rebuild'               = 'rebuild'
  'Invoke-SusdbIndexMaintenance.RebuildWithFillFactor' = 'rebuild with fill factor 90'
  'Invoke-SusdbIndexMaintenance.Reorganize'            = 'reorganize'
  'Invoke-SusdbIndexMaintenance.StatisticsDone'        = 'statistics updated'
  'Invoke-SusdbIndexMaintenance.StatisticsFailed'      = 'Statistics could not be updated: {0}'
  'Invoke-SusdbIndexMaintenance.StatisticsSkipped'     = 'statistics not updated'
  'Invoke-SusdbIndexMaintenance.Summary'               = 'Reorganized {0} and rebuilt {1} index(es); {2} failed; about {3} page(s) freed; {4}.'
}

Function Invoke-SusdbIndexMaintenance {
  <#
    .SYNOPSIS
        Defragments fragmented SUSDB indexes and then updates statistics.

    .DESCRIPTION
        Selects indexes as Microsoft's re-index script for SUSDB does (sys.dm_db_index_physical_stats in
        SAMPLED mode: page density below 85 percent with more than one page to gain, or fragmentation
        above 15 percent on more than 50 pages, or above 80 percent on more than 10 pages), and handles
        each with the action Get-SusdbIndexAction chooses, one statement per index so the time budget
        and progress logging apply between indexes. Heaps are left out, as the published script cannot
        act on them, and an index with several qualifying allocation units or partitions is handled
        once, with the figures of its in-row data where that qualifies. It then estimates the pages freed from the used
        pages before and after. Statistics are updated with sp_updatestats only when every index
        succeeded and the run identity is the database owner or sysadmin, which sp_updatestats
        requires; otherwise a Warning notice names the identity and the corrective action. A failed
        index is recorded, statistics are skipped for the run, and the stage ends in error. A dry run
        lists the planned actions and changes nothing.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-SusdbIndexMaintenance -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-susdbindexmaintenance',
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

  Write-Debug -Message:'[Invoke-SusdbIndexMaintenance] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Action = [System.String]::Empty
  [System.Collections.Hashtable]$Private:After = $Null
  [System.Int32]$Private:BatchSize = 1
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Object]$Private:Database = $Null
  [System.String]$Private:Description = [System.String]::Empty
  [System.Object]$Private:Index = $Null
  [System.Object[]]$Private:Indexes = @()
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.String]$Private:Key = [System.String]::Empty
  [System.String]$Private:Login = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String]$Private:PagesQuery = 'SELECT object_id AS ObjectId, index_id AS IndexId, CAST(SUM(used_page_count) AS BIGINT) AS UsedPages FROM sys.dm_db_partition_stats GROUP BY object_id, index_id'
  [System.Object]$Private:Permission = $Null
  [System.String]$Private:SelectionQuery = @(
    'WITH Fragmented AS (',
    '  SELECT',
    '    f.object_id, f.index_id, f.avg_page_space_used_in_percent, f.avg_fragmentation_in_percent, f.record_count,',
    '    ROW_NUMBER() OVER (PARTITION BY f.object_id, f.index_id ORDER BY CASE f.alloc_unit_type_desc WHEN N''IN_ROW_DATA'' THEN 0 ELSE 1 END, f.partition_number) AS RowRank',
    '  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''SAMPLED'') AS f',
    '  WHERE f.index_id > 0',
    '    AND ((f.avg_page_space_used_in_percent < 85.0 AND f.avg_page_space_used_in_percent / 100.0 * f.page_count < f.page_count - 1)',
    '      OR (f.page_count > 50 AND f.avg_fragmentation_in_percent > 15.0)',
    '      OR (f.page_count > 10 AND f.avg_fragmentation_in_percent > 80.0))',
    ')',
    'SELECT',
    '  f.object_id AS ObjectId,',
    '  f.index_id AS IndexId,',
    '  QUOTENAME(s.name) + N''.'' + QUOTENAME(o.name) AS TableName,',
    '  QUOTENAME(i.name) AS IndexName,',
    '  f.avg_page_space_used_in_percent AS Density,',
    '  f.avg_fragmentation_in_percent AS Fragmentation,',
    '  CAST(f.record_count AS BIGINT) AS RecordCount,',
    '  CAST(i.fill_factor AS INT) AS FillFactor,',
    '  (SELECT CAST(SUM(p.used_page_count) AS BIGINT) FROM sys.dm_db_partition_stats AS p WHERE p.object_id = f.object_id AND p.index_id = f.index_id) AS UsedPages',
    'FROM Fragmented AS f',
    'INNER JOIN sys.indexes AS i ON i.object_id = f.object_id AND i.index_id = f.index_id',
    'INNER JOIN sys.objects AS o ON o.object_id = f.object_id',
    'INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id',
    'WHERE f.RowRank = 1',
    'ORDER BY TableName, IndexName'
  ) -join [System.Environment]::NewLine
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.String]$Private:Statement = [System.String]::Empty
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Int32]$Private:Timeout = 0
  [PSCustomObject]$Private:Result = $Null

  $Database = Get-SusdbConnection -Context:$Context
  $Timeout = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0)
  $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
  $Permission = Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'Permission' -Default:$Null
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Selected', 'Reorganized', 'Rebuilt', 'Failed', 'PagesBefore', 'PagesAfter', 'PagesFreed', 'StatisticsUpdated')) {
    $Counts[$Name] = [System.Int64]0
  }

  # Selection thresholds and actions follow the re-index script Microsoft publishes for SUSDB:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/reindex-the-wsus-database
  $Indexes = @(Invoke-SusdbCommand -CommandText:$SelectionQuery -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout)
  $Counts['Selected'] = [System.Int64]$Indexes.Count
  $Started = Get-MaintenanceTime

  For ($Position = 1; $Position -le $Indexes.Count; $Position++) {
    $Index = $Indexes[$Position - 1]
    $Action = Get-SusdbIndexAction -Density:([System.Double]$Index.Density) -FillFactor:([System.Int32]$Index.FillFactor) -Fragmentation:([System.Double]$Index.Fragmentation) -RecordCount:([System.Int64]$Index.RecordCount)
    $Description = $Script:Message['Invoke-SusdbIndexMaintenance.Item'] -f $Index.IndexName, $Index.TableName, $Script:Message[('Invoke-SusdbIndexMaintenance.{0}' -f $Action)], ([System.Double]$Index.Fragmentation).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), ([System.Double]$Index.Density).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
    $Counts['PagesBefore'] = $Counts['PagesBefore'] + [System.Int64]$Index.UsedPages

    If ($Context.DryRun -eq $True) {
      $Items.Add($Description)
      Continue
    }

    If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
      $Stopped = $True
      Break
    }

    Switch ($Action) {
      'Reorganize' { $Statement = 'ALTER INDEX {0} ON {1} REORGANIZE' -f $Index.IndexName, $Index.TableName }
      'RebuildWithFillFactor' { $Statement = 'ALTER INDEX {0} ON {1} REBUILD WITH (FILLFACTOR = 90)' -f $Index.IndexName, $Index.TableName }
      Default { $Statement = 'ALTER INDEX {0} ON {1} REBUILD' -f $Index.IndexName, $Index.TableName }
    }

    Try {
      $Null = Invoke-SusdbCommand -CommandText:$Statement -Connection:$Database -Log:$Context.Log -NonQuery -TimeoutSeconds:$Timeout
      If ($Action -eq 'Reorganize') {
        $Counts['Reorganized'] = $Counts['Reorganized'] + 1
      } Else {
        $Counts['Rebuilt'] = $Counts['Rebuilt'] + 1
      }

      $Items.Add($Description)
    } Catch {
      $Counts['Failed'] = $Counts['Failed'] + 1
      $Items.Add(($Script:Message['Invoke-SusdbIndexMaintenance.FailedItem'] -f $Description, $PSItem.Exception.Message))
      Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-SusdbIndexMaintenance.FailedItem'] -f $Description, $PSItem.Exception.Message) -Stage:'Reindex'
    }

    Write-MaintenanceProgress -BatchSize:$BatchSize -Item:$Description -Log:$Context.Log -Position:$Position -Stage:'Reindex' -StartedAt:$Started -Total:$Indexes.Count
  }

  If (($Context.DryRun -eq $False) -and ($Indexes.Count -gt 0)) {
    $After = @{}
    ForEach ($Row In @(Invoke-SusdbCommand -CommandText:$PagesQuery -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout)) {
      $After[('{0}:{1}' -f $Row.ObjectId, $Row.IndexId)] = [System.Int64]$Row.UsedPages
    }

    ForEach ($Index In $Indexes) {
      $Key = '{0}:{1}' -f $Index.ObjectId, $Index.IndexId
      If ($After.ContainsKey($Key) -eq $True) {
        $Counts['PagesAfter'] = $Counts['PagesAfter'] + $After[$Key]
      } Else {
        $Counts['PagesAfter'] = $Counts['PagesAfter'] + [System.Int64]$Index.UsedPages
      }
    }

    $Counts['PagesFreed'] = $Counts['PagesBefore'] - $Counts['PagesAfter']
  }

  If ($Counts['Failed'] -gt 0) {
    $Status = 'Error'
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-SusdbIndexMaintenance.FailedNotice'] -f $Counts['Failed']) -Severity:'Error' -Stage:'Reindex'))
  } ElseIf ($Stopped -eq $True) {
    $Status = 'Warning'
    $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Invoke-SusdbIndexMaintenance.Budget'] -Severity:'Warning' -Stage:'Reindex'))
  } ElseIf ($Context.DryRun -eq $False) {
    If (([System.Boolean](Get-MaintenancePropertyValue -InputObject:$Permission -Name:'Checked' -Default:$False) -eq $True) -and ([System.Boolean](Get-MaintenancePropertyValue -InputObject:$Permission -Name:'OwnerOrSysadmin' -Default:$True) -eq $False)) {
      $Status = 'Warning'
      $Login = [System.String](Get-MaintenancePropertyValue -InputObject:$Permission -Name:'LoginName' -Default:'')
      $Notices.Add((New-MaintenanceNotice -Command:($Script:Message['Invoke-SusdbIndexMaintenance.OwnerCommand'] -f (ConvertTo-SqlIdentifier -Name:$Context.Server.Environment.DatabaseName), (ConvertTo-SqlIdentifier -Name:$Login)) -Message:($Script:Message['Invoke-SusdbIndexMaintenance.NotOwner'] -f $Login) -Severity:'Warning' -Stage:'Reindex'))
    } Else {
      Try {
        $Null = Invoke-SusdbCommand -CommandText:'EXEC sp_updatestats' -Connection:$Database -Log:$Context.Log -NonQuery -TimeoutSeconds:$Timeout
        $Counts['StatisticsUpdated'] = 1
      } Catch {
        $Status = 'Error'
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-SusdbIndexMaintenance.StatisticsFailed'] -f $PSItem.Exception.Message) -Severity:'Error' -Stage:'Reindex'))
      }
    }
  }

  If ($Context.DryRun -eq $True) {
    $Summary = $Script:Message['Invoke-SusdbIndexMaintenance.DrySummary'] -f $Indexes.Count
  } Else {
    $Summary = $Script:Message['Invoke-SusdbIndexMaintenance.Summary'] -f $Counts['Reorganized'], $Counts['Rebuilt'], $Counts['Failed'], $Counts['PagesFreed'], $(If ($Counts['StatisticsUpdated'] -eq 1) { $Script:Message['Invoke-SusdbIndexMaintenance.StatisticsDone'] } Else { $Script:Message['Invoke-SusdbIndexMaintenance.StatisticsSkipped'] })
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:$Items.ToArray() -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Invoke-SusdbIndexMaintenance] Exiting'
}
