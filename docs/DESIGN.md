# Design

This document is the working design of `windows-wsus-maintenance`: what the script does, how it is
built, how it behaves on each kind of WSUS server, what release one contains, and where each
milestone stands. It is written so that a maintainer can carry on from it together with the
behavioural requirements specification (requirement identifiers `REQ-001` to `REQ-099`) and the
repository itself.

The decided behaviour and defaults are stated here and in the repository's architecture decision
records ([decision-records](decision-records/README.md)).

Status date: 2026-10-07 (M0 to M10 complete: release one is built and its gate is green; what
only a live server can prove is listed in section 12, by the lane that will prove it).

---

## 1. Purpose and scope

The script performs recurring, unattended upkeep of a Windows Server Update Services (WSUS) server
and its SUSDB database: Microsoft-documented cleanup and database maintenance, update declines,
housekeeping, health checks and reporting. It is installed as one file and launched by a scheduled
task that configuration management creates; it never creates, changes or removes its own task.

Supported targets:

- Windows Server 2019, 2022 and 2025 with the WSUS role installed locally.
- Windows PowerShell 5.1. PowerShell 7 is not required and not targeted.
- SUSDB on SQL Server on the WSUS server itself, default or named instance. Windows Internal
  Database (WID), remote SQL Server and Windows Server 2016 are detected and refused as a
  precondition failure that names the combination.
- Every server tier: a top-tier server that synchronizes from Microsoft Update, an autonomous
  downstream server, and a replica downstream server. Domain membership is not required; the
  script must run on a workgroup host.

## 2. Deployment profiles

The script serves several kinds of deployment. None is hard-coded: the script detects the
server's tier on every run, and everything else is configuration.

| Profile | Tier | Upstream | Set locally | Enabled behaviour |
|---|---|---|---|---|
| Top-tier server that only synchronizes and serves | Top tier; may be a workgroup host (not domain-joined) | Microsoft Update | Everything | Upkeep and declines; no approval and no pre-staging. It downloads every update in its selected products and classifications as soon as Microsoft publishes it and serves it to downstream servers. |
| Autonomous downstream of an externally managed upstream | Autonomous downstream | A WSUS server managed outside the deployment | Everything except the synchronized products and classifications, which the upstream sets | Upkeep, declines, deferred approval and content pre-staging. The upstream link may be slow, so content for needed updates is staged early. |
| Autonomous downstream of a locally managed upstream | Autonomous downstream | A top-tier server of the same deployment | Everything | As the previous profile. |
| Replica | Replica downstream | Any WSUS server | Everything a replica does not inherit | Upkeep; the decline and approval stages are skipped. The `windows-wsus` repository builds and tests such a replica on every change (SQL Server 2022 Standard, default instance, Windows Server 2022, domain-joined). |

What this implies:

- A downstream gets content only from its upstream, and an upstream that downloads everything it
  synchronizes already holds content for every update in its selection as soon as it is
  published. When the upstream link is slow, the bottleneck is the downstream's own transfer, so
  every lever that speeds up content arrival sits on the downstream (section 11.3).
- A top tier that only synchronizes and serves needs download settings that differ from a
  downstream (it downloads everything it synchronizes). Health-check expectations for download
  settings are therefore per-deployment configuration, not fixed values.
- Deploying such a top-tier server (a top-tier, workgroup mode) is a later extension of the
  `windows-wsus` role and out of scope for this repository. The script itself must run correctly
  on a top-tier workgroup host.

## 3. Architecture

### 3.1 Single installed script from structured source

The repository follows the single-script layout ([repo/0001](decision-records/repo/0001-single-script-project.md),
[repo/0002](decision-records/repo/0002-script-structure-and-test-seams.md)):

```text
src/EntryPoint.ps1        Script help, parameters, Trap, initialization, execution and exit code
src/Public/*.ps1          Invoke-WsusMaintenance, the orchestrator
src/Private/*.ps1         One function (or enum) per file
build.ps1                 Build, Analyze, Test, Smoke, Clean, All
build/                    Generated; never edited, never committed
```

`build.ps1 -Task Build` emits `build/Invoke-WsusMaintenance.ps1` (the one file that is installed)
and `build/Invoke-WsusMaintenance.Functions.ps1` (the functions only, which the tests dot-source
and which carries the coverage measurement).

### 3.2 Coding standard

The organisation PowerShell style guide (rules SG-1 to SG-8 in `NWarila/powershell-template`
`docs/STYLE-GUIDE.md`) applies throughout, enforced by `PSScriptAnalyzerSettings.psd1` and
`analyzers/HouseRules.psm1` with zero findings allowed. In practice:

- Every function: full six-option `[CmdletBinding()]` in alphabetical order, `[OutputType()]`,
  the five-option `[Parameter()]` on every parameter, parameters in alphabetical order,
  validation attributes before the type.
- Locals are typed `$Private:` declarations at the top under `# Initialize Variable(s)`.
- Single exit: build a typed `$Result`, emit it, and end with
  `Write-Debug -Message:'[Name] Exiting'`. No `Return`.
- PascalCase keywords, colon-form parameters (`-Name:$Value`). A script block passed in colon
  form must be parenthesized: `-Process:({ $PSItem.Name })`.
- User-facing text lives in per-file `$Script:Message += @{ 'Function.Key' = '...' }` fragments.
  The build creates the table.
- Failures that end a run use `New-ErrorRecord -ErrorId:<MaintenanceExitCode member> -IsFatal`.
  The entry point maps the ErrorId to the exit code.

### 3.3 Seams and testability

Windows-only types and commands are confined to small seam functions, so that the whole suite
runs under PowerShell on Linux as well as Windows PowerShell 5.1. Tests mock the seams with
Pester `Mock`. The seams:

| Seam | Wraps |
|---|---|
| `Get-MaintenanceTime` (M2) | The clock: run start, every budget check, every log and report timestamp |
| `New-MaintenanceLock` (M2) | The system-wide named mutex `Global\Invoke-WsusMaintenance` |
| `Test-MaintenanceElevation` (M2) | Administrator or LocalSystem check |
| `New-MaintenanceRunId` (M3) | The random part of the run identifier |
| `Resolve-MaintenancePath` (M2) | Environment-variable expansion of configured folders; tests map folders into the test drive |
| `Test-MaintenanceEventSource`, `Write-MaintenanceEventEntry` (M3) | `System.Diagnostics.EventLog`: is the source registered in the log, and write one entry |
| `New-SqlConnection` (M4) | `System.Data.SqlClient.SqlConnection` (in-box .NET Framework; no external SQL utility, so REQ-054 needs no probe) |
| `Get-WsusUpdateServer` (M4) | The WSUS administration API (`Microsoft.UpdateServices.Administration.AdminProxy.GetUpdateServer`) |
| `Get-WsusSetupValue` (M4) | `HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup` |
| `Get-MaintenanceOperatingSystem`, `Get-MaintenanceIdentity` (M4) | The operating-system build and the run identity |
| `Wait-MaintenanceInterval` (M4) | `Start-Sleep`, so the synchronization guard can be tested without waiting |
| `Get-BackupDestinationSpace` (M5) | `System.IO.DriveInfo`: the free space of the volume holding the backup folder |
| `New-WsusAdministrationObject` (M6, M7) | The scope classes of the WSUS administration API (`CleanupScope`, `ComputerTargetScope`, `UpdateScope`) |
| `Get-IisConfiguration` (M9) | `applicationHost.config`, read only |
| `Get-MaintenanceRegistryKey` (M9) | `Microsoft.Win32.RegistryKey` in the 64-bit or 32-bit view, read only: strong cryptography and HTTP.sys certificate bindings |
| `Get-MaintenanceCertificate` (M9) | `X509Store` of the local machine, read only |
| `Get-MaintenanceMachineInfo` (M9) | `Win32_ComputerSystem`: manufacturer, model and logical processors |
| `Test-MaintenanceAclSupport` (M10) | Whether the host has Windows access control lists, so folder protection can be exercised with stand-ins on any platform |
| `Get-MaintenanceIdentitySid` (M10) | The security identifier of the run identity |
| `Get-MaintenancePathAccess` (M10) | `Get-Acl`: the owner and every access rule of a file or folder, read only |
| `New-MaintenanceProtectedFolder` (M10) | Creation of one folder together with its protected access control list (`Directory.CreateDirectory` with a `DirectorySecurity` on Windows PowerShell, `FileSystemAclExtensions.Create` on PowerShell 7) |
| `Get-MaintenanceScriptPath` (M10) | The path of the running script, for the installation check |
| `Test-MaintenanceDependencyPresent` (M10) | Whether a component is installed: the WSUS administration assembly, the SQL Server client, the IIS configuration |

Lessons already learned in this code base:

- Variables declared `$Private:` are not visible inside script blocks passed to `Where-Object`.
  Use a loop instead.
- In tests, a helper that returns an array has it unrolled by the pipeline. Keep it intact with a
  leading comma or by wrapping the call in `@( )`.
- `ConvertFrom-Json` differs between editions:

  | Edition | Whole numbers | Fractions | ISO date strings | Keys differing only by case |
  |---|---|---|---|---|
  | Windows PowerShell 5.1 | `Int32` | `Decimal` | Left as strings | — |
  | PowerShell 7 | `Int64` | `Double` | Converted to `DateTime` | Rejected |

  Validation accepts both editions' integer types, and tests avoid date-like strings.
- Pester 6 does not fall through to the real command when no parameter filter of a mock
  matches; Pester 5 does. Tests therefore always give a filtered mock a default mock, or mock a
  different command.
- A test's `-Skip:` condition is evaluated during discovery, so the variables it reads are set
  in `BeforeDiscovery`, not `BeforeAll`.
- `[System.Math]::Max(0, $Seconds)` picks the integer overload and drops the fraction; durations
  use `[System.Math]::Max([System.Double]0, $Seconds)`.
- Redaction patterns run on plain text only. Running them over serialized JSON or HTML can
  swallow the quotes or tags that follow a value, so the report model is redacted field by field
  and the rendered files are written as they are.
- `Test-Json` (PowerShell 7) validates the summary against its schema; Windows PowerShell 5.1 has
  no equivalent, so that test is skipped there.
- `Invoke-SusdbCommand` and everything that uses the WSUS API work on whatever object they are
  given, so tests pass stand-ins for the update server, the subscription and the SQL connection
  (`tests/Helpers/MaintenanceFakes.ps1`) instead of mocking every call.
- `GetNewClosure()` does not capture `$Private:` variables. The InfoMessage handler is therefore
  built by `New-SusdbMessageHandler` around its parameter.
- A .NET property getter that throws (for example `FileInfo.Length` of a missing file) gives
  `$null` in an expression instead of an error, so code checks `Exists` first.
- `Sort-Object` compares strings by culture, which orders `-` and `_` differently on different
  platforms; tests that compare file lists sort them ordinally.
- Under `Set-StrictMode -Version 3.0` an index past the end of an array is an error, not `$null`,
  so code checks the length of a `-split` result before reading an optional part.
- `powershell.exe -File` passes each argument as one literal string, so a list such as
  `-Stage Backup,Reindex` arrives as one value, and a `[ValidateSet()]` failure exits 1 before the
  script runs. Options therefore take comma-separated lists and are validated by the script.
- A directory's last write time changes when a file is created or deleted in it, which lets a
  test prove that nothing was written to a folder, a probe included.

### 3.4 Quality gates, release and provenance

- **Local gate**, run after every milestone: `pwsh -NoProfile -File ./build.ps1 -Task All`. It
  requires zero analyzer findings, all tests passing, at least 90% line coverage on the functions
  artifact, and the smoke scripts passing. `build.ps1` loads the newest Pester installed (6.1.0
  on the development host); CI pins Pester 5.7.1, and the suite is checked under both.
- **CI** (`.github/workflows/ci.yaml`): workflow lint, workflow security scan, secret scan, an
  analyzer SARIF upload, and the full build on `windows-latest` under Windows PowerShell 5.1. A
  runner lane will install SQL Server Express and WSUS on the hosted runner and run the built
  script against a real, unsynchronized top-tier SUSDB (milestone M11).
- **Release** (`.github/workflows/release.yaml`, tags `v*`): a module-free sealed build, then
  analyze, test and smoke run against the sealed copy. Only then is the GitHub Release published,
  bound to the sealed digest, carrying the script, its `.sha256` sidecar,
  `maintenance.schema.json` and `summary.schema.json` (copied unchanged from `docs/reference/`)
  and signed build provenance whose subjects cover the script and both schemas; the release job
  checks every asset against the sealed subjects before publishing
  ([repo/0009](decision-records/repo/0009-release-assets-and-schemas.md)). No release has been
  tagged yet.
- **Versioning**: release-please, starting from version `0.0.0`.

### 3.5 Consumption by windows-wsus

The `windows-wsus` role installs a pinned release: the controller fetches it and verifies its
pinned digest. These integration pieces are delivered separately in that repository:

- **I1. Backup volume.** A dedicated backup volume (`Function = WSUSBACKUP`) formatted by the disk
  role, with a role input for its drive letter.
- **I2. SQL rights.** A script pair that ensures a login for `NT AUTHORITY\SYSTEM` and makes it
  the SUSDB owner (`ALTER AUTHORIZATION`), then verifies by reading it back. It also grants the
  backup folder to the SQL Server service SID.
- **I3. Installation.**
  - Role defaults hold the release tag and the asset SHA-256.
  - The controller downloads the asset with `ansible.builtin.get_url`, verifying `checksum`, and
    `win_copy` installs it, so the guest needs no internet access.
  - Protected ACLs go on the install, configuration and data folders.
  - The configuration document is written from role variables (`to_nice_json`).
  - The event source is registered (`ansible.windows.win_eventlog`).
  - `-ValidateOnly` runs at deploy time with `changed_when: false`.
  - A scheduled task is created (`community.windows.win_scheduled_task`: `SYSTEM`,
    `service_account`, `highest`, `multiple_instances: 2`, an execution time limit above the run
    budget, `start_when_available`, and a daily trigger whose role default is 01:00 local on a
    downstream server and 03:00 local on a top-tier server
    ([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)), so a hierarchy cleans
    up from the bottom tier up as Microsoft advises ([maintenance guide][guide]); each deployment
    may override it).
- **I4. Proof playbook.** Runs after the idempotence gate: starts the task in dry-run, then live
  twice, and asserts the exit codes, the summary, the events, replica gating, and that the second
  run finds nothing to do.
- **I5. Autonomous lifecycle variant.** A dispatch-only variant that builds the server with
  `replica: false` against a test upstream, skips the client proof, and gives the decline engine
  live evidence.

Paths:

| Item | Location |
|---|---|
| Installed script | `C:\ProgramData\NWarila\bin\Invoke-WsusMaintenance.ps1`, under a protected ACL; the script refuses to run from a location that principals other than SYSTEM, Administrators and the run identity can change |
| Configuration document | `C:\ProgramData\NWarila\WsusMaintenance\maintenance.json` (the script's fixed default) |
| Data folders | Configuration values; the role points them at a subdirectory of the IIS log volume. A folder the run creates is protected; an existing one that others can change is refused unless `run.permissiveFolderOverride` is set ([repo/0007](decision-records/repo/0007-protected-folders-and-runtime-integrity.md)) |

## 4. Command line, exit codes, status and events

### 4.1 Parameters

| Parameter | Meaning |
|---|---|
| `-ConfigPath` | Configuration document. Defaults to `%ProgramData%\NWarila\WsusMaintenance\maintenance.json`. |
| `-Stage` | Run only the listed stages, still in catalogue order; without it every enabled stage runs. Names are matched without regard to case and recorded in their canonical spelling, and may be given as one comma-separated value, as `powershell.exe -File` passes them. This is how a hierarchy runs declines and cleanup separately (REQ-043). The onboarding profile is deferred. |
| `-DryRun` | Simulate: every stage applies its selection logic and reports what it would change; SUSDB receives only reads. |
| `-RemoveCustomIndexes` | Drop the custom indexes this script created, and only those, instead of creating missing ones. Runs the `CustomIndexes` stage alone unless `-Stage` is given, which must then include `CustomIndexes`. |
| `-ReportFolder`, `-ReportFormat` | One-run report destination and formats; formats may be one comma-separated value. |
| `-Verbosity` | One-run log verbosity. |
| `-ValidateOnly` | Validate the configuration and the options, then stop. |

Every override in effect is recorded (REQ-083). Option values are matched without regard to case.
An unknown or repeated stage name, and an unknown format or verbosity, is a configuration error,
reported together with any configuration-document errors (exit code 4).

Order of a run (M2):

1. Read and validate the configuration document and the options; with `-ValidateOnly`, stop here
   without writing any file or event.
2. Open the run: a new run identifier, the run log, and the report and summary folders (falling
   back to the built-in defaults with a warning). A missing folder is created protected, and an
   existing one that others can change is not written to (section 4.5). An invalid configuration
   still names its output settings where it validly can. A log that cannot be written stops the
   run with `PreconditionFailed`.
3. With an invalid configuration, stop with `ConfigurationInvalid`.
4. Check elevation (administrator or LocalSystem); otherwise stop with `PreconditionFailed`.
   Then check folder protection (REQ-092): a report or summary folder refused in step 2, or a
   script file or folder that principals other than SYSTEM, Administrators and the run identity
   can change, stops the run with `PreconditionFailed`
   ([repo/0007](decision-records/repo/0007-protected-folders-and-runtime-integrity.md)).
5. Take the system-wide lock `Global\Invoke-WsusMaintenance`; when another run holds it, log
   that and stop at once with `LockHeld`. A lock left by a crashed run is abandoned by the
   operating system and taken over.
6. Discover the environment (section 5.1): the operating system and where SUSDB lives. An
   unsupported combination stops the run with `PreconditionFailed` and names it. Then check the
   dependencies (REQ-093) and log the result: a missing component the whole run needs (the WSUS
   administration API, the SQL Server client) stops the run with `PreconditionFailed`; a missing
   IIS configuration makes IIS log retention unavailable, unless `iisLogs.folder` names the
   folder.
7. Connect to the WSUS administration interface and to SUSDB (REQ-053); a failed connection
   stops the run with `PreconditionFailed`. Detect the server tier (REQ-052).
8. Check the database permissions of every stage (REQ-025); a stage that lacks one is skipped
   with a Warning notice before any stage starts.
9. Run the synchronization guard (REQ-044); a synchronization that will not stop stops the run
   with `PreconditionFailed`, after restoring what the guard changed.
10. Write the run-started event, build the stage plan (every enabled stage, or the `-Stage` list,
    in catalogue order, gated by tier, permissions and missing components) and run each stage in its own error
    boundary within the time budget. Before the first stage that deletes or alters SUSDB content,
    the backup gate is evaluated once (section 10, M5). A stage the budget stops from starting is
    reported as `NotRun` with a warning and runs on the next night.
11. Restart the synchronization the guard stopped and restore the schedule it suspended; close
    the SUSDB connection and release the lock, on every path. Nothing is stored between runs.
12. Save the report and the summary, log the notices, and write a stage-error event per failed
    stage and the completion event.

Steps 2 to 9 change nothing on the server except creating missing data folders and stopping a
running synchronization (and, when configured, suspending its schedule), which step 11 undoes.
Each stop in steps 2 to 9, except `LockHeld`, first saves a failure report and summary and writes
its event (REQ-069).

An unexpected error anywhere after step 2 (REQ-098) is caught at the top: step 11 still runs, and
the run saves a failure report and summary with the failure kind `StageError` and the point it
reached, writes the run-failed event and exits with `StageError` (1). An error before the run log
exists exits 1 through the entry point's trap, with nothing changed and no report
([repo/0008](decision-records/repo/0008-failure-handling-and-rerun-safety.md)).

### 4.2 Exit codes (fixed)

| Code | Member | Meaning |
|---|---|---|
| 0 | `Success` | Completed, nothing to report above information. |
| 1 | `StageError` | One or more stage errors. Also every unexpected failure, with a failure report once the run log is open: nothing unexpected exits 0. |
| 2 | `CompletedWithWarnings` | Completed with warnings. |
| 3 | `PreconditionFailed` | Aborted on a precondition: log folder, elevation, data folder or script protection, lock, unsupported combination, missing component, connectivity, synchronization guard. |
| 4 | `ConfigurationInvalid` | Invalid configuration document or options. |
| 5 | `LockHeld` | Another run holds the lock. |
| 6 | `DeliveryFailed` | Reserved for the delivery test once mail delivery exists. |

### 4.3 Run status and severity

- Severity scale: `Information` < `Warning` < `High` < `Error`.
- `High` marks something that needs attention, such as a guard breach or a failed backup. It
  raises the run status to warning.
- `Error` raises the run status to error.
- The run status is the worst of the stage outcomes and notices (REQ-077). It decides the exit
  code.

### 4.4 Event Log

Events go to the `Application` log under the source `Invoke-WsusMaintenance`. Deployment
registers the source; the script never registers it. The identifiers are configurable:

| Event | Default identifier | Entry type | Written |
|---|---|---|---|
| Run started | 1000 | Information | Once every precondition has passed, before the first stage |
| Run completed: success | 1001 | Information | Last, for a run that completed |
| Run completed: warning | 1002 | Warning | Last, for a run that completed |
| Run completed: error | 1003 | Error | Last, for a run that completed, or for a run an unexpected error stopped |
| Each stage error | 1100 | Error | After the stages, one per failed stage |
| Precondition failure | 1200 | Error | Instead of the events above, for a log, elevation, folder-protection, installation, lock, environment, dependency, connection or synchronization-guard failure |
| Invalid configuration | 1300 | Error | Instead of the events above |
| Late content | 1400 | Warning | During deferred approval, once per run that approves updates whose files are not yet local, naming each |

The source is checked on the first event of a run. When it is not registered in the configured
log, or cannot be checked, one warning goes to the run log and the run continues without events
(REQ-072). A run that stops with `LockHeld` writes no event.

### 4.5 Outputs

Each run other than `-ValidateOnly` produces, under its run identifier
(`yyyyMMdd-HHmmss-` and eight random hexadecimal digits):

| Output | Location | Content |
|---|---|---|
| Run log | `log.folder\WsusMaintenance-<run id>.log` | One line per entry: local time with offset, level, run identifier, stage, message. Run header, overrides, effective configuration, every stage's start, end, status and items, every notice, the outcome and the files written. Filtered by `log.verbosity`. |
| Text report | `report.folder\WsusMaintenance-<run id>.txt` | Header (server, WSUS version, role, upstream, database, run identifier, profile, dry run, start time with time zone, configuration, overrides, run log); failure, if any; notices by severity, the highest marked `>>>`; WSUS connection time; one section per stage with status, duration, reason, counts, items (at most `report.maxItemsPerSection`; all of them are in the log) and error; totals, duration and status. |
| HTML report | `report.folder\WsusMaintenance-<run id>.html` | The same, self-contained and HTML-encoded, with notices coloured by severity, links as hyperlinks and commands as preformatted text. |
| Summary | `summary.folder\WsusMaintenance-<run id>.json` | Validates against [reference/summary.schema.json](reference/summary.schema.json); its counts and each stage's listed items come from the same report model. |
| Events | Event Log | Section 4.4. |
| Exit code | Task Scheduler last run result | Section 4.2. |

- **Formats.** `report.formats` chooses text, HTML or both; `-ReportFolder` and `-ReportFormat`
  override them for one run.
- **Folder fallback.** A report or summary folder that cannot be written falls back to the
  built-in default with a Warning notice in the report; when the default fails too, that file is
  not saved and the notice says so. A log folder that cannot be written stops the run (REQ-071).
- **Folder protection** (REQ-092). Every folder the run creates (log, report, summary and backup,
  and each missing level above them) is created with inheritance off and full control for
  SYSTEM, Administrators and the run identity only (and the SQL Server service account for the
  backup folder), and its access control list is read back and verified. An existing folder is
  never changed; one whose owner or allow rules let another principal change it is not written
  to: a log folder stops the run at step 2, a report or summary folder falls back for the failure
  report and stops the run at step 4, and a backup folder fails the backup stage, which closes the
  backup gate. `run.permissiveFolderOverride` uses such folders with a Warning notice each run.
- **Broken configuration.** When the document is missing, unreadable or invalid, each output
  setting it states validly is still used and every other setting takes its built-in default,
  so the failure report reaches a known folder (REQ-069).
- **Secrets.** Every log line, every text in the report model (and so in both reports and the
  summary) and every event message passes through `Protect-MaintenanceText`, which removes the
  values registered with `Register-MaintenanceSecret`, connection-string passwords and the
  values of credential-named JSON keys (REQ-091). Release one consumes no secret; the mechanism
  is proven with a planted value.
- **Discovery.** The header shows the WSUS version, the server role, the upstream source, the
  database type and location, the WSUS endpoint (host, port, TLS), the run identity (REQ-090),
  the database permissions summary (REQ-025) and what the synchronization guard did (REQ-044),
  and the report records when each connection was established (REQ-053). Anything a failed run
  did not reach reads "not yet discovered".

Release one does not send mail. It therefore consumes no secret and needs no secret store; its
outputs are the files above, the Event Log and the exit code.

## 5. Server tier behaviour

### 5.1 Discovery and refused combinations

- **Database.** The SQL Server instance and database name come from the values WSUS setup
  records in `HKLM\SOFTWARE\Microsoft\Update Services\Server\Setup` (`SqlServerName`,
  `SqlDatabaseName`) ([WSUS server settings][settings]) unless `discovery.sqlInstance` or
  `discovery.databaseName` overrides them. An instance carrying `##WID` or `##SSEE` is Windows
  Internal Database ([maintenance guide][guide]); any other is SQL Server, local when its host is
  this computer (name, fully qualified name, `.` or `localhost`) and remote otherwise.
- **Refused, as `PreconditionFailed` naming the combination:** WSUS not installed; Windows Server
  2016 (build 14393) or older ([release information][release]); Windows Internal Database; remote
  SQL Server; a value that is neither recorded nor configured, or not a valid name.
- **WSUS administration interface.** The local server through
  `AdminProxy.GetUpdateServer()` ([AdminProxy][adminproxy]); when `discovery.wsusHostName`,
  `discovery.wsusPort` or `discovery.wsusUseTls` is set, that host (default: this computer), port
  (default 8531 with TLS, 8530 without) and TLS setting. The endpoint shown in the report comes
  from the connected server (`Name`, `PortNumber`, `IsConnectionSecureForApiRemoting`) and the
  version from `Version` ([IUpdateServer][iupdateserver]). The decline stages request
  returned strings in `declines.evaluationLanguage` while they read updates, and restore the
  previous language afterwards (section 10, M7).
- **SUSDB.** Integrated authentication and the `run.connectionTimeoutSeconds` connection time-out.
  Commands use no client-side time-out unless `run.databaseCommandTimeoutSeconds` sets one
  (REQ-095); a failed command is reported with how long it ran.
- **Permissions** (REQ-025), read with `HAS_PERMS_BY_NAME` and `IS_SRVROLEMEMBER`
  ([HAS_PERMS_BY_NAME][perms]):

  | Stage | Needs |
  |---|---|
  | Backup | `BACKUP DATABASE` ([BACKUP][backupperm]) |
  | CustomIndexes | `ALTER` on `dbo.tbLocalizedPropertyForRevision` and `dbo.tbRevisionSupersedesUpdate` |
  | DeleteUpdateFix | `ALTER` on `dbo.spDeleteUpdate` |
  | ObsoleteUpdates | `EXECUTE` on `dbo.spGetObsoleteUpdatesToCleanup` and `dbo.spDeleteUpdate` |
  | DeclinedDeletion | `EXECUTE` on `dbo.spDeleteUpdate` |
  | SyncHistory | `DELETE` on `dbo.tbEventInstance` |
  | Reindex | none checked here; statistics need the database owner or sysadmin, which the stage checks itself (M5) |

  Stages that work through the WSUS API need the run identity to be a WSUS administrator, which
  the elevation check covers. The script never grants a permission or changes ownership.
- **Synchronization guard** (REQ-044), with `ISubscription` ([ISubscription][subscription]): the
  status is `NotProcessing`, `Running` or `Stopping` ([SynchronizationStatus][syncstatus]); a
  running synchronization is asked to stop and polled, with retries; any other status counts as a
  failed attempt. A dry run only observes.

### 5.2 Behaviour by tier

The tier is read on every run from `IsReplicaServer` and `SyncFromMicrosoftUpdate`
([repo/0005](decision-records/repo/0005-server-tier-gating.md)). The script never changes the
replica setting.

| Capability | Top tier | Autonomous downstream | Replica downstream |
|---|---|---|---|
| Backup, custom indexes, spDeleteUpdate fix, obsolete deletion, re-index, sync history | Runs | Runs | Runs; a refused obsolete-update deletion is reported as "rejected by server role" (warning) and ends that stage (to measure: what a replica refuses) |
| Built-in cleanup: non-decline options | Runs | Runs | Runs; a refusal is reported as "rejected by server role" (warning) and the other options still run (to measure: which options a replica accepts) |
| Built-in cleanup: superseded and expired declines | Runs | Runs | Suppressed: "skipped: replica" |
| Decline policies (REQ-010 to REQ-016) | Runs | Runs | Skipped: "skipped: replica" |
| Declined-update deletion (REQ-004; off by default) | Runs when enabled | Runs when enabled | Skipped |
| Stale computers: delete | Runs | Runs | Runs; a refusal is reported as "rejected by server role" (warning) and ends the stage (to measure) |
| Stale computers: move to group | Runs | Runs | Skipped: "skipped: replica"; replicas inherit groups |
| IIS log retention, artifact retention, health checks | Runs | Runs | Runs |
| Deferred approval and content pre-staging (section 11) | Runs when enabled (a top tier that only synchronizes and serves leaves it off) | Runs | Skipped: "skipped: replica"; approvals are inherited |

If the tier cannot be determined, every gated action is skipped with a warning (REQ-052).

Hierarchy ordering is achieved through each server's task start time, which deployment sets
(REQ-043, [repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)): cleanup runs from
the bottom tier up, so a downstream server's nightly run starts before its upstream's. The
`windows-wsus` role defaults to 01:00 for downstream servers and 03:00 for a top-tier server.
Declines on an autonomous downstream are local, so their order across servers does not matter; a
replica inherits its upstream's declines. A deployment that needs declines and cleanup at different
times runs them as separate `-Stage` invocations.

## 6. Stages and order

The stage catalogue (`Get-MaintenanceStageCatalog`) fixes names and order. The synchronization
guard runs first, and the synchronization restart, report and summary run last; these are not
stages.

| Order | Stage | Behind backup gate | Requirements |
|---|---|---|---|
| 1 | Backup | — | REQ-020, 021, 058 |
| 2 | CustomIndexes | yes | REQ-022 |
| 3 | DeleteUpdateFix | yes | REQ-023 |
| 4 | SupersededDecline | no | REQ-010, 016 |
| 5 | AcceleratedDecline | no | REQ-011 |
| 6 | ExpiredDecline | no | REQ-012 |
| 7 | RuleDecline | no | REQ-013, 014 |
| 8 | ContentStaging | no | LCA-04, 05, 07, 08 |
| 9 | DeferredApproval | no | LCA-01 to 04, 06 to 09 |
| 10 | DeclinedDeletion | yes | REQ-004 |
| 11 | ObsoleteUpdates | yes | REQ-001, 075 |
| 12 | BuiltInCleanup | yes | REQ-002, 003 |
| 13 | SyncHistory | yes | REQ-027 |
| 14 | StaleComputers | yes | REQ-034 |
| 15 | Reindex | no | REQ-024 |
| 16 | IisLogRetention | no | REQ-030, 031 |
| 17 | ArtifactRetention | no | REQ-032 |
| 18 | HealthChecks | no | REQ-067 |

Cadence ([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)): every enabled stage
runs on every nightly run, and each acts only on what is due, so a quiet night is short. There are
no tiers, no calendar and no catch-up. The Microsoft guidance behind this, and the timing
constraints it does impose, are cited there.

## 7. Configuration

One JSON document validated before anything changes
([repo/0003](decision-records/repo/0003-configuration-document-and-validation.md)).

- **Catalogue.** `Get-MaintenanceConfigurationRule` is the single parameter catalogue. Validation,
  default merging and the published schema
  ([reference/maintenance.schema.json](reference/maintenance.schema.json)) are all derived from
  it.
- **Reference.** [reference/configuration.md](reference/configuration.md) documents every key.
- **Defaults.** The defaults are the decided values in section 8. Only deployment-specific values
  (for example `backup.destination`) have no default; such a value is required while its feature is
  enabled.
- **Validation rules.**
  - All errors are reported together, and nothing is corrected.
  - Keys are case-sensitive.
  - Unknown keys are errors by default (`configuration.unknownKeyPolicy`).
  - A string containing PowerShell expression syntax is refused, never evaluated.
  - Credential-named keys holding text are refused as plain-text secrets.
- **Deprecation.** A deprecated key is reported with its replacement. Schema version 1 has none.
- **No run state.** Nothing is stored between runs
  ([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)); each run decides from the
  server's current state what is due.
- **Extensibility.** A new section is added by appending catalogue rules; the schema, the
  validation and the defaults follow automatically. The `approval` section (section 11.4)
  arrived this way with milestone M8.

## 8. Defaults

| Area | Defaults |
|---|---|
| Run | Budget 240 min. Database command timeout none. Connection timeout 30 s. Progress logged per item. Dry run off. Data folders that others can change are refused (`run.permissiveFolderOverride` off). |
| Sync guard | Poll 10 s. Wait 600 s per attempt. 60 s between attempts. 3 attempts. Schedule not suspended. |
| Schedule | One run per night, started by the task: role default 01:00 local on downstream servers and 03:00 local on a top-tier server, overridable per deployment. Every enabled stage runs on every run; no tiers, calendar or catch-up ([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)). |
| Backup | Native, with checksum. Compression automatic. One backup per day; a same-day backup replaces the earlier one. Keep the 7 most recent; delete files older than 7 days outside them. Free-space margin 20%. Gate required. Freshness 24 h. Destination on the dedicated backup volume. |
| Built-in cleanup | Obsolete updates, compress revisions and unneeded content on. Built-in obsolete computers off; the stale-computer stage replaces it. Superseded and expired declines on, except on replicas. 2 time-out retries. |
| Database changes | Microsoft-published changes only: custom indexes, the spDeleteUpdate fix, and the sync-history delete. Sync-history retention 90 days. |
| Declines | Superseded updates older than 90 days, approved updates included, last-level-only off. Expired declines on. Accelerated policy off. No rules enabled. Empty never-decline list. Unlimited arrival window. Evaluation language `en`. Declined-update deletion built but off. |
| Stale computers | Delete after 90 days. Downstream clients excluded. Change nothing if more than 10% or 50 computers would go. |
| Retention | IIS logs 90 days. Logs, reports and summaries 90 days and 200 files each. |
| Health | Certificate warnings at 60, 30, 14 and 7 days. Superseded-update threshold 1500. Application pool: queue length 2000, idle 0, pinging off, private and virtual memory 0, recycling 0. Processor count at least 4. Download settings: express files off, download only when approved, files stored locally (a top tier sets its own). |
| Reporting | Text and HTML files, JSON summary, Event Log. 100 items per section. No mail in release one. |
| Approval (M8) | Off by default. Updates at least one client needs; per-group delays counted from the revision creation date; deadline a configurable number of days after approval; pre-staging through an empty staging group; express files off; approve and warn when content is late; superseded updates skipped; exclusion list; licence agreements accepted; Upgrades never approved automatically. |
| Identity | `NT AUTHORITY\SYSTEM`, made SUSDB owner by configuration management. |

## 9. Release-one requirement cut

| Cut | Requirement identifiers |
|---|---|
| In release one | 001, 002, 003, 004 (built, off by default), 010, 011 (built, off by default), 012, 013 (no rules enabled), 014, 016, 020, 021, 022, 023, 024, 025, 027, 030, 031, 032, 034, 040 (the daily run of every enabled stage, and the stage list), 042–048, 050, 051 (local SQL), 052, 053, 055–058, 060, 061, 062 (folder; text and HTML), 067 (a–f), 069, 071–075, 077, 080–085 (084: no secrets consumed), 090–093, 095, 096, 097 (local SQL, three tiers, Server 2019–2025), 098, 099; lifecycle automation LCA-01 to LCA-09 (scope beyond the specification) |
| Deferred | 026, 033, 040 onboarding profile, 049, 063, 064, 065, 066, 067 (g), 068, 070, 076 |
| Superseded by one nightly run of every stage ([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)) | 015 (decline cadence and pending preview: every enabled policy acts on every run), 040 (b) (tier invocation), 041 (calendar rules) |
| Not built | 005, 028 (unsupported table edits); 054 (no external utility: SqlClient is built in); WID branches of 020, 051 and 097; remote-SQL branches of 020, 025 and 094 |

Notes on scope:

- REQ-082: the published schema covers every parameter of the features in release one. The
  parameters of deferred features are added with their milestones.
- Lifecycle automation (section 11) extends the scope beyond the specification, which lists
  update approval as out of scope; it is part of release one as milestone M8.
- REQ-092: release one's data folders are the log, report, summary and backup folders; the digest
  queue, pending-deletion list and secrets folders the requirement also names do not exist in
  release one.
- REQ-093: the components checked are the ones release one calls (section 4.1, step 6).
- REQ-096: release one sends no mail, so no report can be delivered twice, and keeps no
  deferred-deletion list; the other properties hold as built (section 10, M10).

## 10. Milestones and status

| # | Milestone | Requirements | Status |
|---|---|---|---|
| M0 | Scaffold: layout, build, CI and release workflows, exit codes, error records, run result | 046, 073, 093 | **Done** (gate green, 2026-10-06) |
| M1 | Configuration and validation: catalogue, reader, validator, cross-field rules, overrides, effective configuration, published schema, `-ValidateOnly` | 080–085, 099; 041 and 092 rules | **Done** (gate green, 2026-10-06) |
| M2 | Run control: stage plan and ordering, lock, elevation, stage error boundary and budget, status resolution, dry-run plumbing | 040, 042, 043, 045, 047, 048, 050, 055, 077, 096, 098 | **Done** (gate green, 2026-10-06; reworked for one daily run, 2026-10-07) |
| M3 | Reporting and observability: report, text and HTML renderers, summary and schema, run log with redaction, events, failure reports | 060–062, 069, 071, 072, 074, 075, 091 | **Done** (gate green, 2026-10-07) |
| M4 | Discovery and preconditions: seams, environment and tier, permissions, sync guard and restart | 025, 044, 051–053, 090, 095, 097 | **Done** (gate green, 2026-10-07) |
| M5 | SUSDB upkeep: indexes, procedure fix, obsolete deletion, re-index and statistics, sync history, backup, retention, gate, free space | 001, 020–024, 027, 056–058, 075 | **Done** (gate green, 2026-10-07) |
| M6 | WSUS API cleanup and stale computers | 002, 003, 034, 057 | **Done** (gate green, 2026-10-07) |
| M7 | Decline engine | 004, 010–016 | **Done** (gate green, 2026-10-07) |
| M8 | Lifecycle automation: needed-update approval with per-group delays and deadlines, content pre-staging, late-content warning, exclusions, licences | LCA-01 to LCA-09 (section 11) | **Done** (gate green, 2026-10-07) |
| M9 | Housekeeping and health | 030–032, 067 | **Done** (gate green, 2026-10-07) |
| M10 | Hardening and release readiness: folder protection, dependency check, interruption tests, ADRs, schema release assets | 048, 092, 093, 096, 098 | **Done** (gate green, 2026-10-07) |
| M11 | Runner lane: SQL Server Express and WSUS on the hosted Windows runner (spike first) | live evidence (section 12, lane A) | Planned |

Each milestone ends with the local gate green. M0 to M10 are release one as built; M11 and the
`windows-wsus` integration pieces I1 to I5 (section 3.5) produce the live evidence that section 12
lists. No release has been tagged.

What M0 and M1 delivered:

- **Functions.** `MaintenanceExitCode`, `New-ErrorRecord`, `New-MaintenanceRunResult`,
  `Get-MaintenanceStageCatalog`, `Get-MaintenanceConfigurationRule`,
  `Get-MaintenanceDefaultConfigurationPath`, `Read-MaintenanceConfiguration`,
  `Get-MaintenanceDocumentValue`, the validators (`Test-MaintenanceConfiguration` and helpers),
  `ConvertTo-MaintenanceEffectiveConfiguration`, `Resolve-MaintenanceOverride`,
  `ConvertTo-MaintenanceConfigurationSchema`, and the orchestrator with `-ValidateOnly`.
- **Run behaviour at the time.** A run without `-ValidateOnly` validated and completed with no
  stages; M2 added the run itself.

What M2 delivered: `Get-MaintenanceTime`, `Test-MaintenanceElevation`, `New-MaintenanceLock`,
`Enter-MaintenanceLock`, `Exit-MaintenanceLock`, `Resolve-MaintenancePath`,
`Test-MaintenanceStageEnabled`, `Get-MaintenanceStagePlan`, `Get-MaintenanceStageHandler`,
`Invoke-MaintenanceStage`, `New-MaintenanceStageOutcome`, `New-MaintenanceNotice`,
`Test-MaintenanceBudget`, `Resolve-MaintenanceRunStatus`, `Invoke-MaintenanceRun`, and the
orchestrator wiring. From then on a run validated, checked elevation, took the lock, planned every
enabled stage, and recorded each as "not available in this release" until the stage milestones
registered handlers (every stage has one since M9). The first M2 build also had a tier calendar with a run-state file; the move to one nightly
run of every stage removed it
([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)).

What M3 delivered: `New-MaintenanceRunId`, `Register-MaintenanceSecret`,
`Protect-MaintenanceText`, `Get-MaintenancePropertyValue`, `Initialize-MaintenanceFolder`,
`Resolve-MaintenanceOutputFolder`, `Get-MaintenanceOutputSetting`, `New-MaintenanceLog`,
`Write-MaintenanceLog`, `Write-MaintenanceProgress`, `New-MaintenanceEventChannel`,
`Test-MaintenanceEventSource`, `Write-MaintenanceEventEntry`, `Write-MaintenanceEvent`,
`New-MaintenanceRunRecord`, `New-MaintenanceReport`, `ConvertTo-MaintenanceReportText`,
`ConvertTo-MaintenanceReportHtml`, `Save-MaintenanceReport`, `Write-MaintenanceSummary`,
`Open-MaintenanceRunOutput`, `Publish-MaintenanceRunOutput`, `Stop-MaintenanceRun`,
`docs/reference/summary.schema.json`, and the orchestrator wiring. Notices now carry an optional
link and suggested command, stage outcomes carry their items, and the stage loop logs every
stage. The gate proves: every stage appears exactly once with status and duration in both
renderings; notices are ordered by severity in both; a planted secret is absent from the log,
both reports, the summary and every event; the summary validates against its schema and its
counts match the report; a stage error changes the report, the summary, the events and the exit
code together; each precondition failure saves a failure report with its exit code; a broken
document reports to the built-in default folder; and an unwritable log folder aborts with
`PreconditionFailed` and an event.

What M4 delivered: the seams `Get-WsusSetupValue`, `Get-WsusUpdateServer`, `New-SqlConnection`,
`Get-MaintenanceOperatingSystem`, `Get-MaintenanceIdentity` and `Wait-MaintenanceInterval`; and
`Invoke-SusdbCommand`, `New-SusdbMessageHandler`, `Get-WsusEnvironment`,
`Connect-MaintenanceServer`, `Disconnect-MaintenanceServer`, `Get-WsusServerRole`,
`Test-SusdbPermission`, `Invoke-SynchronizationGuard` and `Restore-Synchronization`, with the
orchestrator, the stage plan (tier and permission gating) and the report header wired to them.
The gate proves: each database class and tier from stand-in registry values and API objects;
Windows Internal Database, remote SQL Server, Windows Server 2016 and a server without WSUS stop
with exit code 3 and a failure report; a failed WSUS or SUSDB connection does the same; REQ-044
(a), (b) and (c) with a stand-in clock, including a restart after an unexpected failure; a
missing backup right skips the backup with a notice before any stage starts; an unrecognized
synchronization status counts as a failed attempt; a replica skips every decline stage with
"skipped: replica".

What M5 delivered: the stage functions `Backup-Susdb`, `Set-SusdbCustomIndex`,
`Set-DeleteUpdateProcedureFix`, `Invoke-ObsoleteUpdateCleanup`, `Remove-SyncHistory` and
`Invoke-SusdbIndexMaintenance`, registered in `Get-MaintenanceStageHandler`; the helpers
`ConvertTo-DeleteUpdateFix`, `Get-SusdbIndexAction`, `Remove-BackupFile`, `Test-BackupGate`,
`New-MaintenanceStageResult`, `Get-SusdbConnection` and `ConvertTo-SqlIdentifier`; the seam
`Get-BackupDestinationSpace`; the backup gate in `Invoke-MaintenanceRun`; and the
`-RemoveCustomIndexes` option. The stages:

- **Backup** (REQ-020, 021, 058). `BACKUP DATABASE` to
  `backup.destination\<database>_<yyyyMMdd>.bak` `WITH CHECKSUM`, `INIT` when `backup.sameDay` is
  `Replace` and `NOINIT` when it is `Append`, under the backup-set name
  `<database> full backup <date> <time>`. Compression follows `backup.compression`: `Auto`
  compresses on the Enterprise, Standard and Developer editions, which support it ([backup
  compression][compression]), and not otherwise. The folder is created when missing (protected,
  since M10). Before the
  backup, its size is estimated from the database's reserved pages (`sys.dm_db_partition_stats`),
  and the destination must have that much free space plus `backup.freeSpaceMarginPercent`;
  otherwise the backup is skipped with a High notice. When the free space cannot be read, the
  backup is attempted with an Information notice. A failed backup is a stage error with a High
  notice. Only after a successful backup does the retention run, over the top-level files named
  `<database>_<yyyyMMdd>.bak`: the `backup.minimumKept` newest are always kept and, of the others,
  each whose name date is `backup.maximumAgeDays` or more days old is deleted; when one limit is
  zero the other applies alone, and when both are zero every file is kept with an Information
  notice. Other files and sub-folders are never touched; a file that cannot be deleted is a
  Warning notice.
- **Backup gate** (REQ-056). Evaluated once, before the first stage whose catalogue entry has
  `AltersDatabase`. It is satisfied by a backup this run made (in a dry run, one it would make),
  or else by a full backup of the database recorded in `msdb.dbo.backupset` that finished within
  `backup.freshnessHours`. When `backup.gate` is `Required` and it is not satisfied, each such
  stage is skipped with "skipped: no recent backup" and one High notice is raised; `Advisory` runs
  them with a Warning notice; `Off` skips the evaluation. The run log records the outcome.
- **CustomIndexes** (REQ-022). On every run, checks `nclLocalizedPropertyID` on
  `dbo.tbLocalizedPropertyForRevision (LocalizedPropertyID)`, `nclSupercededUpdateID` on
  `dbo.tbRevisionSupersedesUpdate (SupersededUpdateID)` ([guide], "Create custom indexes") and
  each `customIndexes.additional` entry. A missing index is created as a non-clustered index and
  tagged with the extended property `CreatedBy = Invoke-WsusMaintenance` (since M10, both in one
  transaction); an existing one is
  reported as already present and left alone. With `-RemoveCustomIndexes` only tagged indexes are
  dropped; an untagged index of the same name is kept and reported. A failure is a Warning notice
  per index.
- **DeleteUpdateFix** (REQ-023). Reads `OBJECT_DEFINITION` of `dbo.spDeleteUpdate`. With the
  primary key already on the `@revisionList` table variable ([spDeleteUpdate fix][spdelete]) the
  stage reports "already applied" and changes nothing. With exactly one such declaration lacking
  it, and a `CREATE PROCEDURE` header, it logs the definition, runs the live text with two changes
  only (`PRIMARY KEY` added to that declaration, `CREATE` turned into `ALTER`), logs the new
  definition and verifies it. Any other text is left untouched with a Warning notice; a failure to
  read or alter is a Warning notice, and obsolete-update deletion still runs.
- **ObsoleteUpdates** (REQ-001, 057, 075). `EXEC dbo.spGetObsoleteUpdatesToCleanup`, then
  `EXEC dbo.spDeleteUpdate @localUpdateID` one update at a time ([guide]), with the time budget
  checked before each deletion and a progress entry per deletion (or per
  `run.progressBatchSize`) giving position, total, identifier and duration.
  `obsoleteUpdates.maxDeletions` caps the deletions per run, with a Warning notice when reached. A
  failed deletion is logged with its identifier and the error, and the next one proceeds; the
  stage then ends in error. On a replica the first refusal ends the stage with "rejected by server
  role" (warning).
- **SyncHistory** (REQ-027). Deletes the `dbo.tbEventInstance` records of event namespace 2 with
  event identifiers 381, 382, 384, 386, 387 and 389 ([manual maintenance][maintenance], "Clean up
  the synchronization history") whose `TimeAtServer` is more than `syncHistory.retentionDays` days
  before the current UTC time, in batches of 10,000 with the time budget checked between batches;
  zero days removes every such record. Without a `TimeAtServer` column the stage deletes nothing
  and raises a Warning notice.
- **Reindex** (REQ-024). Selects indexes from `sys.dm_db_index_physical_stats` in `SAMPLED`
  mode with the thresholds of Microsoft's re-index script for SUSDB ([reindex]): page density below
  85% where at least one page could be saved, fragmentation above 15% on more than 50 pages, or
  above 80% on more than 10 pages. Heaps are left out (the published script cannot act on them),
  and an index with several qualifying allocation units or partitions is handled once. Each index
  is reorganized (density 75–85% with a fill factor set, or fragmentation below 30%), rebuilt with
  fill factor 90 (at least 5,000 rows and no fill factor set) or rebuilt, with the budget checked
  and progress logged per index. Pages before and after (`sys.dm_db_partition_stats`) give the
  pages freed. `sp_updatestats` then runs, but only when no index failed, the budget did not stop
  the stage, and the run identity is the database owner or a sysadmin; otherwise a Warning notice
  names the login and the `ALTER AUTHORIZATION` command that fixes it.
- **Dry run.** Each stage reads `Context.DryRun` and sends SUSDB nothing but reads (`SELECT` and
  `spGetObsoleteUpdatesToCleanup`); the backup stage creates no folder and deletes no file, and
  its retention preview lists the files it would delete.
- **T-SQL provenance.** Every T-SQL statement is written for this script; it follows the logic
  Microsoft publishes, and the code names the source next to it. No Microsoft script is copied.
  The selection of synchronization-history records comes from Microsoft's manual-maintenance
  article, whose code samples are published under the MIT License; the code carries the article's
  address and that notice.
- **Permissions.** Statistics are no longer gated by the permission check: a non-owner still
  defragments, and the stage raises its own notice (REQ-024). `Test-SusdbPermission` reports the
  login name and whether it is the owner or a sysadmin.

The gate proves each stage against a stand-in SUSDB that answers the stage's queries
(`tests/Helpers/MaintenanceFakes.ps1`): created and already-present indexes, and removal of only
tagged ones; the fix applied with the before and after text, already applied, and unexpected text
left untouched; N deletions with N progress entries, a cap of M deleting exactly M, a failure that
carries on, a replica refusal and a budget stop; every re-index action and threshold, and
statistics skipped for a non-owner with the corrective command; batched sync-history deletion and
the missing-column warning; dated backups with each compression and same-day option, the
free-space skip, a failed backup, and the retention over mixed ages, a foreign file and a
sub-folder; the gate closed, open and advisory; and a whole dry run that sends SUSDB only reads.

What M6 delivered: the stage functions `Invoke-WsusBuiltInCleanup` and
`Invoke-StaleComputerCleanup`, registered in `Get-MaintenanceStageHandler`; the helpers
`Get-WsusConnection`, `Test-MaintenanceTimeout`, `ConvertTo-MaintenanceByteText` and
`ConvertTo-StaleComputerText`; the seam `New-WsusAdministrationObject`; and tier gating of
stale-computer moves in `Get-MaintenanceStagePlan`. The stages:

- **BuiltInCleanup** (REQ-002, 003). The WSUS cleanup manager (`IUpdateServer.GetCleanupManager`,
  `PerformCleanup`) runs each enabled option in a cleanup scope of its own ([cleanup scope][scope]),
  in this order: superseded-update decline, expired-update decline, obsolete updates, obsolete
  update revisions (`CompressUpdates`), obsolete computers (off by default; the stale-computer
  stage replaces it) and unneeded content files. Each option is isolated: a time-out (a
  `TimeoutException`, a web request with the `Timeout` status, a SQL Server command time-out, or a
  message saying the operation timed out, at any depth) is retried up to
  `builtInCleanup.timeoutRetries` times while the time budget allows; any other failure is not
  retried. A failed option is recorded with its attempts and message and an Error notice, and the
  next option still runs; the stage then ends in error. The count reported for an option is the
  one counter of the cleanup results that belongs to it, so with one option enabled only that
  counter can be non-zero; disk space freed is shown in readable units. The two decline options
  are suppressed with "skipped: replica" on a replica and "skipped: server role unknown" when the
  role is unknown; on a replica any other refusal is reported as "rejected by server role" with a
  Warning notice. The budget is checked before each option, and options it stops from starting
  are named in a Warning notice. When unneeded-content cleanup runs, the stage message says that
  it also deletes update files imported manually from the Microsoft Update Catalog.
- **StaleComputers** (REQ-034, 057). Selects the computers whose last synchronization
  (`IComputerTarget.LastSyncTime`, kept in UTC) is more than `staleComputers.thresholdDays` days
  old through a `ComputerTargetScope` with `ToLastSyncTime`, leaving out clients of downstream
  servers unless `staleComputers.includeDownstream` is set, as Microsoft's stale-computer sample
  does ([stale computers][stale]). The total for the share is
  `GetComputerTargetCount` over the same population. When more computers are selected than
  `staleComputers.guardCount`, or a larger share than `staleComputers.guardPercent`, nothing is
  changed, the selection is listed as "not changed (guard)" and a High notice is raised; with
  `staleComputers.override` the selection is processed with a Warning notice. Each selected
  computer is deleted (`IComputerTarget.Delete`) or, with `action` `Move`, added to the existing
  group `staleComputers.targetGroup` (`IComputerTargetGroup.AddComputerTarget`, which Microsoft
  documents as taking a computer out of Unassigned Computers); computers already in that group are
  left out, and a missing group is an error that changes nothing (the group is never created).
  The budget is checked and progress logged per computer; a failed computer is recorded and the
  next proceeds, and the stage then ends in error; on a replica the first refusal ends the stage
  with "rejected by server role". The items list each computer, sorted by name, with its last
  synchronization time, operating system and client version. Moving is skipped by the stage plan
  on a replica ("skipped: replica") and when the role is unknown, because a replica inherits its
  groups.
- **Dry run.** The built-in cleanup calls nothing and lists the options that would run; the
  stale-computer stage reads but changes nothing, and its list is marked as a simulation.

The gate proves: each option alone in its own scope and in order, with only its own counter taken
from results that report every counter; only the configured options; decline options suppressed
on a replica and with an unknown role; exactly retry count plus one attempts for a time-out,
success on a retry, no retry for other failures; a replica refusal; a budget stop; stale
computers on each side of the threshold, never-synchronized and downstream computers; both
guards, the override, moves that leave out existing members, a missing group, a failed computer,
a replica refusal, a budget stop; and a whole dry run that sends SUSDB and WSUS only reads.

What M7 delivered: the stage functions `Invoke-SupersededDecline`, `Invoke-AcceleratedDecline`,
`Invoke-ExpiredDecline`, `Invoke-RuleDecline` and `Remove-DeclinedUpdate`, registered in
`Get-MaintenanceStageHandler`; and the helpers `Get-WsusUpdateRecord`, `ConvertTo-DeclineRecord`,
`Get-DeclineCatalog`, `Select-SupersededUpdate`, `Invoke-SupersededPolicy`,
`Invoke-DeclineSelection`, `New-DeclineUnavailableResult`, `Test-DeclineRuleCondition`,
`Test-UpdateIdentity` and `ConvertTo-DeclineItemText`. The behaviour:

- **Evaluation scope and language** (REQ-014, 016). The first decline stage of a run retrieves
  the updates once (`IUpdateServer.GetUpdates` with an `UpdateScope` whose approval states are
  not approved, latest revision approved and stale approvals, so declined updates are left out,
  as Microsoft advises against `Any` ([ApprovedStates][approvedstates])), limited to
  `declines.arrivalWindowDays` when set. Before retrieving, it sets the connection's preferred
  culture to `declines.evaluationLanguage` (default `en`) and logs it; it reads every attribute
  the policies use, then restores the previous preference ([PreferredCulture][culture]). The
  connection step no longer sets the culture. Every decline stage of the run evaluates this
  list, and an update one policy declines (or, in a dry run, would decline) is not counted again
  by a later one, so a repeat run declines nothing. Each stage reports the number of updates
  evaluated.
- **Retrieval failure** (REQ-016). When the list cannot be retrieved or the retrieval times out,
  no decline policy acts: each decline stage ends in error with zero declines, and the first one
  raises one Error notice that names memory exhaustion of the WsusPool application pool in IIS
  as a common cause. The other stages still run.
- **SupersededDecline** (REQ-010). Every superseded update that is not declined and whose
  revision `CreationDate` is more than `declines.superseded.ageDays` days (default 90) before the
  run start (in UTC) is declined (`IUpdate.Decline`), as Microsoft's superseded-update script
  selects them ([decline superseded][declinesuperseded]). Approved updates are eligible
  (`includeApproved`, default on); `lastLevelOnly` (default off) keeps updates that supersede
  others. The counts include the superseded updates still inside the threshold.
- **AcceleratedDecline** (REQ-011). The same selection, limited to
  `declines.accelerated.classifications` with its own `ageDays`; built and off by default.
- **ExpiredDecline** (REQ-012). Every update whose publication state is `Expired` and that is not
  declined.
- **RuleDecline** (REQ-013). Each enabled rule of `declines.rules`, in order, whose group in
  `declines.groups` is not disabled, declines the updates its condition matches: `all`, `any` and
  `not` combine text tests (`Contains`, `Equals`, `Like`, `Match`, ignoring case) on the title,
  legacy name, classification, product and product family titles and Knowledge Base numbers,
  date tests (`OlderThanDays`, `NewerThanDays`) on the creation and arrival dates, and the update
  source. The items give per rule its name and the numbers matched and declined, then the updates.
  No rule ships enabled. When the evaluation language cannot be set, rule-based declines are
  skipped with an Error notice while the age- and state-based policies still run. A rule that
  cannot be evaluated is reported and the next rule runs.
- **Never-decline list.** `declines.neverDecline` (Knowledge Base numbers or update GUIDs)
  overrides every policy and rule; the updates it saves are counted as protected.
- **Declines.** One update at a time, with the time budget checked and progress logged per
  update; a failed decline is listed with its error, the next one proceeds and the stage ends in
  error. The items list each update with its title, Knowledge Base references and creation date.
- **Pending preview.** A dry run declines nothing; each policy lists its updates as
  "pending: ..." and its message starts with "pending: N". This is how the pending declines of a
  policy are seen, since every enabled policy acts on every run
  ([repo/0006](decision-records/repo/0006-nightly-run-of-every-stage.md)).
- **DeclinedDeletion** (REQ-004). Built and off by default. It retrieves the declined updates and
  deletes each with `IUpdateServer.DeleteUpdate` ([DeleteUpdate][deleteupdate]), except updates in
  `declinedDeletion.protected`, in `excludedClassifications` or, when `includedClassifications`
  is not empty, outside it. The counts give found, protected, excluded by classification, deleted
  and failed; the items list each deleted update. A failed deletion is listed and the next one
  proceeds; any failure ends the stage in error. When classifications filter the deletion and
  the evaluation language cannot be set, nothing is deleted. The stage is behind the backup gate.
- **Tier gating.** Unchanged from M4: on a replica every decline stage and the deletion are
  skipped with "skipped: replica", and with an unknown role with "skipped: server role unknown".

The gate proves: superseded updates on both sides of the threshold, last-level-only, approved
updates kept when not eligible, the never-decline list by number and identifier, a repeat run
that declines nothing, the pending preview, a failed decline, a budget stop; the accelerated
policy limited to its classifications; expired declines; each rule operator and field, `all`,
`any`, `not`, a disabled group, the never-decline list, zero new declines for updates already
declined in the run, a rule that cannot be evaluated; the language set, restored and logged, and
rules skipped while age-based declines run when it cannot be set; one retrieval per run; a
retrieval time-out with zero declines and one Error notice; the arrival window; deletion with
protected and classification filters, a second run that deletes nothing, failures, the budget,
dry run and the language guard; and deletion skipped by the backup gate.

What M8 delivered: the `approval` configuration section (catalogue, schema, generated reference,
validation of `approval.groups` entries, and the cross-field rules); the stages `ContentStaging`
(`Invoke-ContentStaging`) and `DeferredApproval` (`Invoke-DeferredApproval`) after the decline
stages and before declined-update deletion; the helpers `Get-ApprovalCatalog`,
`Select-ApprovalCandidate`, `Test-UpdateApproval`, `Add-UpdateApproval` and
`New-ApprovalUnavailableResult`; the late-content event (`eventLog.eventIds.lateContent`, 1400);
the event channel in the stage context; and the listed items of every stage in the summary. The
behaviour (section 11.2):

- **Gating.** Both stages are off by default (`approval.enabled`), and a top tier that only
  synchronizes and serves leaves them off. On a replica they are skipped with "skipped: replica"
  ("If your WSUS server is running in replica mode, you won't be able to approve updates" [ops]),
  and with an unknown role with "skipped: server role unknown".
- **What the stages read** (`Get-ApprovalCatalog`, once per run). The undeclined updates: the
  decline stages' list when they read every arrival, less what they declined in the run;
  otherwise a retrieval of its own across every arrival, in the evaluation language. How many
  clients need each update: `IUpdateServer.GetSummariesPerUpdate`, counting the clients whose
  state is not installed, downloaded, installed pending a restart, or failed, which is how
  Microsoft defines a needed update ([needed]). The approvals of the approved updates
  (`IUpdateServer.GetUpdateApprovals`), indexed by update identifier and revision, so an approval
  of an earlier revision does not count for a re-released one (LCA-01). The computer groups by
  name. When any of this cannot be read, or the evaluation language cannot be set (the Upgrades
  classification could not be recognised reliably), neither stage changes anything and one Error
  notice says why.
- **Candidates** (`Select-ApprovalCandidate`, LCA-04, 07, 08). Updates that at least one client
  needs and that are not expired (an expired update can only be approved for removal
  ([Approve][approve])), except the Upgrades classification, `approval.excludedClassifications`
  and `approval.neverApprove` (Knowledge Base numbers or update GUIDs). A superseded update is
  left out while an update that supersedes it
  (`GetRelatedUpdates(UpdatesThatSupersedeThisUpdate)`) is approved or is itself a candidate.
  WSUS infrastructure updates come first ("you can't approve other updates to client systems
  until the WSUS update is approved" [ops]); the rest follow by revision creation date.
- **ContentStaging** (LCA-05). Each candidate not approved for install for any group, and not yet
  staged, is approved for install (`IUpdate.Approve`) for the group `approval.staging.groupName`:
  with deferred downloads "an update is downloaded only after it's approved" ([plan]), so its
  files download at once while no client is offered it. The group must exist (it is never
  created) and must have no members, subgroups included; otherwise nothing is staged and the
  stage ends in error. Once an update is approved for a configured group and its state is
  `Ready` (approved, with all files available ([UpdateState][updatestate])), its staging approval
  is removed (`IUpdateApproval.Delete`). The server's download settings are checked by the health
  checks (M9) against this deployment's expected values ([IUpdateServerConfiguration][config]).
- **DeferredApproval** (LCA-01, 02, 03, 06). For each candidate and each group in
  `approval.groups`, in order, the update is approved for install once `delayDays` have passed
  since its revision `CreationDate`, unless that revision is already approved for the group. A
  group that does not exist is reported with an Error notice and never created; the other groups
  are still approved for. The install deadline is `deadlineDays` after the approval, passed in
  UTC as the API requires ([Approve][approve]); an update that can request user input
  (`InstallationBehavior.CanRequestUserInput` ([views])) is approved without one, because "you
  can't set a deadline for automatic installation for an update if user input is required"
  ([ops]), and so is a group without `deadlineDays`.
- **Licence agreements** (LCA-08). An update that requires one has it accepted
  (`IUpdate.AcceptLicenseAgreement`) before it is staged or approved, since approval fails until
  it is ([Approve][approve]); with `approval.acceptLicenseAgreements` off, such an update is left
  unapproved and listed.
- **Late content** (LCA-06). An update whose state is not `Ready` on its approval date is
  approved on schedule; one Warning notice and one late-content event (Warning, 1400) name each
  such approval. Clients wait for the files.
- **Reporting** (LCA-09). Every staging and approval action is an item of its stage, with its
  group, delay, deadline and content state, and the summary now carries each stage's listed
  items as well as its counts. A dry run changes nothing and lists the stagings, removals and
  approvals it would make as pending. A repeat run stages and approves nothing new, because the
  approvals already made are read back.
- **Failures.** A failed staging or approval is listed with its error, the next one proceeds, and
  the stage ends in error. The time budget is checked before each action.

The gate proves: approval per group after each delay with deadlines in UTC, infrastructure updates
first, user input without a deadline, licences accepted or the update left unapproved, Upgrades,
the never-approve list, expired, unneeded and superseded updates left out, supersedence that
cannot be checked, a re-released revision approved again, late content with a notice and an
event, a missing group, failures, the budget, dry run, the unreadable catalog and the language
failure with one notice for both stages; staging into the empty group, updates approved elsewhere
left out, staging approvals removed once local and approved, a missing or populated staging group,
each download-setting drift, unreadable settings, licences, dry run, failures and the budget;
reuse of the decline list, a separate list with an arrival window; the configuration rules; and a
whole run that stages and approves, lists every action in the report and the summary, and repeats
nothing.

What M9 delivered: the stages `IisLogRetention` (`Remove-IisLogFile`), `ArtifactRetention`
(`Remove-MaintenanceArtifact`) and `HealthChecks` (`Invoke-HealthCheck`), so every stage of the
catalogue now has a handler; the website detection `Find-WsusWebSite`; the checks
`Test-WsusTlsHealth`, `Test-CertificateHealth`, `Test-StrongCryptoHealth`, `Test-AppPoolHealth`,
`Test-DownloadSettingHealth`, `Test-SupersededCountHealth`, `Test-ProcessorHealth` and
`Test-VirtualMachine`; the read-only seams `Get-IisConfiguration`, `Get-MaintenanceRegistryKey`,
`Get-MaintenanceCertificate` and `Get-MaintenanceMachineInfo`; and the configuration keys
`health.appPool.virtualMemoryLimitKb` and `health.downloadSettings.*`. The behaviour:

- **WSUS website** (REQ-031). Read from `applicationHost.config`, never by its English display
  name: `iisLogs.siteName` when set; otherwise the site whose root physical path lies under the
  installation folder WSUS setup recorded (`TargetDir`); otherwise the site that hosts the
  remote-administration application `/ApiRemoting30` (WSUS installed on the default website);
  otherwise the default name `WSUS Administration`, with a Warning notice. A renamed site is
  therefore still found. Two matches are ambiguous and an error. The log records the site, its
  identifier and how it was found.
- **IisLogRetention** (REQ-030). Deletes the files with the `.log` extension directly in the
  site's IIS log folder (its own log directory, else the site defaults, else the IIS default,
  plus `W3SVC<id>`) or in `iisLogs.folder`, last written more than `iisLogs.maxAgeDays` days
  (default 90) before the run start, as Microsoft describes for managing IIS log storage
  ([IIS logs][iislogs]). Other files and sub-folders are never touched; zero days keeps every file.
  Without the IIS HTTP logging feature the stage does nothing and suggests turning it off; a site
  or folder that cannot be found, or an ambiguous site, deletes nothing and is an error. A file
  that cannot be deleted is a warning and is retried on the next run.
- **ArtifactRetention** (REQ-032). For run logs, reports and summaries, looks directly in the
  configured folder and the built-in default folder for files named `WsusMaintenance-<run
  identifier>` with that kind's extension, groups them by run (a run's text and HTML report are
  one report), and deletes the runs older than `retention.<kind>.maxAgeDays` (90) by the time in
  their identifier, or beyond the `retention.<kind>.maxCount` (200) newest. The current run's log
  and runs dated after the run start are never deleted. Diagnostic bundles and digest-queue items
  do not exist in release one.
- **HealthChecks** (REQ-067 a to f). Read-only: nothing is ever changed. Each enabled check adds
  one line to the items and each deviation raises its own notice with the current and expected
  values:
  - (a) TLS: WSUS setup's `UsingSSL` value; Microsoft recommends TLS as the first step after
    installation ([best practices][bestpractices]).
  - (b) Certificate expiry: for each https port of the WSUS website, the certificate HTTP.sys
    binds to it (`SslBindingInfo` and `SslSniBindingInfo` registrations) is found in its
    local-machine store; expired is an Error notice, within the smallest tier (7 days) a High
    notice, within another tier (60, 30, 14) a Warning notice; a port without a bound
    certificate, or one missing from its store, a Warning notice.
  - (c) Strong cryptography: `SchUseStrongCrypto` and `SystemDefaultTlsVersions` under
    `SOFTWARE\Microsoft\.NETFramework\v4.0.30319` in the 64-bit and 32-bit registry views must be
    1 ([.NET TLS][dotnettls]); one notice lists every value that is not.
  - (d) Application pool: the pool of the WSUS site's root application, read with the pool
    defaults and the IIS defaults as fallbacks, compared with Microsoft's WsusPool
    recommendations: queue length 2000, idle time-out 0, pinging off, private and virtual memory
    limits 0, regular recycling 0 ([best practices][bestpractices]); one notice per setting that
    differs.
  - Download settings: express installation files, download only when approved and local file
    storage, against `health.downloadSettings`, which holds this deployment's expectations (a
    downstream that stages expects downloads only when approved; a top tier that serves every
    update sets `downloadOnlyWhenApproved` to false); one notice per setting that differs. This
    moved here from content staging, which keeps its refusals.
  - (e) Superseded updates that are not declined, counted with the maintenance guide's query,
    above 1500 ([guide]).
  - (f) Logical processors on a virtual machine (recognised from the manufacturer and model),
    below 4.

  A check that fails raises one notice for itself and the others still run; when the IIS
  configuration or the WSUS website cannot be read, one notice names the checks that need it.

The gate proves: site detection by path (renamed site), by the remote-administration application,
by name, the default-name fallback, ambiguity and absence, and the three sources of the log
folder; IIS log retention over old and new logs, a non-log file, a look-alike extension and a
sub-folder, the folder override, zero days, dry run, the missing logging feature, the error
paths and the budget; artifact retention by age and count, reports grouped by run, foreign files
and folders untouched, both folders, the current and future-dated runs kept, and dry run; a healthy
server with no notice; each misconfiguration raising exactly its own notice; pool values from the
defaults; per-deployment download expectations; disabled checks; a failing check; and the
unreadable IIS configuration and missing site.

What M10 delivered: folder protection (`Test-MaintenancePathProtection`,
`Get-MaintenanceTrustedSid`, `Test-MaintenanceInstallation`, `ConvertTo-MaintenanceAccountName`,
`ConvertTo-SqlServiceAccount`, and protection in `Initialize-MaintenanceFolder`,
`Resolve-MaintenanceOutputFolder`, `New-MaintenanceLog`, `Open-MaintenanceRunOutput` and
`Backup-Susdb`); the dependency check (`Test-MaintenanceDependency`) and unavailable stages in the
plan; the top-level handling of unexpected errors; option handling for `powershell.exe -File`
(`ConvertTo-MaintenanceList`, `ConvertTo-MaintenanceCanonicalValue`); the seams listed in section
3.3; the schemas as release assets; and the decision records
[repo/0007](decision-records/repo/0007-protected-folders-and-runtime-integrity.md) to
[repo/0010](decision-records/repo/0010-destructive-actions-opt-in.md). The behaviour:

- **Folder protection** (REQ-092, section 4.5). Every folder the run creates, and every missing
  level above it, is created in one step with a protected access control list for SYSTEM,
  Administrators and the run identity (and, for the backup folder, the SQL Server per-service
  account, `NT SERVICE\MSSQLSERVER` or `NT SERVICE\MSSQL$<instance>`, which writes the file), and
  read back. An existing folder is never changed. A principal outside the trusted set counts as
  able to change a file or folder when it is the owner or when an allow rule, inherited or not,
  gives it write data, append data, write attributes or extended attributes, delete, delete child
  items, change permissions, take ownership, or generic write or all; service identities
  (`S-1-5-80-`), `CREATOR OWNER` and `OWNER RIGHTS` are trusted. A refused folder is never written
  to (not even the write probe). `run.permissiveFolderOverride`, which M1 added to the catalogue,
  now takes effect: such folders are used with a Warning notice.
- **Installation check** (REQ-093). After the elevation check, the folder of the running script
  and the script file are checked the same way; a writer outside the trusted set, or an access
  control list that cannot be read, stops the run with `PreconditionFailed` at "installation
  protection check". There is no override.
- **Dependency check** (REQ-093). After environment discovery the run logs one line naming each
  component and whether it is present: the WSUS administration API, the SQL Server client and the
  IIS configuration. The first two are needed by the whole run, so a missing one stops it with
  `PreconditionFailed` at "dependency check"; a missing IIS configuration makes `IisLogRetention`
  unavailable (unless `iisLogs.folder` is set): the plan skips it with "unavailable: missing the
  IIS configuration (applicationHost.config)" and the run raises one Warning notice. A test of the
  source refuses any command or API that downloads, installs, changes file trust or loads code
  from a file, and any write to the script's own path.
- **Unexpected errors** (REQ-098). The run body after opening the outputs is wrapped: an error
  that is not one of the coded stops is turned into `Stop-MaintenanceRun` with `StageError`, after
  the inner `Finally` has restarted the synchronization (recording what it did in the report
  header), closed the connection and released the lock. The run tracks the point it reached
  (for example "stage run" or "saving of the report and summary") for the failure report. The
  summary's failure kind gains `StageError`, and its event is the run-failed event (1003).
- **Re-run safety** (REQ-096). The custom index and its tag are created in one batch under
  `SET XACT_ABORT ON` and one transaction, so an interrupted run never leaves an untagged index
  that the removal action would not recognise. Every other change was already one atomic call or
  statement ([repo/0008](decision-records/repo/0008-failure-handling-and-rerun-safety.md)).
  Reports are written per run identifier, so a rerun never repeats a delivery (release one sends
  no mail), and release one keeps no deferred-deletion list.
- **Time budget** (REQ-048). Unchanged since M2 and M5: no stage starts after the deadline,
  item-by-item stages stop at their next item boundary, the synchronization restart and the
  report still happen, and the stages that did not run are listed with a Warning notice.
- **Options under `powershell.exe -File`**, which passes each argument as one literal string:
  `-Stage` and `-ReportFormat` accept comma-separated lists, option values are matched without
  regard to case, and an unknown `-ReportFormat` or `-Verbosity` value is a configuration error
  (exit code 4) instead of a parameter-binding failure (exit code 1).
- **Release assets.** The release workflow copies both schemas next to the sealed script, adds
  them to the provenance subjects and publishes them with the release; the release job checks them
  against those subjects first ([repo/0009](decision-records/repo/0009-release-assets-and-schemas.md)).

The gate proves: the trusted and untrusted principals and each write right; protected creation of
every missing level with the granted identities; a refused folder left untouched and unwritten;
the override with its warning; a created folder that does not verify; the report folder refused
with the failure report in the default folder and no lock taken; the log folder refused; the
backup folder created with the SQL Server account, refused, and overridden; the installation
check for the folder, the file and an unreadable access control list; on Windows, a protected
folder created and read back with exactly the granted identities; the dependency summary, a
blocking component, an unavailable stage and a check that fails; the source free of download,
install, trust and code-loading calls; an unexpected failure in the stage run, before the stages
and while saving the outputs, each with its failure report, its point, the synchronization
restarted, the lock released, the run-failed event and `StageError`, and a coded stop that keeps
its own code; interrupted runs of obsolete-update deletion, superseded declines, declined-update
deletion, deferred approval, stale-computer removal, sync-history cleanup and IIS log retention,
each finished by the next run with nothing done twice, a custom index left by an interrupted run,
and a partial backup file replaced; the release workflow's schema assets; and the `-ValidateOnly`
exit codes of the smoke script (0, 2 and 4 for the fixtures, and 0 or 4 for stage lists, the
index removal, report formats, verbosity and a relative report folder).

Notes for maintainers:

- **Stage handlers.** Every stage of the catalogue has a handler in `Get-MaintenanceStageHandler`.
  A handler is a script block with one `-Context` parameter (`StageName`, `DryRun`,
  `Configuration`, `Deadline`, `RunStart`, `Log`, `Server`, `RemoveCustomIndexes`, `Events`) that
  returns `[PSCustomObject]@{ Status; Counts; Items; Message; Notices }`, built with
  `New-MaintenanceStageResult`. A stage that works item by item checks the time budget between
  items and logs progress. In a dry run the stage changes nothing and reports what it would
  change. A stage that needs its own event writes it through `Context.Events`.
- **Server facts.** `Context.Server` carries `Tier`, `Role`, `Environment`, `Permission`,
  `UpdateServer`, `Database` and `CommandTimeoutSeconds`, and the decline and approval stages add
  `DeclineCatalog` and `ApprovalCatalog`. Windows-only reads go through the seams in section 3.3,
  which tests replace.
- **Strict mode.** The build runs the tests under `Set-StrictMode -Version 3.0`: a property of a
  missing XML node or object is an error there, so code checks for null first.
- **Tier gating.** Done in `Get-MaintenanceStagePlan`: on a replica the decline and approval
  stages, declined-update deletion and stale-computer moves are skipped with "skipped: replica",
  and with an unknown tier with "skipped: server role unknown".
- **Run result.** Configuration failures throw `ConfigurationInvalid` with the full validation
  summary as `TargetObject`; precondition failures throw `PreconditionFailed` or `LockHeld`; an
  unexpected error throws `StageError` after its failure report. A completed run returns
  `WsusMaintenance.RunResult` with `Stages` (18 outcomes), `Notices`, `Run` and `Validation`.
- **Seams in tests.** Tests that do not exercise folder protection replace
  `Test-MaintenanceAclSupport` with `$False`, and the run-level tests replace
  `Test-MaintenanceDependencyPresent` with `$True`, so that the suite behaves the same on Windows
  and elsewhere.

## 11. Lifecycle automation

Requirement: automate WSUS end to end. Approve the updates clients need a configurable number of
days after release, and download their content as early as possible, from the moment a client
reports needing an update, without making it installable before its approval date. The design
below was built in milestone M8 (section 10).

### 11.1 Behaviour per tier

- **Autonomous downstream** (both downstream profiles in section 2). Approvals, computer groups and
  declines are local: "downstream WSUS servers are administered separately, and they don't receive
  update approval status or computer group information from the upstream server" ([Plan your WSUS
  deployment][plan]). Deferred approval and pre-staging run here.
- **Replica downstream** (the proof deployment). "If your WSUS server is running in replica mode,
  you won't be able to approve updates on your WSUS server" ([Updates operations][ops]), and
  computer groups cannot be created on a replica ([plan]). Both approval stages are skipped with
  "skipped: replica".
- **Top tier.** Enabled only when configured; a top tier that only synchronizes and serves
  leaves approval off. With deferred downloads on a downstream, a request for an update the
  upstream has not approved "forces a download on the upstream server" ([plan]); an upstream that
  downloads everything it synchronizes already holds all content for its selection.

### 11.2 Decided behaviour

| Id | Behaviour | Microsoft basis |
|---|---|---|
| LCA-01 | **Deferred approval.** An update is approved for a group once the configured number of days has passed since its revision's `CreationDate` ("when this revision of the update's metadata was authored"). A re-released revision restarts the delay. | `IUpdate` [members][iupdate] |
| LCA-02 | **Per-group delays.** Each configured computer group has its own delay; there is no fixed ring structure. Groups are created by configuration management; a group that does not exist is reported, never created. | `IUpdate.Approve(UpdateApprovalAction, IComputerTargetGroup)`; group conflict resolution in [plan] |
| LCA-03 | **Deadlines.** Each approval carries an install-by deadline a configurable number of days after the approval. An update that needs user input is approved without one, as WSUS requires. | `IUpdate.Approve(..., DateTime)`; [ops] |
| LCA-04 | **Needed updates only.** Candidates are updates that at least one client reports needing, taken from per-update summaries. Nothing else is approved or downloaded. | `IUpdate.GetSummary(ComputerTargetScope)` [iupdate] |
| LCA-05 | **Content pre-staging.** On every run, each needed candidate that is not yet approved is approved for an empty staging computer group, which starts its download without offering it to any client. On its approval date the real per-group approvals follow, and the staging approval is removed once the files are local. Express installation files stay off. | Deferred download: "an update is downloaded only after it's approved" ([plan]); express files ([plan]) |
| LCA-06 | **Late content.** When an approval date arrives before the files are local, the update is approved on schedule and the report raises a Warning notice and an event naming each such approval. Clients wait for the files. | Server status `UpdatesNeedingFilesCount` |
| LCA-07 | **Supersedence and exclusions.** An update whose superseding update is approved or eligible is never approved. A configured list of Knowledge Base numbers or GUIDs is never approved. Superseded updates are left for the decline engine. | [ops] ("Automatically Declining Superseded Updates") |
| LCA-08 | **Special cases.** Licence agreements of selected updates are accepted automatically (native automatic approval rules skip such updates until the agreement is accepted). The Upgrades classification is never approved automatically, because feature updates can move clients to a new OS release. WSUS infrastructure updates are approved before any other update. | [ops]; `IUpdate.AcceptLicenseAgreement()` [iupdate] |
| LCA-09 | **Gating and reporting.** Replica: skipped. Every approval and staging action is listed with its group, delay, deadline and content state. Dry run lists the approvals that would be made. | [ops], [plan] |

The native automatic approval rules approve during synchronization, by classification, product
and computer group, with an optional deadline, but with no delay ([ops]). Deferral is therefore
done by the script: the approval stages run on every nightly run, like every other stage, so an
approval is never more than a day late.

### 11.3 Content download over a slow upstream link: levers and where they sit

| Lever | Where | Behaviour | Decision |
|---|---|---|---|
| Approve needed updates for an empty staging group | Downstream | With deferred downloads an update downloads once approved; an approval for an empty group starts the download and offers nothing to clients ([plan]). | Used (LCA-05). |
| `IUpdate.ResumeDownload()` | Downstream | "Identifies to the synchronization agent the update to download"; the download starts on schedule or earlier on `StartSynchronization` ([ResumeDownload][resume]). Undocumented for unapproved updates. | Not used; may serve to retry a failed download. |
| "Download only when approved" off (`DownloadUpdateBinariesAsNeeded = false`) | Downstream configuration (owned by configuration management) | Downloads files for every synchronized update ([IUpdateServerConfiguration][config]). | Not used on downstreams: transfers the whole selection over a slow upstream link. A top tier that only synchronizes and serves needs it on. Reported as drift against per-deployment expectations. |
| Express installation files (`DownloadExpressPackages`) | Downstream configuration | "Express installation files are larger than the updates that are distributed to client computers" and cost "additional bandwidth between your WSUS server, any upstream WSUS servers, and Microsoft Update"; off by default ([plan]). | Off; reported as drift. |
| Content from Microsoft Update instead of the upstream (`GetContentFromMU`) | Downstream configuration | Metadata from the upstream, files from Microsoft Update ([config], [plan] branch offices). | Not available when the downstream cannot reach Microsoft Update. |
| Upstream approval and content | Upstream (may be managed outside the deployment) | Bounds what a downstream can fetch; an upstream that downloads everything it synchronizes already holds all content for its selection. | Outside the downstream's control when the upstream is managed elsewhere. |
| BITS throttling | Host policy | WSUS transfers all files with BITS; BITS limits "apply to all applications that are using BITS" ([plan]). | Reported when a throttling policy is present. |

Figures Microsoft publishes: about 10 GB of on-premises UUP content per Windows version and
processor architecture, and at least 20 GB (40 GB recommended) for local content storage ([plan]).
No figure is given for express-file size beyond "larger" on the server.

### 11.4 Configuration (M8)

```json
"approval": {
  "enabled": true,
  "groups": [
    { "name": "Pilot", "delayDays": 7, "deadlineDays": 7 },
    { "name": "All Computers", "delayDays": 14, "deadlineDays": 7 }
  ],
  "staging": { "enabled": true, "groupName": "Content Staging" },
  "neverApprove": [ "KB0000000" ],
  "excludedClassifications": [ "Drivers" ],
  "acceptLicenseAgreements": true
}
```

`approval.enabled` is off by default. `deadlineDays` is optional; without it a group's approvals
carry no deadline. Fixed, not configurable: candidates are client-needed updates only, the delay
counts from the revision creation date, late content is approved with a warning, superseded
updates are skipped while their superseding update is approved or eligible, and Upgrades stay
excluded (`excludedClassifications` adds to it and cannot remove it). The stages `ContentStaging`
and `DeferredApproval` follow the decline stages and precede declined-update deletion. The health
checks compare the download settings with the per-deployment values in `health.downloadSettings`
(section 10, M9).

## 12. Open items and risks

Release one is built and tested against stand-ins (section 3.3); what only a live server can show
is listed here, once, under the lane that can prove it. Until an item is proven it is a known
risk.

### 12.1 Live evidence still owed

**A. SQL Server Express runner lane (M11).** A hosted Windows runner with SQL Server Express and
the WSUS role, an unsynchronized top-tier SUSDB, and the built script started by a scheduled task
as SYSTEM:

- that `HAS_PERMS_BY_NAME` reports the stage permissions as expected for SYSTEM as database owner,
  and for a login that is not;
- that `dbo.tbEventInstance` has the `TimeAtServer` column and that it holds UTC times;
- that SYSTEM can read `msdb.dbo.backupset` for the backup gate;
- that `SERVERPROPERTY('Edition')` begins with the edition name the compression choice reads
  (Express: no compression);
- the text `OBJECT_DEFINITION` returns for `dbo.spDeleteUpdate` on the WSUS version of the
  runner's Windows Server release (leading comments, header, declaration spacing), before and
  after the fix (lane B adds Windows Server 2022's);
- that the custom indexes are created and tagged in one transaction (`SET XACT_ABORT ON`,
  `sys.sp_addextendedproperty`) and that the removal action drops only those;
- that a backup folder the run creates, protected for SYSTEM, Administrators and
  `NT SERVICE\MSSQL$SQLEXPRESS`, lets the SQL Server service write the backup, and that a second
  backup on the same day replaces the first;
- that the folders the run creates carry exactly the protected access control list on NTFS, that
  an existing folder with inherited `%ProgramData%` permissions is refused, and how the
  installation check judges the folder the runner starts the script from;
- that the dependency check finds the WSUS administration API, the SQL Server client and the IIS
  configuration once the WSUS role is installed, and that the script runs as a 64-bit process (a
  32-bit process would read a redirected `applicationHost.config` path);
- that WSUS setup records `UsingSSL`, `TargetDir` and `SqlServerName` in its registry key as
  discovery and the TLS and site checks expect, and the IIS site, log folder and application pool
  WSUS setup creates;
- that the local `AdminProxy.GetUpdateServer()` connects under SYSTEM, and that setting
  `PreferredCulture` to `en` and restoring the previous (possibly empty) value works on an
  English server;
- that `spGetObsoleteUpdatesToCleanup`, each built-in cleanup option, the re-index statements and
  `sp_updatestats` complete on a real SUSDB, and that a second run finds nothing to do;
- the exit codes Task Scheduler records for a successful run, a stage error and a failed
  precondition;
- that terminating the task at several points of a run and then running it again leaves SUSDB
  consistent and every stage succeeding (REQ-096).

**B. `windows-wsus` replica proof (I4).** The replica the `windows-wsus` repository builds on every
change: SQL Server 2022 Standard (default instance), Windows Server 2022, domain-joined, TLS, with
reporting clients:

- who owns SUSDB, and SYSTEM's SQL login on the image after I2;
- which SUSDB operations and built-in cleanup options a replica accepts or refuses, and with what
  error;
- the WSUS API over HTTPS under SYSTEM: whether the local `GetUpdateServer()` connects when the
  API web service requires TLS, or `discovery.wsusHostName` and `discovery.wsusUseTls` must be set;
- that the SQL Server service account (`NT SERVICE\MSSQLSERVER`) writes the backup into the
  protected folder I1 and I2 prepare, with compression on Standard;
- the names under which HTTP.sys registers the certificate of the WSUS TLS port
  (`SslBindingInfo` or `SslSniBindingInfo`, `0.0.0.0:8531` or `[::]:8531`), and the certificate
  expiry check against it;
- the manufacturer and model strings of the hypervisor, for the virtual-machine test;
- the IIS log folder and file names of the WSUS website on Windows Server 2022;
- whether `ComputerTargetScope.ToLastSyncTime` includes computers that never synchronized, that
  `GetComputerTargetCount` over the same scope counts the population the stale-computer guard
  compares against, and whether a replica accepts the deletion of a stale computer;
- the event source registered by I3 and the events of a run, the scheduled task's exit codes,
  replica gating, and a second run that finds nothing to do (I4);
- the duration of each stage on a SUSDB of realistic size, and an interrupted run finished by the
  next one on a live server.

**C. Autonomous lifecycle variant (I5).** A dispatch-only build with `replica: false` against a
test upstream, which gives the decline engine and the approval stages a server that may decline
and approve; as planned it has no reporting clients, so the items marked "needs clients" stay open
until clients are added to it:

- how long `GetUpdates` takes over the undeclined updates, and the memory the WsusPool application
  pool needs for it;
- whether `CreationDate` and `ArrivalDate` arrive in UTC, as the age tests assume;
- that the approval states used for the evaluation scope leave out every declined update;
- that superseded and expired declines happen as selected and a repeat run declines nothing;
- which errors `DeleteUpdate` raises for a declined update that other updates still reference;
- which exceptions a built-in cleanup time-out raises through the administration API, so that
  the retry test recognises them (seen only if a time-out occurs);
- the state an unapproved update reports, and how quickly an approval for the empty staging
  group starts its download on a downstream server with deferred downloads;
- how a staging approval removal interacts with the built-in unneeded-content cleanup;
- whether `AcceptLicenseAgreement` succeeds for an update whose licence text is not yet
  downloaded, before staging has fetched it;
- whether an approval's deadline is accepted in UTC as documented, and how `CanRequestUserInput`
  is set on updates that ask for input (needs an update that asks for input);
- that the per-update summaries report needed counts for updates that are not yet approved, which
  the approval candidates rely on (needs clients);
- how `AddComputerTarget` treats a stale computer that is already in other groups, for the `Move`
  action (needs clients).

**Not covered by any planned lane.** These stay open after A, B and C:

- Windows Server 2019, and whichever of Windows Server 2022 and 2025 neither the runner nor the
  replica runs;
- a server whose display language is not English, where `PreferredCulture` must return English
  titles and category names for the rules and the Upgrades exclusion;
- a large SUSDB that has gone without maintenance: first-run durations, the time budget across
  several nights, and built-in cleanup time-outs;
- a top-tier server on a workgroup host (section 2), which the `windows-wsus` role does not deploy
  yet.

### 12.2 Risks and limits

- **WSUS API connection time-out.** The administration API has no connection time-out parameter;
  `run.connectionTimeoutSeconds` bounds the SUSDB connection only, and the API connection is
  bounded by the API's own web-request time-out.
- **spDeleteUpdate fix.** Applied as a targeted edit of the live procedure (adding `PRIMARY KEY` to
  the `@revisionList` table variable), never by replaying the full published body. It is checked
  on every run. A WSUS update that rewrites the procedure in an unexpected shape leaves it
  untouched with a warning until the recognized patterns are extended.
- **Statistics.** `sp_updatestats` needs the database owner or sysadmin. Making SYSTEM the SUSDB
  owner satisfies that.
- **Custom indexes.** Created under the names Microsoft publishes and tagged with an extended
  property, so that the removal action drops only the indexes this script created. An index of
  the same name created by hand before the script ran carries no tag and is never dropped.
- **Sync-history age.** Records are aged by `TimeAtServer` against the current UTC time; if the
  column holds local time on some servers, the age is off by the UTC offset.
- **Backup size estimate.** The estimate is the database's reserved space, which overstates a
  compressed backup; the margin is applied on top.
- **Same-day append.** With `backup.sameDay` set to `Append`, a second backup on the same day
  fails if compression differs from the first, because compressed and uncompressed backups cannot
  share a media set ([backup compression][compression]).
- **Built-in cleanup and the run budget.** Each built-in cleanup option is one API call that
  cannot be interrupted; the budget can only stop the next option from starting. A first cleanup
  of a server that has gone without maintenance can run for hours.
- **Declined-update deletion.** Deleting declined updates is hard to reverse: an update comes back
  only through a re-import or a resynchronization. The stage is off by default and behind the
  backup gate.
- **Decline retrieval size.** All undeclined updates are read in one call; on a large server
  with an unlimited arrival window this is the call most likely to exhaust the WsusPool
  application pool. `declines.arrivalWindowDays` narrows it, as Microsoft's script does with six
  months.
- **Approvals are hard to undo in bulk.** Approval stays off by default, the exclusion lists and
  the never-approve list are the safety levers, and a dry run lists every approval first.
- **Staging group membership.** An approval for the staging group is offered to any computer that
  joins it. The stage refuses to stage into a group with members, but a computer that joins
  between runs is offered the staged updates until the next run finds it.
- **Stale-computer guard at zero.** `staleComputers.guardCount` and `guardPercent` are upper
  limits taken literally: a value of 0 means any selection exceeds the guard, so nothing is
  removed without `staleComputers.override`.
- **Validation under PowerShell 7.** Date-like strings in JSON become `DateTime` under PowerShell 7
  (the test runtime on Linux) but stay strings under 5.1.
- **Pinning by digest.** Renovate can move a release tag but cannot refresh the asset digest. A
  bump fails closed until the digest is updated.
- **Redaction is a safeguard, not a guarantee.** Registered secret values are removed exactly;
  the connection-string and JSON-key patterns are heuristics for text the script did not
  produce itself (for example an exception message). A connection-string password is redacted to
  the end of its value or line, which can hide more than the password.
- **Event source.** Deployment (I3) must register the source in the configured log; otherwise
  every run logs one warning and writes no events.
- **Folders prepared by hand.** A data folder created by hand under `%ProgramData%` inherits write
  access for standard users and is refused; the run then stops until the folder is protected or
  `run.permissiveFolderOverride` is set. The script's own location has no override. The trust
  test reads the access control list as written; it does not evaluate group membership, so a
  rule for a group that contains only administrators still counts as another principal.
- **Errors before the run log.** An unexpected error while reading the configuration or opening
  the outputs exits 1 without a report, because no report location is known yet; nothing has
  been changed at that point.
- **Termination.** Termination is simulated in the tests by stopping a stage between items; a
  live interruption (lane A) is still owed. A built-in cleanup option that is terminated restarts
  from the beginning on the next run.
- **Dependency check scope.** Only the components the script calls are checked (the WSUS
  administration API, the SQL Server client and the IIS configuration); a component that is
  present but broken still fails in its stage.

[plan]: https://learn.microsoft.com/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment
[guide]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide
[ops]: https://learn.microsoft.com/windows-server/administration/windows-server-update-services/manage/updates-operations
[iupdate]: https://learn.microsoft.com/previous-versions/windows/desktop/ms752700(v=vs.85)
[resume]: https://learn.microsoft.com/previous-versions/windows/desktop/ms748088(v=vs.85)
[config]: https://learn.microsoft.com/previous-versions/windows/desktop/ms752728(v=vs.85)
[reindex]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/reindex-the-wsus-database
[compression]: https://learn.microsoft.com/sql/relational-databases/backup-restore/backup-compression-sql-server
[spdelete]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/spdeleteupdate-slow-performance
[maintenance]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-automatic-maintenance
[scope]: https://learn.microsoft.com/previous-versions/windows/desktop/aa354275(v=vs.85)
[stale]: https://learn.microsoft.com/previous-versions/windows/desktop/ee958382(v=vs.85)
[approvedstates]: https://learn.microsoft.com/previous-versions/windows/desktop/aa354257(v=vs.85)
[culture]: https://learn.microsoft.com/previous-versions/windows/desktop/ms751963(v=vs.85)
[declinesuperseded]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/decline-superseded-updates
[deleteupdate]: https://learn.microsoft.com/previous-versions/windows/desktop/aa349863(v=vs.85)
[needed]: https://learn.microsoft.com/previous-versions/windows/desktop/ms744621(v=vs.85)
[approve]: https://learn.microsoft.com/previous-versions/windows/desktop/ms747129(v=vs.85)
[updatestate]: https://learn.microsoft.com/previous-versions/windows/desktop/ms752993(v=vs.85)
[views]: https://learn.microsoft.com/previous-versions/windows/desktop/bb410149(v=vs.85)
[iislogs]: https://learn.microsoft.com/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage
[bestpractices]: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/windows-server-update-services-best-practices
[dotnettls]: https://learn.microsoft.com/dotnet/framework/network-programming/tls
[settings]: https://learn.microsoft.com/security-updates/windowsupdateservices/18125970
[release]: https://learn.microsoft.com/windows/release-health/windows-server-release-info
[adminproxy]: https://learn.microsoft.com/previous-versions/windows/desktop/ms745830(v=vs.85)
[iupdateserver]: https://learn.microsoft.com/previous-versions/windows/desktop/ms752727(v=vs.85)
[perms]: https://learn.microsoft.com/sql/t-sql/functions/has-perms-by-name-transact-sql
[backupperm]: https://learn.microsoft.com/sql/t-sql/statements/backup-transact-sql
[subscription]: https://learn.microsoft.com/previous-versions/windows/desktop/aa354311(v=vs.85)
[syncstatus]: https://learn.microsoft.com/previous-versions/windows/desktop/ms752776(v=vs.85)
