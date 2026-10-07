#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Terminates live runs part-way and checks that the next run finishes the work (REQ-096).

  .DESCRIPTION
      1. Removes the custom indexes with the script's own removal action (after a backup in the same
         run, which keeps the backup gate open), so that the next run has to create them again.
      2. Starts live runs and terminates each as soon as its run log shows that a chosen stage
         has started (Stop-ScheduledTask stops all running instances of the task at once,
         https://learn.microsoft.com/powershell/module/scheduledtasks/stop-scheduledtask), the
         first one inside the custom-index stage. After each termination each custom index exists
         with its CreatedBy tag or not at all, never untagged.
      3. Runs once more without interruption: it must succeed (the system-wide lock left by a
         terminated run is abandoned and taken over), recreate whatever is missing, and leave
         SUSDB consistent: DBCC CHECKDB reports no error
         (https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql),
         and a backup terminated part-way leaves one backup file for the day after the next run.

  .PARAMETER BackupPath
      Backup destination of the configuration document.
#>
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $True)][System.String]$BackupPath
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'LiveLane.Common.ps1')

$IndexQuery = @"
SELECT i.name AS IndexName, CAST(ep.value AS NVARCHAR(128)) AS CreatedBy
FROM sys.indexes AS i
LEFT JOIN sys.extended_properties AS ep
  ON ep.class = 7 AND ep.major_id = i.object_id AND ep.minor_id = i.index_id AND ep.name = N'CreatedBy'
WHERE i.name IN (N'nclLocalizedPropertyID', N'nclSupercededUpdateID');
"@

Write-LaneNote -Text ''
Write-LaneNote -Text '## Terminated runs'

$Run = Invoke-LaneTask -Argument @('-Stage', 'Backup,CustomIndexes', '-RemoveCustomIndexes')
Assert-LaneRun -Run $Run -Label 'Removal of the custom indexes'
Assert-LaneCondition -Condition (@(Invoke-LaneSql -Database 'SUSDB' -Query $IndexQuery).Count -eq 0) -Message 'the removal action dropped both custom indexes'

ForEach ($Target In @('CustomIndexes', 'Backup', 'DeleteUpdateFix', 'BuiltInCleanup', 'SyncHistory', 'Reindex', 'HealthChecks')) {
  $Run = Invoke-LaneTask -NoWait
  $Marker = '] {0}: Stage started.' -f $Target
  $Deadline = (Get-Date).AddMinutes(20)
  $Reached = $False
  Do {
    Start-Sleep -Milliseconds 100
    $Log = Get-LaneLog -Since $Run.StartedAt
    If ($Null -ne $Log) {
      $Reached = [System.Boolean](Select-String -LiteralPath $Log.FullName -SimpleMatch -Pattern $Marker -Quiet)
    }

    $State = [System.String](Get-ScheduledTask -TaskName $Script:LaneTaskName).State
  } While (($Reached -eq $False) -and ($State -eq 'Running') -and ((Get-Date) -lt $Deadline))

  If ($State -eq 'Running') {
    Stop-ScheduledTask -TaskName $Script:LaneTaskName
  }

  $LastLine = ''
  If ($Null -ne $Log) {
    $LastLine = [System.String](Get-Content -LiteralPath $Log.FullName -Tail 1)
  }

  Write-LaneNote -Text ('- terminated at {0} (reached: {1}, still running: {2}); last log line: {3}' -f $Target, $Reached, ($State -eq 'Running'), ($LastLine -replace '^\S+\s+\S+\s+\[[^\]]+\]\s+', ''))
  Do {
    Start-Sleep -Milliseconds 500
  } While ([System.String](Get-ScheduledTask -TaskName $Script:LaneTaskName).State -eq 'Running')

  $Untagged = @(Invoke-LaneSql -Database 'SUSDB' -Query $IndexQuery | Where-Object -FilterScript { $PSItem.CreatedBy -ne 'Invoke-WsusMaintenance' })
  Assert-LaneCondition -Condition ($Untagged.Count -eq 0) -Message ('after the termination at {0}, every custom index that exists carries its tag' -f $Target)
}

$Run = Invoke-LaneTask
Assert-LaneRun -Run $Run -Label 'Run after the terminated runs'
$Tags = @(Invoke-LaneSql -Database 'SUSDB' -Query $IndexQuery)
Assert-LaneCondition -Condition (($Tags.Count -eq 2) -and (@($Tags | Where-Object -FilterScript { $PSItem.CreatedBy -ne 'Invoke-WsusMaintenance' }).Count -eq 0)) -Message 'both custom indexes exist with their tag after the next run'
$Null = Invoke-LaneSql -Database 'master' -Query "DBCC CHECKDB (N'SUSDB') WITH NO_INFOMSGS, ALL_ERRORMSGS;"
Assert-LaneCondition -Condition $True -Message 'DBCC CHECKDB reports no error in SUSDB'
$Today = @(Get-ChildItem -LiteralPath $BackupPath -Filter ('SUSDB_{0}.bak' -f (Get-Date).ToString('yyyyMMdd')) -File)
Assert-LaneCondition -Condition ((@(Get-ChildItem -LiteralPath $BackupPath -Filter '*.bak' -File).Count -eq 1) -and ($Today.Count -eq 1)) -Message 'the terminated and repeated runs leave one backup file for the day'
