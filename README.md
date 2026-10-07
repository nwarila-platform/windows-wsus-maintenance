# windows-wsus-maintenance

Unattended maintenance for Windows Server Update Services (WSUS) servers backed by SQL Server:
Microsoft-documented cleanup and SUSDB upkeep, update declines, housekeeping, health checks and
reporting, packaged as one Windows PowerShell 5.1 script that a scheduled task runs.

> **Status: pre-release.** Milestones M0 (scaffold), M1 (configuration and validation), M2 (run
> control: stage plan, lock, elevation, time budget), M3 (run log, text and HTML reports, JSON
> summary, events, failure reports), M4 (discovery, connections, server tier, database
> permissions, synchronization guard) and M5 (SUSDB upkeep: backup and retention, backup gate,
> custom indexes, the spDeleteUpdate fix, obsolete-update deletion, sync-history cleanup,
> re-index and statistics) are complete. The WSUS API cleanup, declines, housekeeping and health
> stages are not implemented yet and are reported as not available. See
> [docs/DESIGN.md](docs/DESIGN.md) for the design and milestone plan.

## Supported servers

- Windows Server 2019, 2022 and 2025 with the WSUS role installed locally.
- SUSDB on SQL Server on the WSUS server (default or named instance). Windows Internal Database
  and remote SQL Server are refused.
- Top-tier, autonomous downstream and replica downstream servers; domain membership is not
  required.

## Usage

```powershell
.\Invoke-WsusMaintenance.ps1 -ConfigPath 'C:\ProgramData\NWarila\WsusMaintenance\maintenance.json' -ValidateOnly
```

The [CLI contract](docs/reference/cli-contract.md) lists every parameter, exit code, output file
and event; the [configuration reference](docs/reference/configuration.md) documents every key, and
[maintenance.schema.json](docs/reference/maintenance.schema.json) is the machine-readable schema.
Each run's JSON summary follows [summary.schema.json](docs/reference/summary.schema.json).

## Build and test

```powershell
pwsh -NoProfile -File ./build.ps1 -Task All
```

`All` cleans, builds `build/Invoke-WsusMaintenance.ps1`, runs the analyzer with the house rules
(zero findings), runs the Pester suite with a 90 percent coverage gate on
`build/Invoke-WsusMaintenance.Functions.ps1`, and runs the smoke scripts. CI runs the same gate on
Windows PowerShell 5.1.

## Releases

Tags matching `v*` publish a GitHub Release from a sealed build that has passed analysis, tests and
smoke checks. Each release carries `Invoke-WsusMaintenance.ps1`, its `.sha256` sidecar and signed
build provenance (`Invoke-WsusMaintenance.ps1.intoto.jsonl`). Consumers pin a release by tag and
SHA-256 digest.

## License

[MIT](LICENSE).
