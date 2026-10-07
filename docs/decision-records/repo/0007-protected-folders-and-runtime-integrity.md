# ADR-repo/0007: Protect the Script's Folders and Run Only Code That Others Cannot Change

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-07                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Medium                                                       |

## Context and Problem Statement

The script runs as `NT AUTHORITY\SYSTEM` and writes logs, reports, summaries and SUSDB backups
that describe the server. A folder that inherits the permissions of `%ProgramData%` lets standard
users add files to it, so they could read or plant content next to what the script writes; a
script file in such a folder could be replaced and then run with SYSTEM's rights. Servers may also
have no internet access, and a scheduled job must behave the same on every run.

## Considered Options

1. Create every folder protected, refuse existing folders that others can change, and refuse to
   run from such a location; never change an existing access control list (chosen).
2. Repair the access control list of any folder the script uses.
3. Leave permissions to the deployment.

## Decision Outcome

- **Folders the run creates** (the log, report, summary and backup folders, and each missing level
  above them) are created in one step with inheritance turned off and full control for SYSTEM,
  the local Administrators group and the run identity only; a backup folder also grants the SQL
  Server per-service account (`NT SERVICE\MSSQLSERVER` or `NT SERVICE\MSSQL$<instance>`), which
  writes the backup file. The access control list is read back and verified.
- **An existing folder is never changed.** When its owner, or any allow rule (inherited or not),
  lets another principal write, append, delete, change attributes, change permissions or take
  ownership, the run does not write to it: a log or report or summary folder makes the run stop as
  a failed precondition (exit code 3) after saving its failure report in a folder that can be
  used, and a backup folder fails the backup stage, which closes the backup gate. Service
  identities (`S-1-5-80-`), `CREATOR OWNER` and `OWNER RIGHTS` are trusted. The configuration key
  `run.permissiveFolderOverride` allows such a folder on purpose, with a Warning notice each run.
- **The script's own location.** Before taking the lock, the run checks the folder that holds the
  running script and the script file itself the same way and stops as a failed precondition when
  anybody else can change them. There is no override: code that others can change must not run
  as SYSTEM. The deployment installs the script under a protected folder.
- **Runtime integrity.** The script never downloads, installs or updates modules or packages,
  never changes file trust, execution policy or its own files, and loads no code from files. A
  test of the source enforces this. Before connecting, a dependency check looks for each
  component the run uses, all of them part of Windows Server, the WSUS role or IIS, and logs the
  result: a missing component the whole run needs (the WSUS administration API, the SQL Server
  client) stops the run as a failed precondition; one that only some stages need (the IIS
  configuration, for IIS log retention) makes those stages unavailable with a Warning notice.

### Consequences

- Positive: nothing the script writes or runs can be changed by a standard user; a server without
  internet access behaves like any other; a missing component is named instead of failing deep in
  a stage.
- Negative: a folder prepared by hand with inherited permissions stops the run until it is fixed
  or the override is set; the run cannot be started from a temporary or shared folder.
