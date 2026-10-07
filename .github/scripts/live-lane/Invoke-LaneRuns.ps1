#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Runs the installed script as SYSTEM and checks each run.

  .DESCRIPTION
      Each run is started by a scheduled task as SYSTEM (LiveLane.Common.ps1), as the deployment
      runs it, and judged by the exit code Task Scheduler records, the JSON summary, the events and
      the state of SUSDB and the file system:

      1. -ValidateOnly: exit code 0.
      2. A dry run: no stage in error, and nothing written to SUSDB (no custom index) or to the
         backup folder.
      3. A live run: the custom indexes created and tagged, the spDeleteUpdate fix applied or found,
         a backup written into a backup folder the script created protected for the SQL Server
         service, the run-started and run-completed events.
      4. A second live run: nothing new to do (the backup of the day is replaced; every other
         change counter is zero), and still one backup file for the day.
      4a. A run of the custom-index stage alone: with no backup in the run, the backup gate must
         find the earlier backup in msdb.dbo.backupset, which SYSTEM must be able to read.
      5. A report folder that standard users can change: exit code 3 at the data folder protection
         check, with nothing written to it.
      6. The script started from a folder that standard users can change: exit code 3 at the
         installation protection check.

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
Write-LaneNote -Text '## Runs as SYSTEM'

# 1. Validation only.
$Run = Invoke-LaneTask -Argument @('-ValidateOnly')
Write-LaneNote -Text ''
Write-LaneNote -Text '### -ValidateOnly'
Assert-LaneCondition -Condition ($Run.ExitCode -eq 0) -Message ('-ValidateOnly exits 0 (exit code {0})' -f $Run.ExitCode)

# 2. Dry run.
$Run = Invoke-LaneTask -Argument @('-DryRun')
Assert-LaneRun -Run $Run -Label 'Dry run'
Assert-LaneCondition -Condition ($Run.Summary.dryRun -eq $True) -Message 'the summary records a dry run'
Assert-LaneCondition -Condition (@(Invoke-LaneSql -Database 'SUSDB' -Query $IndexQuery).Count -eq 0) -Message 'the dry run created no custom index'
Assert-LaneCondition -Condition (@(Get-ChildItem -LiteralPath $BackupPath -Filter '*.bak' -File -ErrorAction SilentlyContinue).Count -eq 0) -Message 'the dry run wrote no backup'
$Events = Get-LaneEventId -Since $Run.StartedAt
Assert-LaneCondition -Condition (($Events.Count -eq 2) -and ($Events[0] -eq 1000) -and (@(1001, 1002) -contains $Events[1])) -Message ('the dry run wrote the run-started and run-completed events ({0})' -f ($Events -join ', '))

# 3. First live run.
$Run = Invoke-LaneTask
Assert-LaneRun -Run $Run -Label 'First live run'
$Skipped = @($Run.Summary.stages | Where-Object -FilterScript { ([System.String]$PSItem.reason -like 'skipped: missing permission*') -or ([System.String]$PSItem.reason -like 'unavailable*') -or ([System.String]$PSItem.reason -eq 'skipped: no recent backup') } | ForEach-Object -Process { '{0} ({1})' -f $PSItem.name, $PSItem.reason })
Assert-LaneCondition -Condition ($Skipped.Count -eq 0) -Message ('no stage was skipped for a missing permission, a missing component or the backup gate{0}' -f $(If ($Skipped.Count -gt 0) { ': ' + ($Skipped -join '; ') } Else { '' }))
$History = Get-LaneStage -Summary $Run.Summary -Name 'SyncHistory'
Assert-LaneCondition -Condition ([System.String]$History.status -eq 'Success') -Message ('the sync-history stage found the TimeAtServer column ({0}: {1})' -f $History.status, $History.message)
$Indexes = Get-LaneStage -Summary $Run.Summary -Name 'CustomIndexes'
Assert-LaneCondition -Condition (([System.Int32]$Indexes.counts.Created + [System.Int32]$Indexes.counts.Present) -eq 2) -Message ('both custom indexes exist after the first live run (created {0}, present {1})' -f $Indexes.counts.Created, $Indexes.counts.Present)
$Tags = @(Invoke-LaneSql -Database 'SUSDB' -Query $IndexQuery)
Assert-LaneCondition -Condition (($Tags.Count -eq 2) -and (@($Tags | Where-Object -FilterScript { $PSItem.CreatedBy -ne 'Invoke-WsusMaintenance' }).Count -eq 0)) -Message 'both custom indexes carry the CreatedBy tag'
$Fix = Get-LaneStage -Summary $Run.Summary -Name 'DeleteUpdateFix'
Assert-LaneCondition -Condition (([System.Int32]$Fix.counts.Applied + [System.Int32]$Fix.counts.AlreadyApplied) -eq 1) -Message ('the spDeleteUpdate fix is applied or found (applied {0}, already applied {1}): {2}' -f $Fix.counts.Applied, $Fix.counts.AlreadyApplied, $Fix.message)
$Backup = Get-LaneStage -Summary $Run.Summary -Name 'Backup'
Assert-LaneCondition -Condition ([System.Int32]$Backup.counts.Created -eq 1) -Message ('the first live run wrote a backup: {0}' -f $Backup.message)
$Acl = Get-Acl -LiteralPath $BackupPath
$Identities = @($Acl.Access | ForEach-Object -Process { [System.String]$PSItem.IdentityReference })
Assert-LaneCondition -Condition ($Acl.AreAccessRulesProtected -eq $True) -Message ('the backup folder the script created does not inherit permissions ({0})' -f ($Identities -join ', '))
Assert-LaneCondition -Condition ($Identities -contains ('NT SERVICE\MSSQL${0}' -f $env:SQL_INSTANCE)) -Message 'the backup folder grants the SQL Server service account'
Assert-LaneCondition -Condition (@($Identities | Where-Object -FilterScript { $PSItem -match 'Users' }).Count -eq 0) -Message 'the backup folder grants nothing to Users or Authenticated Users'
$Events = Get-LaneEventId -Since $Run.StartedAt
Assert-LaneCondition -Condition (($Events.Count -ge 2) -and ($Events[0] -eq 1000) -and (@(1001, 1002) -contains $Events[-1])) -Message ('the first live run wrote the run-started and run-completed events ({0})' -f ($Events -join ', '))
$Permissions = Get-Content -LiteralPath (Get-LaneLog -Since $Run.StartedAt).FullName | Where-Object -FilterScript { $PSItem -match 'Database permissions:|Dependencies:|Server role:|Environment:' }
ForEach ($Line In $Permissions) {
  Write-LaneNote -Text ('  - log: {0}' -f ($Line -replace '^\S+\s+\S+\s+\[[^\]]+\]\s+', ''))
}

# 4. Second live run: nothing new.
$Run = Invoke-LaneTask
Assert-LaneRun -Run $Run -Label 'Second live run'
$Unchanged = [ordered]@{
  CustomIndexes     = @('Created', 'Removed')
  DeleteUpdateFix   = @('Applied')
  SupersededDecline = @('Declined')
  ExpiredDecline    = @('Declined')
  ObsoleteUpdates   = @('Deleted')
  BuiltInCleanup    = @('SupersededUpdatesDeclined', 'ExpiredUpdatesDeclined', 'ObsoleteUpdatesDeleted', 'UpdatesCompressed', 'ObsoleteComputersDeleted', 'DiskSpaceFreed')
  SyncHistory       = @('Removed')
  StaleComputers    = @('Deleted', 'Moved')
  Reindex           = @('Rebuilt', 'Reorganized')
  IisLogRetention   = @('Deleted')
}
ForEach ($StageName In $Unchanged.Keys) {
  $Stage = Get-LaneStage -Summary $Run.Summary -Name $StageName
  $Changed = @(ForEach ($Counter In $Unchanged[$StageName]) {
      If (($Null -ne $Stage.counts.PSObject.Properties[$Counter]) -and ([System.Double]$Stage.counts.$Counter -ne 0)) {
        '{0} {1}' -f $Counter, $Stage.counts.$Counter
      }
    })
  Assert-LaneCondition -Condition ($Changed.Count -eq 0) -Message ('the second live run found nothing new for {0} ({1}): {2}' -f $StageName, $Stage.status, $Stage.message)
}

$Today = @(Get-ChildItem -LiteralPath $BackupPath -Filter ('SUSDB_{0}.bak' -f (Get-Date).ToString('yyyyMMdd')) -File)
Assert-LaneCondition -Condition ((@(Get-ChildItem -LiteralPath $BackupPath -Filter '*.bak' -File).Count -eq 1) -and ($Today.Count -eq 1)) -Message 'two live runs on one day leave one backup file for that day'

# 4a. The backup gate from msdb.
$Run = Invoke-LaneTask -Argument @('-Stage', 'CustomIndexes')
Assert-LaneRun -Run $Run -Label 'Custom indexes alone (backup gate from msdb)'
$Indexes = Get-LaneStage -Summary $Run.Summary -Name 'CustomIndexes'
Assert-LaneCondition -Condition ([System.String]$Indexes.status -ne 'Skipped') -Message ('the backup gate found the earlier backup in msdb ({0}: {1})' -f $Indexes.status, $Indexes.reason)

# 5. A report folder that standard users can change.
$OpenRoot = Join-Path -Path $env:SystemDrive -ChildPath 'LiveLaneOpen'
$OpenReports = Join-Path -Path $OpenRoot -ChildPath 'Reports'
$Null = New-Item -ItemType Directory -Path $OpenReports -Force
Write-LaneNote -Text ''
Write-LaneNote -Text ('Access control list of {0}: {1}' -f $OpenReports, (@((Get-Acl -LiteralPath $OpenReports).Access | ForEach-Object -Process { '{0} {1} {2}' -f $PSItem.IdentityReference, $PSItem.AccessControlType, $PSItem.FileSystemRights }) -join '; '))
$Run = Invoke-LaneTask -Argument @('-ReportFolder', ('"{0}"' -f $OpenReports))
Assert-LaneRun -Run $Run -Label 'Report folder that standard users can change' -ExpectedExitCode @(3)
Assert-LaneCondition -Condition ([System.String]$Run.Summary.failure.point -eq 'data folder protection check') -Message ('the run stopped at the data folder protection check: {0}' -f $Run.Summary.failure.message)
Assert-LaneCondition -Condition (@(Get-ChildItem -LiteralPath $OpenReports -Force).Count -eq 0) -Message 'nothing was written to the refused folder'
Assert-LaneCondition -Condition ((Get-LaneEventId -Since $Run.StartedAt) -contains 1200) -Message 'the precondition-failure event was written'

# 6. The script started from a folder that standard users can change.
$OpenScript = Join-Path -Path $OpenRoot -ChildPath 'Invoke-WsusMaintenance.ps1'
Copy-Item -LiteralPath $Script:LaneScriptPath -Destination $OpenScript -Force
$Run = Invoke-LaneTask -ScriptPath $OpenScript
Assert-LaneRun -Run $Run -Label 'Script in a folder that standard users can change' -ExpectedExitCode @(3)
Assert-LaneCondition -Condition ([System.String]$Run.Summary.failure.point -eq 'installation protection check') -Message ('the run stopped at the installation protection check: {0}' -f $Run.Summary.failure.message)
Remove-Item -LiteralPath $OpenRoot -Recurse -Force
