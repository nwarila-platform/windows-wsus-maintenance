# ADR-repo/0002: Confine Platform Access to Mockable Seams

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-06                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Medium                                                       |

## Context and Problem Statement

The script talks to SQL Server, the WSUS administration API, the registry, IIS, the Event Log and
the file system. None of these exist on a build agent, and a test that needs a live WSUS server
cannot run on every change. The suite must still reach the 90% coverage gate and run under both
Windows PowerShell 5.1 and PowerShell on Linux.

## Decision Outcome

- Every Windows-only type or command is reached through a small seam function (for example
  `New-SqlConnection`, `Invoke-SusdbCommand`, `Get-WsusUpdateServer`, `Get-WsusSetupValue`,
  `Write-MaintenanceEvent`, `New-MaintenanceLock`). Everything above the seams is plain logic.
- Tests dot-source the functions artifact and replace seams with Pester `Mock`, asserting both the
  outcome and the exact calls made (for example the T-SQL text and parameters).
- Live behaviour is proven separately: by a hosted-runner lane with SQL Server Express and WSUS,
  and by the `windows-wsus` deployment proof.

### Consequences

- Positive: deterministic tests on any agent; a seam is the single place to change when a platform
  API behaves differently.
- Negative: seams themselves are thin and are covered mainly by live lanes, not unit tests.
