# ADR-repo/0006: Run Every Enabled Stage Each Night and Keep No State Between Runs

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-07                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Medium                                                       |

## Context and Problem Statement

The maintenance stages find different amounts of work: declines and obsolete-update deletion act
on what has aged past a threshold, re-indexing acts on fragmented indexes, retention acts on old
files, and the backup must precede anything that alters SUSDB. A calendar of cadence tiers (for
example daily, monthly and quarterly) has to remember when each tier last ran in order to catch
up a missed date, which adds state that can be lost, corrupted or out of step with the server.

## Considered Options

1. Run every enabled stage on every nightly run, with no calendar and no stored state (chosen).
2. Assign stages to cadence tiers with a calendar, a run-state file and catch-up.

## Decision Outcome

- The scheduled task starts one run per night. Every enabled stage runs on every run and acts
  only on what is due, so a quiet night is short. There are no cadence tiers, no calendar and no
  catch-up: a missed night is made up by the next one.
- A stage that the time budget (`run.maxDurationMinutes`) stops from starting is reported as
  `NotRun` with a warning and runs the next night.
- Decline policies act on every run. There is no preview-only mode; a dry run shows what a policy
  would decline. `-Stage` runs a chosen subset, for example declines and cleanup at different
  times.
- Nothing is stored between runs: each run decides from the server's current state what is due.
- One SUSDB backup per night, keeping the seven most recent (`backup.minimumKept` 7 and
  `backup.maximumAgeDays` 7).
- The start time belongs to the deployment's scheduled task, not to the script. The
  `windows-wsus` role defaults to 01:00 local on downstream servers and 03:00 local on a top-tier
  server, so a hierarchy cleans up from the bottom tier up; each deployment may override it.

### Microsoft guidance

No Microsoft guidance requires a less frequent cadence for any stage:

- The WSUS maintenance guide sets monthly maintenance as the minimum ("you should perform monthly
  maintenance") and lets the cleanup task run "once a month or on any schedule you want"
  ([maintenance guide][guide]).
- Configuration Manager declines superseded and expired updates and removes obsolete updates
  "after every synchronization", stopping obsolete-update removal after 30 minutes and resuming
  it "after the next synchronization occurs" ([software updates maintenance][sum]).
- The re-index script rebuilds or reorganizes only the indexes whose fragmentation or page
  density passes its thresholds, and `sp_updatestats` updates only the statistics whose rows
  changed ([re-index script][reindex]; [sp_updatestats][updatestats]).
- SQL Server leaves the backup frequency to each database's recovery needs and recommends full
  backups in a predictable off-peak period ([back up and restore][backup]).

The timing constraints Microsoft does give are met without a calendar:

- No synchronization during maintenance: the synchronization guard stops one and restarts it
  afterwards.
- Back up before cleaning up, and re-index after declining: the fixed stage order.
- Clean a hierarchy from the bottom up: WSUS servers "should be removed from the bottom up", and
  the guide's example schedule cleans the lowest tier at 1:00 AM and the top tier at 3:00 AM
  ([maintenance guide][guide]); the per-tier start times above follow it.

### Consequences

- Positive: no state to lose or reset; every night's report covers every stage; a stage cut short
  by the budget catches up on its own.
- Negative: every night runs every stage's selection queries, even when there is little to do;
  on a server that has never been maintained the first runs can take several nights, which the
  time budget spreads out.

[guide]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide
[sum]: https://learn.microsoft.com/mem/configmgr/sum/deploy-use/software-updates-maintenance
[reindex]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/reindex-the-wsus-database
[updatestats]: https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-updatestats-transact-sql
[backup]: https://learn.microsoft.com/sql/relational-databases/backup-restore/back-up-and-restore-of-sql-server-databases
