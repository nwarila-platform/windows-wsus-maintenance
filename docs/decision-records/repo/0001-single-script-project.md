# ADR-repo/0001: Assemble a Single Installed Script from Structured Source

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-06                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Medium                                                       |

## Context and Problem Statement

The WSUS maintenance tool is far larger than a single gap-filling script: configuration with a
published schema, a stage plan, many database and WSUS API stages, reports, events and
exit codes. It still has to be installed on each WSUS server as one file that a scheduled task
runs, with no module installation at run time.

## Considered Options

1. Structured source under `src/`, assembled by `build.ps1` into one installed script (chosen).
2. One hand-written script.
3. A PowerShell module with a manifest.

## Decision Outcome

Chosen: option 1, the same layout as `windows-certificate-store-exporter`.

- Source lives in `src/EntryPoint.ps1`, `src/Public/*.ps1` and `src/Private/*.ps1`, one function
  or enum per file.
- `build.ps1 -Task Build` emits `build/Invoke-WsusMaintenance.ps1` (installed) and
  `build/Invoke-WsusMaintenance.Functions.ps1` (dot-sourced by the tests and measured for
  coverage).
- Releases publish the single script with a SHA-256 sidecar and signed build provenance; consumers
  pin a release by tag and digest.

### Consequences

- Positive: small, reviewable source files; the tests cover exactly the merged code that ships.
- Negative: the build must run before tests and releases; `build/` is generated and ignored.
