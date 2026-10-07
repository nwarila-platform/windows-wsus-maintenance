# windows-wsus-maintenance

Unattended maintenance for Windows Server Update Services (WSUS) servers backed by SQL Server:
Microsoft-documented cleanup and SUSDB upkeep, update declines, housekeeping, health checks and
reporting, packaged as one Windows PowerShell 5.1 script that a scheduled task runs.

> **Status: release one built, not yet released.** Milestones M0 to M10 are complete: the
> configuration and validation, run control, reporting, discovery and preconditions, SUSDB upkeep,
> the built-in cleanup and stale computers, the decline engine, lifecycle automation (off by
> default), housekeeping and health checks, and hardening (protected folders, the dependency
> check, failure reports for unexpected errors, re-run safety). Every stage is implemented and
> tested against stand-ins; the evidence that only a live server can give is listed in
> [docs/DESIGN.md](docs/DESIGN.md) section 12, with the milestone and deployment proof that will
> provide it.

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
smoke checks. Each release carries `Invoke-WsusMaintenance.ps1`, its `.sha256` sidecar, the two
JSON schemas `maintenance.schema.json` and `summary.schema.json` of that version, and signed build
provenance (`Invoke-WsusMaintenance.ps1.intoto.jsonl`) that covers the script and both schemas.
Consumers pin a release by tag and SHA-256 digest.

## Runtime security

The script runs as SYSTEM and never downloads or installs anything. It creates its folders with
access for SYSTEM, Administrators and the run identity only, refuses existing folders that other
principals can change (unless `run.permissiveFolderOverride` is set), and refuses to run from a
location that others can change; see
[repo/0007](docs/decision-records/repo/0007-protected-folders-and-runtime-integrity.md).

## License

[MIT](LICENSE).
