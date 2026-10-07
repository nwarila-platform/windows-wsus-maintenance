#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceConfigurationRule {
  <#
    .SYNOPSIS
        Returns the configuration parameter catalogue.

    .DESCRIPTION
        The single source of truth for every configuration key: its dotted path, value
        type, unit, valid range or allowed values, and default. Validation, default
        merging and the published JSON schema are all derived from this table, so the
        three cannot disagree. A key with no default is either required (schemaVersion)
        or deployment-specific and required only when the feature that uses it is
        enabled, which validation enforces as a cross-field rule. A key that names ReplacedBy
        is deprecated: it is still read and validated, and every use is reported with its
        replacement. The defaults are the decided values listed in docs/DESIGN.md section 8.

    .EXAMPLE
        Get-MaintenanceConfigurationRule

    .OUTPUTS
        [System.Management.Automation.PSCustomObject[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenanceconfigurationrule',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject[]])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceConfigurationRule] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ClassificationPattern = [System.String]::Empty
  [System.Object[]]$Private:Definitions = @()
  [System.String]$Private:EventNamePattern = [System.String]::Empty
  [System.String]$Private:HostPattern = [System.String]::Empty
  [System.String]$Private:IdentityPattern = [System.String]::Empty
  [System.String]$Private:PathPattern = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Rules = $Null
  [PSCustomObject[]]$Private:Result = @()
  [System.String]$Private:SitePattern = [System.String]::Empty

  # A Windows path: drive-rooted, UNC, or rooted at one %VARIABLE% that is expanded at run time.
  $PathPattern = '^(?:[A-Za-z]:\\|\\\\[^\\/:*?"<>|]+\\[^\\/:*?"<>|]+|%[A-Za-z_][A-Za-z0-9_()]*%)[^/:*?"<>|]*$'
  # A Knowledge Base number (with or without the KB prefix) or an update GUID.
  $IdentityPattern = '^(?:KB[0-9]{4,8}|[0-9]{4,8}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$'
  $ClassificationPattern = '^\S(?:.{0,254}\S)?$'
  $EventNamePattern = '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,210}$'
  $HostPattern = '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$'
  $SitePattern = '^[^\\/?;:@&=+$,|"<>*\s](?:[^\\/?;:@&=+$,|"<>*]{0,254}[^\\/?;:@&=+$,|"<>*\s])?$'

  $Definitions = @(
    @{ Path = 'schemaVersion'; Type = 'Integer'; Required = $True; Minimum = 1; Maximum = 1; Description = 'Configuration schema version. This release reads version 1 only.' }
    @{ Path = 'configuration.unknownKeyPolicy'; Type = 'String'; Default = 'Error'; AllowedValues = @('Error', 'Warning'); Description = 'Whether a key this release does not know fails validation (Error) or is reported and ignored (Warning).' }

    @{ Path = 'run.dryRun'; Type = 'Boolean'; Default = $False; Description = 'Apply every selection rule and report the intended changes without changing anything.' }
    @{ Path = 'run.maxDurationMinutes'; Type = 'Integer'; Default = 240; Minimum = 0; Maximum = 10080; Unit = 'minutes'; Description = 'Run time budget. No new stage starts once it has elapsed. Zero means unlimited.' }
    @{ Path = 'run.databaseCommandTimeoutSeconds'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 604800; Unit = 'seconds'; Description = 'Client-side timeout for each database command. Zero means no timeout.' }
    @{ Path = 'run.connectionTimeoutSeconds'; Type = 'Integer'; Default = 30; Minimum = 1; Maximum = 600; Unit = 'seconds'; Description = 'Timeout for establishing the WSUS and SUSDB connections.' }
    @{ Path = 'run.progressBatchSize'; Type = 'Integer'; Default = 1; Minimum = 1; Maximum = 100000; Unit = 'items'; Description = 'Item-by-item stages log one progress entry per this many items.' }
    @{ Path = 'run.permissiveFolderOverride'; Type = 'Boolean'; Default = $False; Description = 'Allow an existing data folder whose access control grants write access to principals other than SYSTEM, Administrators and the run identity.' }

    @{ Path = 'discovery.sqlInstance'; Type = 'String'; Nullable = $True; Default = $Null; Pattern = '^[A-Za-z0-9._-]{1,253}(?:\\[A-Za-z_][A-Za-z0-9_$#]{0,15})?$'; Description = 'SQL Server instance hosting SUSDB (HOST or HOST\INSTANCE). Null means the instance WSUS setup recorded. It must be on this server.' }
    @{ Path = 'discovery.databaseName'; Type = 'String'; Nullable = $True; Default = $Null; Pattern = '^[A-Za-z_][A-Za-z0-9_]{0,127}$'; Description = 'SUSDB database name. Null means the name WSUS setup recorded.' }
    @{ Path = 'discovery.wsusPort'; Type = 'Integer'; Nullable = $True; Default = $Null; Minimum = 1; Maximum = 65535; Description = 'Port of the WSUS administration interface. Null means the local server''s own setting; with a host name or TLS set, 8531 with TLS and 8530 without.' }
    @{ Path = 'discovery.wsusUseTls'; Type = 'Boolean'; Nullable = $True; Default = $Null; Description = 'Whether to reach the WSUS administration interface over TLS. Null means the local server''s own setting.' }
    @{ Path = 'discovery.wsusHostName'; Type = 'String'; Nullable = $True; Default = $Null; Pattern = $HostPattern; Description = 'Host name of the WSUS administration interface, which with TLS must match its certificate. Null means the local WSUS server.' }

    @{ Path = 'syncGuard.pollIntervalSeconds'; Type = 'Integer'; Default = 10; Minimum = 1; Maximum = 3600; Unit = 'seconds'; Description = 'Interval between synchronization status checks while waiting for a stop.' }
    @{ Path = 'syncGuard.waitSeconds'; Type = 'Integer'; Default = 600; Minimum = 1; Maximum = 86400; Unit = 'seconds'; Description = 'How long one stop attempt waits for the synchronization to reach a not-processing state.' }
    @{ Path = 'syncGuard.retryDelaySeconds'; Type = 'Integer'; Default = 60; Minimum = 0; Maximum = 86400; Unit = 'seconds'; Description = 'Delay between stop attempts.' }
    @{ Path = 'syncGuard.maxAttempts'; Type = 'Integer'; Default = 3; Minimum = 1; Maximum = 100; Description = 'Stop attempts before the run aborts with the precondition-failure code.' }
    @{ Path = 'syncGuard.suspendSchedule'; Type = 'Boolean'; Default = $False; Description = 'Suspend the automatic synchronization schedule for the duration of the run.' }

    @{ Path = 'backup.enabled'; Type = 'Boolean'; Default = $True; Description = 'Create a full SUSDB backup with checksum verification.' }
    @{ Path = 'backup.destination'; Type = 'Path'; Pattern = $PathPattern; Nullable = $True; Default = $Null; Description = 'Folder for backup files, resolved on the database host. Required when backup is enabled.' }
    @{ Path = 'backup.sameDay'; Type = 'String'; Default = 'Replace'; AllowedValues = @('Replace', 'Append'); Description = 'Whether a second backup on the same day replaces or appends to that day''s file.' }
    @{ Path = 'backup.compression'; Type = 'String'; Default = 'Auto'; AllowedValues = @('Auto', 'Always', 'Never'); Description = 'Backup compression: when the engine supports it (Auto), always, or never.' }
    @{ Path = 'backup.minimumKept'; Type = 'Integer'; Default = 7; Minimum = 0; Maximum = 1000; Unit = 'files'; Description = 'Most recent backup files always kept. Zero means no minimum; with both limits zero every file is kept.' }
    @{ Path = 'backup.maximumAgeDays'; Type = 'Integer'; Default = 7; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Backup files this many days old or older, by the date in their name, and outside the most recent set are deleted. Zero means no age limit.' }
    @{ Path = 'backup.freeSpaceMarginPercent'; Type = 'Integer'; Default = 20; Minimum = 0; Maximum = 1000; Unit = 'percent'; Description = 'Free space required on the destination beyond the estimated backup size.' }
    @{ Path = 'backup.gate'; Type = 'String'; Default = 'Required'; AllowedValues = @('Required', 'Advisory', 'Off'); Description = 'Whether stages that delete or alter SUSDB content require a recent successful backup.' }
    @{ Path = 'backup.freshnessHours'; Type = 'Integer'; Default = 24; Minimum = 1; Maximum = 8760; Unit = 'hours'; Description = 'How recent a backup must be to satisfy the backup gate.' }

    @{ Path = 'builtInCleanup.declineSupersededUpdates'; Type = 'Boolean'; Default = $True; Description = 'Run the built-in superseded-update decline. Suppressed automatically on a replica.' }
    @{ Path = 'builtInCleanup.declineExpiredUpdates'; Type = 'Boolean'; Default = $True; Description = 'Run the built-in expired-update decline. Suppressed automatically on a replica.' }
    @{ Path = 'builtInCleanup.obsoleteUpdates'; Type = 'Boolean'; Default = $True; Description = 'Run the built-in obsolete-update deletion.' }
    @{ Path = 'builtInCleanup.compressUpdates'; Type = 'Boolean'; Default = $True; Description = 'Remove obsolete update revisions.' }
    @{ Path = 'builtInCleanup.obsoleteComputers'; Type = 'Boolean'; Default = $False; Description = 'Run the built-in obsolete-computer deletion (fixed threshold). The stale-computer stage is the configurable alternative.' }
    @{ Path = 'builtInCleanup.unneededContentFiles'; Type = 'Boolean'; Default = $True; Description = 'Delete unneeded content files. Also removes files imported manually from the Microsoft Update Catalog.' }
    @{ Path = 'builtInCleanup.timeoutRetries'; Type = 'Integer'; Default = 2; Minimum = 0; Maximum = 10; Description = 'Retries after a built-in cleanup time-out.' }

    @{ Path = 'obsoleteUpdates.enabled'; Type = 'Boolean'; Default = $True; Description = 'Delete obsolete updates one at a time with the SUSDB procedures.' }
    @{ Path = 'obsoleteUpdates.maxDeletions'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 10000000; Unit = 'updates'; Description = 'Per-run cap on obsolete-update deletions. Zero means no cap.' }

    @{ Path = 'customIndexes.enabled'; Type = 'Boolean'; Default = $True; Description = 'Ensure the non-clustered SUSDB indexes Microsoft recommends exist.' }
    @{ Path = 'customIndexes.additional'; Type = 'IndexArray'; Default = @(); Description = 'Additional non-clustered index definitions (name, table, columns).' }

    @{ Path = 'deleteUpdateFix.enabled'; Type = 'Boolean'; Default = $True; Description = 'Check for, and apply when absent, the published fix for slow spDeleteUpdate.' }

    @{ Path = 'reindex.enabled'; Type = 'Boolean'; Default = $True; Description = 'Defragment fragmented SUSDB indexes, then update statistics.' }

    @{ Path = 'syncHistory.enabled'; Type = 'Boolean'; Default = $True; Description = 'Delete synchronization-history records older than the retention.' }
    @{ Path = 'syncHistory.retentionDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Synchronization-history records older than this are deleted. Zero removes all such records.' }

    @{ Path = 'staleComputers.enabled'; Type = 'Boolean'; Default = $True; Description = 'Remove computer records that have not synchronized within the threshold.' }
    @{ Path = 'staleComputers.thresholdDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Days without synchronization before a computer is stale. Zero requires the override.' }
    @{ Path = 'staleComputers.includeDownstream'; Type = 'Boolean'; Default = $False; Description = 'Include computers reported through downstream servers.' }
    @{ Path = 'staleComputers.action'; Type = 'String'; Default = 'Delete'; AllowedValues = @('Delete', 'Move'); Description = 'Delete stale computers or move them into the target group.' }
    @{ Path = 'staleComputers.targetGroup'; Type = 'String'; Nullable = $True; Default = $Null; Pattern = $ClassificationPattern; Description = 'Computer group that receives stale computers. Required when the action is Move.' }
    @{ Path = 'staleComputers.guardCount'; Type = 'Integer'; Default = 50; Minimum = 0; Maximum = 10000000; Unit = 'computers'; Description = 'Change nothing and raise a notice if more computers than this are selected.' }
    @{ Path = 'staleComputers.guardPercent'; Type = 'Integer'; Default = 10; Minimum = 0; Maximum = 100; Unit = 'percent'; Description = 'Change nothing and raise a notice if more than this share of all computers is selected.' }
    @{ Path = 'staleComputers.override'; Type = 'Boolean'; Default = $False; Description = 'Proceed despite a guard breach, and allow a zero-day threshold.' }

    @{ Path = 'declines.arrivalWindowDays'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 36500; Unit = 'days'; Description = 'Only updates that arrived within this many days are evaluated. Zero means unlimited.' }
    @{ Path = 'declines.evaluationLanguage'; Type = 'String'; Default = 'en'; Pattern = '^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$'; Description = 'Language in which titles and category names are retrieved for rule evaluation.' }
    @{ Path = 'declines.neverDecline'; Type = 'StringArray'; Default = @(); Pattern = $IdentityPattern; Unique = $True; Description = 'Updates never declined by any policy, by Knowledge Base number or update GUID.' }
    @{ Path = 'declines.superseded.enabled'; Type = 'Boolean'; Default = $True; Description = 'Decline superseded updates older than the age threshold.' }
    @{ Path = 'declines.superseded.ageDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Superseded updates whose revision is newer than this are kept.' }
    @{ Path = 'declines.superseded.lastLevelOnly'; Type = 'Boolean'; Default = $False; Description = 'Decline only updates that are superseded but supersede nothing themselves.' }
    @{ Path = 'declines.superseded.includeApproved'; Type = 'Boolean'; Default = $True; Description = 'Superseded updates that are currently approved are eligible.' }
    @{ Path = 'declines.accelerated.enabled'; Type = 'Boolean'; Default = $False; Description = 'Apply an additional superseded-update policy to selected classifications.' }
    @{ Path = 'declines.accelerated.classifications'; Type = 'StringArray'; Default = @(); Pattern = $ClassificationPattern; Unique = $True; Description = 'Classification titles the accelerated policy applies to. Required when it is enabled.' }
    @{ Path = 'declines.accelerated.ageDays'; Type = 'Integer'; Nullable = $True; Default = $Null; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Age threshold of the accelerated policy. Required when it is enabled.' }
    @{ Path = 'declines.expired.enabled'; Type = 'Boolean'; Default = $True; Description = 'Decline updates whose publication state is expired.' }
    @{ Path = 'declines.rules'; Type = 'RuleArray'; Default = @(); Description = 'Decline rules defined for the deployment. None ships enabled.' }
    @{ Path = 'declines.groups'; Type = 'GroupArray'; Default = @(); Description = 'Rule groups. Disabling a group disables all of its rules.' }

    @{ Path = 'approval.enabled'; Type = 'Boolean'; Default = $False; Description = 'Approve the updates clients need for each configured computer group after its delay, and stage their content early. Leave off on a server that only synchronizes and serves.' }
    @{ Path = 'approval.groups'; Type = 'ApprovalGroupArray'; Default = @(); Description = 'Computer groups to approve for, each {name, delayDays, deadlineDays?}: days after the revision creation date before approval, and days after approval to the install deadline (none when absent). Required when approval is enabled.' }
    @{ Path = 'approval.staging.enabled'; Type = 'Boolean'; Default = $True; Description = 'Approve needed updates for an empty staging group so that their content downloads before their approval date.' }
    @{ Path = 'approval.staging.groupName'; Type = 'String'; Nullable = $True; Default = $Null; Pattern = $ClassificationPattern; Description = 'Computer group used for content staging. It must exist and stay empty. Required when approval and staging are enabled.' }
    @{ Path = 'approval.neverApprove'; Type = 'StringArray'; Default = @(); Pattern = $IdentityPattern; Unique = $True; Description = 'Updates never approved or staged, by Knowledge Base number or update GUID.' }
    @{ Path = 'approval.excludedClassifications'; Type = 'StringArray'; Default = @(); Pattern = $ClassificationPattern; Unique = $True; Description = 'Classifications never approved or staged, in addition to Upgrades, which is always excluded.' }
    @{ Path = 'approval.acceptLicenseAgreements'; Type = 'Boolean'; Default = $True; Description = 'Accept the licence agreement of an update before approving or staging it; when false, such updates are left unapproved.' }

    @{ Path = 'declinedDeletion.enabled'; Type = 'Boolean'; Default = $False; Description = 'Delete declined updates from WSUS. Recovery requires a re-import or resynchronization.' }
    @{ Path = 'declinedDeletion.protected'; Type = 'StringArray'; Default = @(); Pattern = $IdentityPattern; Unique = $True; Description = 'Declined updates never deleted, by Knowledge Base number or update GUID.' }
    @{ Path = 'declinedDeletion.excludedClassifications'; Type = 'StringArray'; Default = @(); Pattern = $ClassificationPattern; Unique = $True; Description = 'Classifications whose declined updates are never deleted.' }
    @{ Path = 'declinedDeletion.includedClassifications'; Type = 'StringArray'; Default = @(); Pattern = $ClassificationPattern; Unique = $True; Description = 'When not empty, only declined updates in these classifications are deleted.' }

    @{ Path = 'iisLogs.enabled'; Type = 'Boolean'; Default = $True; Description = 'Delete the WSUS website''s IIS log files older than the maximum age.' }
    @{ Path = 'iisLogs.maxAgeDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'IIS log files last modified longer ago than this are deleted. Zero keeps every file.' }
    @{ Path = 'iisLogs.folder'; Type = 'Path'; Pattern = $PathPattern; Nullable = $True; Default = $Null; Description = 'Override for the IIS log folder. Null means detected from the WSUS website.' }
    @{ Path = 'iisLogs.siteName'; Type = 'String'; Nullable = $True; Default = $Null; Pattern = $SitePattern; Description = 'Override for the IIS site that hosts WSUS. Null means detected.' }

    @{ Path = 'retention.logs.maxAgeDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Run logs older than this are deleted. Zero keeps every age.' }
    @{ Path = 'retention.logs.maxCount'; Type = 'Integer'; Default = 200; Minimum = 0; Maximum = 100000; Unit = 'files'; Description = 'At most this many run logs are kept. Zero means no count limit.' }
    @{ Path = 'retention.reports.maxAgeDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Saved reports older than this are deleted. Zero keeps every age.' }
    @{ Path = 'retention.reports.maxCount'; Type = 'Integer'; Default = 200; Minimum = 0; Maximum = 100000; Unit = 'files'; Description = 'At most this many saved reports are kept. Zero means no count limit.' }
    @{ Path = 'retention.summaries.maxAgeDays'; Type = 'Integer'; Default = 90; Minimum = 0; Maximum = 3650; Unit = 'days'; Description = 'Run summaries older than this are deleted. Zero keeps every age.' }
    @{ Path = 'retention.summaries.maxCount'; Type = 'Integer'; Default = 200; Minimum = 0; Maximum = 100000; Unit = 'files'; Description = 'At most this many run summaries are kept. Zero means no count limit.' }

    @{ Path = 'health.tls.enabled'; Type = 'Boolean'; Default = $True; Description = 'Raise a notice when WSUS does not use TLS.' }
    @{ Path = 'health.certificateExpiry.enabled'; Type = 'Boolean'; Default = $True; Description = 'Report days until the certificate bound to the WSUS TLS port expires.' }
    @{ Path = 'health.certificateExpiry.warningDays'; Type = 'IntegerArray'; Default = @(60, 30, 14, 7); Minimum = 1; Maximum = 3650; Unique = $True; NonEmpty = $True; Unit = 'days'; Description = 'Warning tiers, strictly descending.' }
    @{ Path = 'health.strongCrypto.enabled'; Type = 'Boolean'; Default = $True; Description = 'Check the .NET strong-cryptography registry values in both registry views.' }
    @{ Path = 'health.appPool.enabled'; Type = 'Boolean'; Default = $True; Description = 'Compare the WSUS application-pool settings with the expected values.' }
    @{ Path = 'health.appPool.queueLength'; Type = 'Integer'; Default = 2000; Minimum = 10; Maximum = 65535; Description = 'Expected application-pool queue length.' }
    @{ Path = 'health.appPool.idleTimeoutMinutes'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 43200; Unit = 'minutes'; Description = 'Expected idle time-out.' }
    @{ Path = 'health.appPool.pingingEnabled'; Type = 'Boolean'; Default = $False; Description = 'Expected pinging setting.' }
    @{ Path = 'health.appPool.privateMemoryLimitKb'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 2147483647; Unit = 'KB'; Description = 'Expected private memory limit.' }
    @{ Path = 'health.appPool.virtualMemoryLimitKb'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 2147483647; Unit = 'KB'; Description = 'Expected virtual memory limit.' }
    @{ Path = 'health.appPool.regularRecyclingMinutes'; Type = 'Integer'; Default = 0; Minimum = 0; Maximum = 2147483647; Unit = 'minutes'; Description = 'Expected regular recycling interval.' }
    @{ Path = 'health.downloadSettings.enabled'; Type = 'Boolean'; Default = $True; Description = 'Compare the WSUS download settings with the values this deployment expects. They are never changed.' }
    @{ Path = 'health.downloadSettings.expressFiles'; Type = 'Boolean'; Default = $False; Description = 'Expected express installation files setting (DownloadExpressPackages).' }
    @{ Path = 'health.downloadSettings.downloadOnlyWhenApproved'; Type = 'Boolean'; Default = $True; Description = 'Expected download-only-when-approved setting (DownloadUpdateBinariesAsNeeded). A top-tier server that downloads every update it synchronizes expects false.' }
    @{ Path = 'health.downloadSettings.storeFilesLocally'; Type = 'Boolean'; Default = $True; Description = 'Expected local storage of update files (HostBinariesOnMicrosoftUpdate off).' }
    @{ Path = 'health.supersededCount.enabled'; Type = 'Boolean'; Default = $True; Description = 'Count superseded updates that are not declined.' }
    @{ Path = 'health.supersededCount.threshold'; Type = 'Integer'; Default = 1500; Minimum = 0; Maximum = 10000000; Unit = 'updates'; Description = 'Raise a notice above this count.' }
    @{ Path = 'health.processorCount.enabled'; Type = 'Boolean'; Default = $True; Description = 'Check the logical-processor count on a virtual machine.' }
    @{ Path = 'health.processorCount.minimum'; Type = 'Integer'; Default = 4; Minimum = 1; Maximum = 1024; Unit = 'processors'; Description = 'Raise a notice below this count.' }

    @{ Path = 'report.folder'; Type = 'Path'; Pattern = $PathPattern; Default = '%ProgramData%\NWarila\WsusMaintenance\Reports'; Description = 'Folder for saved reports, with timestamped file names.' }
    @{ Path = 'report.formats'; Type = 'StringArray'; Default = @('Text', 'Html'); AllowedValues = @('Text', 'Html'); Unique = $True; NonEmpty = $True; Description = 'Formats saved to the report folder.' }
    @{ Path = 'report.maxItemsPerSection'; Type = 'Integer'; Default = 100; Minimum = 1; Maximum = 100000; Unit = 'items'; Description = 'Items listed per report section; the full list goes to the run log.' }

    @{ Path = 'log.folder'; Type = 'Path'; Pattern = $PathPattern; Default = '%ProgramData%\NWarila\WsusMaintenance\Logs'; Description = 'Folder for run logs.' }
    @{ Path = 'log.verbosity'; Type = 'String'; Default = 'Information'; AllowedValues = @('Error', 'Warning', 'Information', 'Verbose', 'Debug'); Description = 'Lowest level written to the run log.' }

    @{ Path = 'summary.folder'; Type = 'Path'; Pattern = $PathPattern; Default = '%ProgramData%\NWarila\WsusMaintenance\Summaries'; Description = 'Folder for machine-readable run summaries.' }
    @{ Path = 'summary.format'; Type = 'String'; Default = 'Json'; AllowedValues = @('Json'); Description = 'Run summary format.' }

    @{ Path = 'eventLog.enabled'; Type = 'Boolean'; Default = $True; Description = 'Write Windows Event Log entries through the registered event source.' }
    @{ Path = 'eventLog.logName'; Type = 'String'; Default = 'Application'; Pattern = $EventNamePattern; Description = 'Event log the source is registered in.' }
    @{ Path = 'eventLog.source'; Type = 'String'; Default = 'Invoke-WsusMaintenance'; Pattern = $EventNamePattern; Description = 'Event source registered by deployment.' }
    @{ Path = 'eventLog.eventIds.runStarted'; Type = 'Integer'; Default = 1000; Minimum = 1; Maximum = 65535; Description = 'Event identifier for run start.' }
    @{ Path = 'eventLog.eventIds.runSucceeded'; Type = 'Integer'; Default = 1001; Minimum = 1; Maximum = 65535; Description = 'Event identifier for a run that completed successfully.' }
    @{ Path = 'eventLog.eventIds.runWarning'; Type = 'Integer'; Default = 1002; Minimum = 1; Maximum = 65535; Description = 'Event identifier for a run that completed with warnings.' }
    @{ Path = 'eventLog.eventIds.runFailed'; Type = 'Integer'; Default = 1003; Minimum = 1; Maximum = 65535; Description = 'Event identifier for a run that completed with errors.' }
    @{ Path = 'eventLog.eventIds.stageError'; Type = 'Integer'; Default = 1100; Minimum = 1; Maximum = 65535; Description = 'Event identifier for each stage error.' }
    @{ Path = 'eventLog.eventIds.preconditionFailure'; Type = 'Integer'; Default = 1200; Minimum = 1; Maximum = 65535; Description = 'Event identifier for a precondition failure.' }
    @{ Path = 'eventLog.eventIds.configurationInvalid'; Type = 'Integer'; Default = 1300; Minimum = 1; Maximum = 65535; Description = 'Event identifier for an invalid configuration.' }
    @{ Path = 'eventLog.eventIds.lateContent'; Type = 'Integer'; Default = 1400; Minimum = 1; Maximum = 65535; Description = 'Event identifier for approvals made before the update files were local.' }
  )

  $Rules = [System.Collections.Generic.List[PSCustomObject]]::new()
  ForEach ($Definition In $Definitions) {
    $Rules.Add(
      [PSCustomObject]@{
        Path          = [System.String]$Definition['Path']
        Type          = [System.String]$Definition['Type']
        Required      = [System.Boolean]($Definition.ContainsKey('Required') -and $Definition['Required'])
        HasDefault    = [System.Boolean]$Definition.ContainsKey('Default')
        Default       = $Definition['Default']
        Nullable      = [System.Boolean]($Definition.ContainsKey('Nullable') -and $Definition['Nullable'])
        Minimum       = $Definition['Minimum']
        Maximum       = $Definition['Maximum']
        AllowedValues = [System.String[]]@($Definition['AllowedValues'] | Where-Object -FilterScript { $Null -ne $PSItem })
        Pattern       = [System.String]$Definition['Pattern']
        Unique        = [System.Boolean]($Definition.ContainsKey('Unique') -and $Definition['Unique'])
        NonEmpty      = [System.Boolean]($Definition.ContainsKey('NonEmpty') -and $Definition['NonEmpty'])
        Unit          = [System.String]$Definition['Unit']
        Description   = [System.String]$Definition['Description']
        ReplacedBy    = [System.String]$Definition['ReplacedBy']
      }
    )
  }

  [PSCustomObject[]]$Result = $Rules.ToArray()
  $Result
  Write-Debug -Message:'[Get-MaintenanceConfigurationRule] Exiting'
}
