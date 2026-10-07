#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Set-SusdbCustomIndex.Absent'     = '{0}: absent'
  'Set-SusdbCustomIndex.Created'    = '{0}: created'
  'Set-SusdbCustomIndex.DrySummary' = 'Would create {0} and remove {1} index(es); {2} already present.'
  'Set-SusdbCustomIndex.Failed'     = '{0}: failed: {1}'
  'Set-SusdbCustomIndex.Label'      = '{0} on dbo.{1}'
  'Set-SusdbCustomIndex.NoTable'    = 'the table dbo.{0} does not exist'
  'Set-SusdbCustomIndex.NotOurs'    = '{0}: kept, not created by this script'
  'Set-SusdbCustomIndex.Present'    = '{0}: already present'
  'Set-SusdbCustomIndex.Removed'    = '{0}: removed'
  'Set-SusdbCustomIndex.Summary'    = 'Created {0} and removed {1} index(es); {2} already present; {3} failed.'
  'Set-SusdbCustomIndex.Warning'    = 'Custom index {0} could not be processed: {1}'
}

Function Set-SusdbCustomIndex {
  <#
    .SYNOPSIS
        Ensures the non-clustered SUSDB indexes Microsoft recommends exist.

    .DESCRIPTION
        Checks, on every run, each index Microsoft publishes for faster cleanup (nclLocalizedPropertyID
        on dbo.tbLocalizedPropertyForRevision and nclSupercededUpdateID on dbo.tbRevisionSupersedesUpdate)
        and each index in customIndexes.additional. A missing index is created and tagged with the
        extended property CreatedBy = Invoke-WsusMaintenance in one transaction, so an interrupted run
        leaves either both or neither; an existing index is left untouched and
        reported as already present. With the removal action (-RemoveCustomIndexes) the stage instead
        drops only the indexes that carry the tag, so indexes it did not create are never touched. A
        failure (for example a missing permission or a lock time-out) is a warning and does not stop
        other stages. A dry run changes nothing and reports what it would do.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Set-SusdbCustomIndex -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#set-susdbcustomindex',
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

  Write-Debug -Message:'[Set-SusdbCustomIndex] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Columns = [System.String]::Empty
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.String]$Private:CreateCommand = @(
    'SET XACT_ABORT ON;',
    'BEGIN TRANSACTION;',
    'CREATE NONCLUSTERED INDEX {0} ({1});',
    'EXEC sys.sp_addextendedproperty @name = @property, @value = @value, @level0type = N''SCHEMA'', @level0name = N''dbo'', @level1type = N''TABLE'', @level1name = @table, @level2type = N''INDEX'', @level2name = @name;',
    'COMMIT TRANSACTION;'
  ) -join [System.Environment]::NewLine
  [System.Object]$Private:Database = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Definitions = $Null
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.String]$Private:Label = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String]$Private:PropertyName = 'CreatedBy'
  [System.String]$Private:PropertyValue = 'Invoke-WsusMaintenance'
  [System.Boolean]$Private:Remove = $False
  [System.Object]$Private:State = $Null
  [System.String]$Private:StateQuery = @(
    'SELECT',
    '  CASE WHEN t.object_id IS NULL THEN 0 ELSE 1 END AS TableExists,',
    '  CASE WHEN i.index_id IS NULL THEN 0 ELSE 1 END AS IndexExists,',
    '  CASE WHEN ep.value IS NULL THEN 0 ELSE 1 END AS CreatedByScript',
    'FROM (SELECT OBJECT_ID(@table) AS object_id) AS t',
    'LEFT JOIN sys.indexes AS i ON i.object_id = t.object_id AND i.name = @name',
    'LEFT JOIN sys.extended_properties AS ep ON ep.class = 7 AND ep.major_id = i.object_id AND ep.minor_id = i.index_id',
    '  AND ep.name = @property AND CAST(ep.value AS NVARCHAR(128)) = @value'
  ) -join [System.Environment]::NewLine
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Object]$Private:Target = $Null
  [System.Int32]$Private:Timeout = 0
  [PSCustomObject]$Private:Result = $Null

  $Database = Get-SusdbConnection -Context:$Context
  $Timeout = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0)
  $Remove = [System.Boolean](Get-MaintenancePropertyValue -InputObject:$Context -Name:'RemoveCustomIndexes' -Default:$False)
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Created', 'Present', 'Removed', 'Kept', 'Failed')) {
    $Counts[$Name] = 0
  }

  # The two index definitions are the ones Microsoft publishes for faster cleanup:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide
  $Definitions = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Definitions.Add([PSCustomObject]@{ name = 'nclLocalizedPropertyID'; table = 'tbLocalizedPropertyForRevision'; columns = @('LocalizedPropertyID') })
  $Definitions.Add([PSCustomObject]@{ name = 'nclSupercededUpdateID'; table = 'tbRevisionSupersedesUpdate'; columns = @('SupersededUpdateID') })
  ForEach ($Additional In @($Context.Configuration.customIndexes.additional)) {
    If ($Null -ne $Additional) {
      $Definitions.Add($Additional)
    }
  }

  ForEach ($Definition In $Definitions) {
    $Label = $Script:Message['Set-SusdbCustomIndex.Label'] -f $Definition.name, $Definition.table
    Try {
      $State = @(Invoke-SusdbCommand -CommandText:$StateQuery -Connection:$Database -Log:$Context.Log -Parameter:@{ table = ('dbo.{0}' -f $Definition.table); name = [System.String]$Definition.name; property = $PropertyName; value = $PropertyValue } -TimeoutSeconds:$Timeout) | Select-Object -First:1
      If ($State.TableExists -ne 1) {
        Throw ($Script:Message['Set-SusdbCustomIndex.NoTable'] -f $Definition.table)
      }

      $Target = '{0} ON {1}.{2}' -f (ConvertTo-SqlIdentifier -Name:$Definition.name), (ConvertTo-SqlIdentifier -Name:'dbo'), (ConvertTo-SqlIdentifier -Name:$Definition.table)
      If ($Remove -eq $True) {
        If (($State.IndexExists -eq 1) -and ($State.CreatedByScript -eq 1)) {
          If ($Context.DryRun -eq $False) {
            $Null = Invoke-SusdbCommand -CommandText:('DROP INDEX {0}' -f $Target) -Connection:$Database -Log:$Context.Log -NonQuery -TimeoutSeconds:$Timeout
          }

          $Counts['Removed'] = $Counts['Removed'] + 1
          $Items.Add(($Script:Message['Set-SusdbCustomIndex.Removed'] -f $Label))
        } ElseIf ($State.IndexExists -eq 1) {
          $Counts['Kept'] = $Counts['Kept'] + 1
          $Items.Add(($Script:Message['Set-SusdbCustomIndex.NotOurs'] -f $Label))
        } Else {
          $Items.Add(($Script:Message['Set-SusdbCustomIndex.Absent'] -f $Label))
        }
      } ElseIf ($State.IndexExists -eq 1) {
        $Counts['Present'] = $Counts['Present'] + 1
        $Items.Add(($Script:Message['Set-SusdbCustomIndex.Present'] -f $Label))
      } Else {
        If ($Context.DryRun -eq $False) {
          $Columns = @(@($Definition.columns) | ForEach-Object -Process:({ '{0} ASC' -f (ConvertTo-SqlIdentifier -Name:([System.String]$PSItem)) })) -join ', '
          # The index and its tag are created in one transaction that any error rolls back, so an
          #   interrupted run never leaves an untagged index that the removal action could not
          #   recognise: https://learn.microsoft.com/sql/t-sql/statements/set-xact-abort-transact-sql
          $Null = Invoke-SusdbCommand -CommandText:($CreateCommand -f $Target, $Columns) -Connection:$Database -Log:$Context.Log -NonQuery -Parameter:@{ property = $PropertyName; value = $PropertyValue; table = [System.String]$Definition.table; name = [System.String]$Definition.name } -TimeoutSeconds:$Timeout
        }

        $Counts['Created'] = $Counts['Created'] + 1
        $Items.Add(($Script:Message['Set-SusdbCustomIndex.Created'] -f $Label))
      }
    } Catch {
      $Counts['Failed'] = $Counts['Failed'] + 1
      $Items.Add(($Script:Message['Set-SusdbCustomIndex.Failed'] -f $Label, $PSItem.Exception.Message))
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Set-SusdbCustomIndex.Warning'] -f $Label, $PSItem.Exception.Message) -Severity:'Warning' -Stage:'CustomIndexes'))
    }
  }

  If ($Counts['Failed'] -gt 0) {
    $Status = 'Warning'
  }

  If ($Context.DryRun -eq $True) {
    $Summary = $Script:Message['Set-SusdbCustomIndex.DrySummary'] -f $Counts['Created'], $Counts['Removed'], $Counts['Present']
  } Else {
    $Summary = $Script:Message['Set-SusdbCustomIndex.Summary'] -f $Counts['Created'], $Counts['Removed'], $Counts['Present'], $Counts['Failed']
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:$Items.ToArray() -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Set-SusdbCustomIndex] Exiting'
}
