# CLI Contract

`Invoke-WsusMaintenance.ps1` is a Windows PowerShell 5.1 script assembled by `build.ps1`. It is
installed as a single file and normally launched once a day by a scheduled task that
configuration management creates. It never prompts.

Every run carries out every enabled stage, and each stage acts only on what is due, so there is
no calendar, no cadence tier and no state kept between runs: work a run could not finish is done
by the next run.

## Parameters

| Parameter | Type | Default | Behavior |
| --- | --- | --- | --- |
| `-ConfigPath` | `System.String` | `%ProgramData%\NWarila\WsusMaintenance\maintenance.json` | Configuration document to read. |
| `-Stage` | `System.String[]` | every enabled stage | Run only the listed stages, still in catalogue order. Stage names are matched without regard to case and recorded in their canonical spelling; a repeated or unknown name is a configuration error. A listed stage that configuration disables is still skipped. |
| `-DryRun` | Switch | off | Simulate: report what each stage would change without changing anything. |
| `-ReportFolder` | `System.String` | configuration | Report folder for this run; an absolute path. |
| `-ReportFormat` | `Text`, `Html` | configuration | Report formats for this run. |
| `-Verbosity` | `Error`, `Warning`, `Information`, `Verbose`, `Debug` | configuration | Log verbosity for this run. |
| `-ValidateOnly` | Switch | off | Validate the configuration document and the options, emit the result, and stop. Writes no file and no event. |

Every override given on the command line is recorded in the run result.

## Stage names

`Backup`, `CustomIndexes`, `DeleteUpdateFix`, `SupersededDecline`, `AcceleratedDecline`,
`ExpiredDecline`, `RuleDecline`, `DeclinedDeletion`, `ObsoleteUpdates`, `BuiltInCleanup`,
`SyncHistory`, `StaleComputers`, `Reindex`, `IisLogRetention`, `ArtifactRetention`,
`HealthChecks` (in execution order).

## Result object

Every completed run writes exactly one object whose first type name is
`WsusMaintenance.RunResult`.

| Field | Type | Meaning |
| --- | --- | --- |
| `Status` | `System.String` | `Success`, `Warning` or `Error`. |
| `ExitCode` | `System.Int32` | The process exit code, derived from `Status`. |
| `Stages` | `PSCustomObject[]` | One outcome per stage in catalogue order: name, order, status (`Success`, `Warning`, `Error`, `Skipped`, `NotRun`), reason, start time, duration, counts, message, notices and any error text and time. |
| `Notices` | `PSCustomObject[]` | Conditions that need attention, each with a severity (`Information`, `Warning`, `High`, `Error`). |
| `Run` | `PSCustomObject` | Run identifier, stages listed with `-Stage` (empty for a full run), dry-run flag, start and end time, duration, time-budget deadline, and `Artifacts`: the paths of the run log, the saved reports and the summary. Null after `-ValidateOnly`. |
| `Validation` | `PSCustomObject` | Configuration path, validity, errors, warnings, overrides, the stages listed with `-Stage`, `ValidateOnly`, and the effective configuration. |
| `GeneratedAtUtc` | `System.DateTime` | UTC time the result was created. |

A run that stops on an invalid configuration or invalid options writes no result object; the
error record's target object carries the same validation summary with every problem listed.

## Run order

The configuration and options are validated first (`-ValidateOnly` stops there). The run then
opens its run log under a new run identifier and chooses its report and summary folders. It
requires a valid configuration, elevation (administrator or LocalSystem) and the system-wide lock
`Global\Invoke-WsusMaintenance`, in that order. Under the lock it discovers the environment,
connects to the WSUS administration interface and to SUSDB, detects the server tier, checks the
database permissions of every stage and makes sure no synchronization runs, stopping one that
does. It then plans every enabled stage (or the `-Stage` list) in catalogue order, skipping the
decline stages on a replica and any stage that lacks a database permission, runs each in its own
error boundary within the time budget, restarts the synchronization it stopped, closes the
database connection, releases the lock on every path, and saves the report and the summary. A
stage the budget stops from starting is reported as `NotRun` with a warning and runs again on the
next run.

These stop the run with a failure report and summary (what happened, the point reached, what to
do), the matching event and exit code `3`, or `4` for an invalid configuration: a log folder that
cannot be written; an invalid configuration; a run that is not elevated; a lock that cannot be
created; an unsupported combination (WSUS not installed, Windows Server 2016 or older, SUSDB on
Windows Internal Database or on a remote SQL Server); a WSUS administration interface or SUSDB
that cannot be reached; and a synchronization that does not stop. A run that finds the lock held
logs that and exits `5` with no report.

## Outputs

Every run other than `-ValidateOnly` writes, named after its run identifier
(`yyyyMMdd-HHmmss-` followed by eight hexadecimal digits):

| File | Folder | Content |
| --- | --- | --- |
| `WsusMaintenance-<run id>.log` | `log.folder` | The run log: one line per entry with local time and offset, level, run identifier, stage and message, filtered by `log.verbosity`. |
| `WsusMaintenance-<run id>.txt` | `report.folder` | The plain-text report (when `report.formats` includes `Text`). |
| `WsusMaintenance-<run id>.html` | `report.folder` | The HTML report (when `report.formats` includes `Html`). |
| `WsusMaintenance-<run id>.json` | `summary.folder` | The summary; it validates against [summary.schema.json](summary.schema.json). |

The report header records the WSUS version, the server role, the upstream source, the database,
the WSUS endpoint, the run identity, the database permissions and what the synchronization guard
did, and the report records when each connection was established.

A report or summary folder that cannot be written falls back to its built-in default with a
warning. With an invalid configuration, each output setting the document states validly is
still used and the rest take their defaults. No secret reaches any file or event.

Events, under the source `eventLog.source` in `eventLog.logName`, with the identifiers in
`eventLog.eventIds`:

| Event | Default | Type |
| --- | --- | --- |
| Run started | `1000` | Information |
| Completed: success | `1001` | Information |
| Completed: warning | `1002` | Warning |
| Completed: error | `1003` | Error |
| Stage error (one per failed stage) | `1100` | Error |
| Precondition failure | `1200` | Error |
| Invalid configuration | `1300` | Error |

When the source is not registered in that log, the run logs one warning and writes no events.

## Exit Codes

| Code | Meaning | ErrorId |
| --- | --- | --- |
| `0` | Success. | N/A |
| `1` | One or more stage errors, or an unhandled failure. | `StageError` or unmapped |
| `2` | Completed with warnings. | N/A |
| `3` | Aborted on a precondition (log folder, elevation, lock, unsupported server combination, connectivity, synchronization guard). | `PreconditionFailed` |
| `4` | Invalid configuration document or options. | `ConfigurationInvalid` |
| `5` | Another run holds the lock. | `LockHeld` |
| `6` | Delivery test failed (reserved). | `DeliveryFailed` |

The entry script maps the leading segment of `FullyQualifiedErrorId` to the code; anything
unrecognised exits `1`, never `0`.
