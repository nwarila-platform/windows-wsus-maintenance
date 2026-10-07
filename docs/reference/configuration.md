# Configuration Reference

The script reads one JSON document: the file named by `-ConfigPath`, or
`%ProgramData%\NWarila\WsusMaintenance\maintenance.json` when no path is given. The document is
data only; no value is ever evaluated. It is validated completely before anything changes, every
problem is reported together, and nothing is corrected.

- The machine-readable schema is [maintenance.schema.json](maintenance.schema.json) (JSON Schema
  draft-07), generated from the same catalogue the script validates against.
- Keys are case-sensitive. An unknown key is an error unless `configuration.unknownKeyPolicy` is
  `Warning`.
- A missing key takes its default. `backup.destination` has no default because it is specific
  to each deployment; it must be given while backup is enabled.
- Paths are absolute: drive-rooted, UNC, or rooted at one `%VARIABLE%` expanded at run time.
- Secrets are never written into this document.

## Minimal document

```json
{
  "schemaVersion": 1,
  "backup": { "destination": "H:\\SUSDB" }
}
```

## Cross-field rules

- `backup.destination` is required while `backup.enabled` is true.
- `declines.accelerated.classifications` (at least one) and `declines.accelerated.ageDays` are
  required while `declines.accelerated.enabled` is true.
- `staleComputers.targetGroup` is required when `staleComputers.action` is `Move`.
- `staleComputers.thresholdDays` of zero requires `staleComputers.override`.
- A classification may not appear in both `declinedDeletion.includedClassifications` and
  `declinedDeletion.excludedClassifications`.
- Every `eventLog.eventIds.*` value is distinct.
- `health.certificateExpiry.warningDays` is strictly descending.
- A decline rule's `group` names a group defined in `declines.groups` (matched without regard to
  case).

## Decline rules

Each entry of `declines.rules` is `{ "name", "enabled", "condition", "group"? }`. Names are
unique without regard to case. Every enabled rule acts on every run. A condition is exactly one of:

- `{ "all": [ conditions ] }`, `{ "any": [ conditions ] }`, `{ "not": condition }`;
- a text test on `Title`, `LegacyName`, `ClassificationTitle`, `ProductTitles`,
  `ProductFamilyTitles` or `KnowledgeBaseArticles` with operator `Contains`, `Equals`, `Like`
  (wildcard) or `Match` (regular expression), and a non-empty string value;
- a date test on `CreationDate` or `ArrivalDate` with operator `OlderThanDays` or
  `NewerThanDays` and a whole number of days from 0 to 36500;
- `{ "field": "UpdateSource", "operator": "Equals", "value": "MicrosoftUpdate" | "Other" }`.

Conditions nest at most 16 levels. Text comparisons ignore case. A list field (`ProductTitles`,
`ProductFamilyTitles`, `KnowledgeBaseArticles`) matches when any of its entries does. Knowledge
Base articles are the numbers WSUS stores, without a `KB` prefix; a `KB` prefix in an `Equals` or
`Contains` value is ignored. Titles and category names are compared in `declines.evaluationLanguage`.
Date tests compare with the start of the run minus the given days. Rules run in order, and an update a
rule (or an earlier decline policy of the run) has declined is not counted again. An update on
`declines.neverDecline` is never declined by any policy or rule.

## Keys
### `schemaVersion`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `schemaVersion` | Integer | 1 to 1 | required | Configuration schema version. This release reads version 1 only. |

### `configuration`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `configuration.unknownKeyPolicy` | String | `Error`, `Warning` | `"Error"` | Whether a key this release does not know fails validation (Error) or is reported and ignored (Warning). |

### `run`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `run.dryRun` | Boolean | `true`, `false` | `false` | Apply every selection rule and report the intended changes without changing anything. |
| `run.maxDurationMinutes` | Integer | 0 to 10080 minutes | `240` | Run time budget. No new stage starts once it has elapsed. Zero means unlimited. |
| `run.databaseCommandTimeoutSeconds` | Integer | 0 to 604800 seconds | `0` | Client-side timeout for each database command. Zero means no timeout. |
| `run.connectionTimeoutSeconds` | Integer | 1 to 600 seconds | `30` | Timeout for establishing the WSUS and SUSDB connections. |
| `run.progressBatchSize` | Integer | 1 to 100000 items | `1` | Item-by-item stages log one progress entry per this many items. |
| `run.permissiveFolderOverride` | Boolean | `true`, `false` | `false` | Allow an existing data folder whose access control grants write access to principals other than SYSTEM, Administrators and the run identity. |

### `discovery`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `discovery.sqlInstance` | String | text matching the documented format, or `null` | `null` | SQL Server instance hosting SUSDB (HOST or HOST\INSTANCE). Null means the instance WSUS setup recorded. It must be on this server. |
| `discovery.databaseName` | String | text matching the documented format, or `null` | `null` | SUSDB database name. Null means the name WSUS setup recorded. |
| `discovery.wsusPort` | Integer | 1 to 65535, or `null` | `null` | Port of the WSUS administration interface. Null means the local server's own setting; with a host name or TLS set, 8531 with TLS and 8530 without. |
| `discovery.wsusUseTls` | Boolean | `true`, `false`, or `null` | `null` | Whether to reach the WSUS administration interface over TLS. Null means the local server's own setting. |
| `discovery.wsusHostName` | String | text matching the documented format, or `null` | `null` | Host name of the WSUS administration interface, which with TLS must match its certificate. Null means the local WSUS server. |

### `syncGuard`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `syncGuard.pollIntervalSeconds` | Integer | 1 to 3600 seconds | `10` | Interval between synchronization status checks while waiting for a stop. |
| `syncGuard.waitSeconds` | Integer | 1 to 86400 seconds | `600` | How long one stop attempt waits for the synchronization to reach a not-processing state. |
| `syncGuard.retryDelaySeconds` | Integer | 0 to 86400 seconds | `60` | Delay between stop attempts. |
| `syncGuard.maxAttempts` | Integer | 1 to 100 | `3` | Stop attempts before the run aborts with the precondition-failure code. |
| `syncGuard.suspendSchedule` | Boolean | `true`, `false` | `false` | Suspend the automatic synchronization schedule for the duration of the run. |

### `backup`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `backup.enabled` | Boolean | `true`, `false` | `true` | Create a full SUSDB backup with checksum verification. |
| `backup.destination` | Path | absolute Windows path, or `null` | `null` | Folder for backup files, resolved on the database host. Required when backup is enabled. |
| `backup.sameDay` | String | `Replace`, `Append` | `"Replace"` | Whether a second backup on the same day replaces or appends to that day's file. |
| `backup.compression` | String | `Auto`, `Always`, `Never` | `"Auto"` | Backup compression: when the engine supports it (Auto), always, or never. |
| `backup.minimumKept` | Integer | 0 to 1000 files | `7` | Most recent backup files always kept. Zero means no minimum; with both limits zero every file is kept. |
| `backup.maximumAgeDays` | Integer | 0 to 3650 days | `7` | Backup files this many days old or older, by the date in their name, and outside the most recent set are deleted. Zero means no age limit. |
| `backup.freeSpaceMarginPercent` | Integer | 0 to 1000 percent | `20` | Free space required on the destination beyond the estimated backup size. |
| `backup.gate` | String | `Required`, `Advisory`, `Off` | `"Required"` | Whether stages that delete or alter SUSDB content require a recent successful backup. |
| `backup.freshnessHours` | Integer | 1 to 8760 hours | `24` | How recent a backup must be to satisfy the backup gate. |

### `builtInCleanup`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `builtInCleanup.declineSupersededUpdates` | Boolean | `true`, `false` | `true` | Run the built-in superseded-update decline. Suppressed automatically on a replica. |
| `builtInCleanup.declineExpiredUpdates` | Boolean | `true`, `false` | `true` | Run the built-in expired-update decline. Suppressed automatically on a replica. |
| `builtInCleanup.obsoleteUpdates` | Boolean | `true`, `false` | `true` | Run the built-in obsolete-update deletion. |
| `builtInCleanup.compressUpdates` | Boolean | `true`, `false` | `true` | Remove obsolete update revisions. |
| `builtInCleanup.obsoleteComputers` | Boolean | `true`, `false` | `false` | Run the built-in obsolete-computer deletion (fixed threshold). The stale-computer stage is the configurable alternative. |
| `builtInCleanup.unneededContentFiles` | Boolean | `true`, `false` | `true` | Delete unneeded content files. Also removes files imported manually from the Microsoft Update Catalog. |
| `builtInCleanup.timeoutRetries` | Integer | 0 to 10 | `2` | Retries after a built-in cleanup time-out. |

### `obsoleteUpdates`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `obsoleteUpdates.enabled` | Boolean | `true`, `false` | `true` | Delete obsolete updates one at a time with the SUSDB procedures. |
| `obsoleteUpdates.maxDeletions` | Integer | 0 to 10000000 updates | `0` | Per-run cap on obsolete-update deletions. Zero means no cap. |

### `customIndexes`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `customIndexes.enabled` | Boolean | `true`, `false` | `true` | Ensure the non-clustered SUSDB indexes Microsoft recommends exist. |
| `customIndexes.additional` | IndexArray | array of `{name, table, columns}` | `[]` | Additional non-clustered index definitions (name, table, columns). |

### `deleteUpdateFix`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `deleteUpdateFix.enabled` | Boolean | `true`, `false` | `true` | Check for, and apply when absent, the published fix for slow spDeleteUpdate. |

### `reindex`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `reindex.enabled` | Boolean | `true`, `false` | `true` | Defragment fragmented SUSDB indexes, then update statistics. |

### `syncHistory`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `syncHistory.enabled` | Boolean | `true`, `false` | `true` | Delete synchronization-history records older than the retention. |
| `syncHistory.retentionDays` | Integer | 0 to 3650 days | `90` | Synchronization-history records older than this are deleted. Zero removes all such records. |

### `staleComputers`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `staleComputers.enabled` | Boolean | `true`, `false` | `true` | Remove computer records that have not synchronized within the threshold. |
| `staleComputers.thresholdDays` | Integer | 0 to 3650 days | `90` | Days without synchronization before a computer is stale. Zero requires the override. |
| `staleComputers.includeDownstream` | Boolean | `true`, `false` | `false` | Include computers reported through downstream servers. |
| `staleComputers.action` | String | `Delete`, `Move` | `"Delete"` | Delete stale computers or move them into the target group. |
| `staleComputers.targetGroup` | String | text matching the documented format, or `null` | `null` | Computer group that receives stale computers. Required when the action is Move. |
| `staleComputers.guardCount` | Integer | 0 to 10000000 computers | `50` | Change nothing and raise a notice if more computers than this are selected. |
| `staleComputers.guardPercent` | Integer | 0 to 100 percent | `10` | Change nothing and raise a notice if more than this share of all computers is selected. |
| `staleComputers.override` | Boolean | `true`, `false` | `false` | Proceed despite a guard breach, and allow a zero-day threshold. |

### `declines`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `declines.arrivalWindowDays` | Integer | 0 to 36500 days | `0` | Only updates that arrived within this many days are evaluated. Zero means unlimited. |
| `declines.evaluationLanguage` | String | text matching the documented format | `"en"` | Language in which titles and category names are retrieved for rule evaluation. |
| `declines.neverDecline` | StringArray | array of text, unique | `[]` | Updates never declined by any policy, by Knowledge Base number or update GUID. |
| `declines.superseded.enabled` | Boolean | `true`, `false` | `true` | Decline superseded updates older than the age threshold. |
| `declines.superseded.ageDays` | Integer | 0 to 3650 days | `90` | Superseded updates whose revision is newer than this are kept. |
| `declines.superseded.lastLevelOnly` | Boolean | `true`, `false` | `false` | Decline only updates that are superseded but supersede nothing themselves. |
| `declines.superseded.includeApproved` | Boolean | `true`, `false` | `true` | Superseded updates that are currently approved are eligible. |
| `declines.accelerated.enabled` | Boolean | `true`, `false` | `false` | Apply an additional superseded-update policy to selected classifications. |
| `declines.accelerated.classifications` | StringArray | array of text, unique | `[]` | Classification titles the accelerated policy applies to. Required when it is enabled. |
| `declines.accelerated.ageDays` | Integer | 0 to 3650 days, or `null` | `null` | Age threshold of the accelerated policy. Required when it is enabled. |
| `declines.expired.enabled` | Boolean | `true`, `false` | `true` | Decline updates whose publication state is expired. |
| `declines.rules` | RuleArray | array of decline rules (see below) | `[]` | Decline rules defined for the deployment. None ships enabled. |
| `declines.groups` | GroupArray | array of `{name, enabled}` | `[]` | Rule groups. Disabling a group disables all of its rules. |

### `declinedDeletion`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `declinedDeletion.enabled` | Boolean | `true`, `false` | `false` | Delete declined updates from WSUS. Recovery requires a re-import or resynchronization. |
| `declinedDeletion.protected` | StringArray | array of text, unique | `[]` | Declined updates never deleted, by Knowledge Base number or update GUID. |
| `declinedDeletion.excludedClassifications` | StringArray | array of text, unique | `[]` | Classifications whose declined updates are never deleted. |
| `declinedDeletion.includedClassifications` | StringArray | array of text, unique | `[]` | When not empty, only declined updates in these classifications are deleted. |

### `iisLogs`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `iisLogs.enabled` | Boolean | `true`, `false` | `true` | Delete the WSUS website's IIS log files older than the maximum age. |
| `iisLogs.maxAgeDays` | Integer | 0 to 3650 days | `90` | IIS log files last modified longer ago than this are deleted. |
| `iisLogs.folder` | Path | absolute Windows path, or `null` | `null` | Override for the IIS log folder. Null means detected from the WSUS website. |
| `iisLogs.siteName` | String | text matching the documented format, or `null` | `null` | Override for the IIS site that hosts WSUS. Null means detected. |

### `retention`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `retention.logs.maxAgeDays` | Integer | 0 to 3650 days | `90` | Run logs older than this are deleted. Zero keeps every age. |
| `retention.logs.maxCount` | Integer | 0 to 100000 files | `200` | At most this many run logs are kept. Zero means no count limit. |
| `retention.reports.maxAgeDays` | Integer | 0 to 3650 days | `90` | Saved reports older than this are deleted. Zero keeps every age. |
| `retention.reports.maxCount` | Integer | 0 to 100000 files | `200` | At most this many saved reports are kept. Zero means no count limit. |
| `retention.summaries.maxAgeDays` | Integer | 0 to 3650 days | `90` | Run summaries older than this are deleted. Zero keeps every age. |
| `retention.summaries.maxCount` | Integer | 0 to 100000 files | `200` | At most this many run summaries are kept. Zero means no count limit. |

### `health`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `health.tls.enabled` | Boolean | `true`, `false` | `true` | Raise a notice when WSUS does not use TLS. |
| `health.certificateExpiry.enabled` | Boolean | `true`, `false` | `true` | Report days until the certificate bound to the WSUS TLS port expires. |
| `health.certificateExpiry.warningDays` | IntegerArray | array of 1 to 3650, unique, at least one | `[60,30,14,7]` | Warning tiers, strictly descending. |
| `health.strongCrypto.enabled` | Boolean | `true`, `false` | `true` | Check the .NET strong-cryptography registry values in both registry views. |
| `health.appPool.enabled` | Boolean | `true`, `false` | `true` | Compare the WSUS application-pool settings with the expected values. |
| `health.appPool.queueLength` | Integer | 10 to 65535 | `2000` | Expected application-pool queue length. |
| `health.appPool.idleTimeoutMinutes` | Integer | 0 to 43200 minutes | `0` | Expected idle time-out. |
| `health.appPool.pingingEnabled` | Boolean | `true`, `false` | `false` | Expected pinging setting. |
| `health.appPool.privateMemoryLimitKb` | Integer | 0 to 2147483647 KB | `0` | Expected private memory limit. |
| `health.appPool.regularRecyclingMinutes` | Integer | 0 to 2147483647 minutes | `0` | Expected regular recycling interval. |
| `health.supersededCount.enabled` | Boolean | `true`, `false` | `true` | Count superseded updates that are not declined. |
| `health.supersededCount.threshold` | Integer | 0 to 10000000 updates | `1500` | Raise a notice above this count. |
| `health.processorCount.enabled` | Boolean | `true`, `false` | `true` | Check the logical-processor count on a virtual machine. |
| `health.processorCount.minimum` | Integer | 1 to 1024 processors | `4` | Raise a notice below this count. |

### `report`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `report.folder` | Path | absolute Windows path | `"%ProgramData%\\NWarila\\WsusMaintenance\\Reports"` | Folder for saved reports, with timestamped file names. |
| `report.formats` | StringArray | array of `Text`, `Html`, unique, at least one | `["Text","Html"]` | Formats saved to the report folder. |
| `report.maxItemsPerSection` | Integer | 1 to 100000 items | `100` | Items listed per report section; the full list goes to the run log. |

### `log`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `log.folder` | Path | absolute Windows path | `"%ProgramData%\\NWarila\\WsusMaintenance\\Logs"` | Folder for run logs. |
| `log.verbosity` | String | `Error`, `Warning`, `Information`, `Verbose`, `Debug` | `"Information"` | Lowest level written to the run log. |

### `summary`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `summary.folder` | Path | absolute Windows path | `"%ProgramData%\\NWarila\\WsusMaintenance\\Summaries"` | Folder for machine-readable run summaries. |
| `summary.format` | String | `Json` | `"Json"` | Run summary format. |

### `eventLog`

| Key | Type | Valid values | Default | Meaning |
| --- | --- | --- | --- | --- |
| `eventLog.enabled` | Boolean | `true`, `false` | `true` | Write Windows Event Log entries through the registered event source. |
| `eventLog.logName` | String | text matching the documented format | `"Application"` | Event log the source is registered in. |
| `eventLog.source` | String | text matching the documented format | `"Invoke-WsusMaintenance"` | Event source registered by deployment. |
| `eventLog.eventIds.runStarted` | Integer | 1 to 65535 | `1000` | Event identifier for run start. |
| `eventLog.eventIds.runSucceeded` | Integer | 1 to 65535 | `1001` | Event identifier for a run that completed successfully. |
| `eventLog.eventIds.runWarning` | Integer | 1 to 65535 | `1002` | Event identifier for a run that completed with warnings. |
| `eventLog.eventIds.runFailed` | Integer | 1 to 65535 | `1003` | Event identifier for a run that completed with errors. |
| `eventLog.eventIds.stageError` | Integer | 1 to 65535 | `1100` | Event identifier for each stage error. |
| `eventLog.eventIds.preconditionFailure` | Integer | 1 to 65535 | `1200` | Event identifier for a precondition failure. |
| `eventLog.eventIds.configurationInvalid` | Integer | 1 to 65535 | `1300` | Event identifier for an invalid configuration. |
