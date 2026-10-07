# ADR-template/0001: Use Public and Private Function Folders with Explicit Manifest Exports

| Field          | Value                                          |
| -------------- | ---------------------------------------------- |
| Status         | Accepted                                       |
| Date           | 2026-06-02                                     |
| Authors        | Nick Warila (@NWarila)                          |
| Decision-maker | Nick Warila (sole portfolio maintainer)        |
| Consulted      | PowerShell Gallery publishing requirements; PSScriptAnalyzer PSGallery ruleset. |
| Informed       | Consumers that create repositories from this template. |
| Reversibility  | Medium                                         |
| Review-by      | N/A (Accepted)                                 |
| Last reviewed  | 2026-06-02                                     |

## TL;DR

PowerShell modules created from this template keep shippable code under
`src/<ModuleName>/`, split functions into `Public/` (exported) and `Private/`
(internal) folders with one function per file, and declare an explicit
`FunctionsToExport` list in the manifest. Wildcard exports (`'*'`) are
prohibited. `CmdletsToExport`, `AliasesToExport`, and `VariablesToExport` are
empty arrays unless the module genuinely ships those. The manifest declares
`CompatiblePSEditions = @('Core', 'Desktop')` with a `PowerShellVersion = '5.1'`
floor.

## Context and Problem Statement

A template's job is to make the right structure the path of least resistance.
PowerShell gives module authors a lot of latitude: code can live anywhere, the
manifest can export with wildcards, and there is no enforced separation between
public and internal functions. That latitude produces inconsistent modules that
are slow to load, hard to review, and surprising to consume.

Three concrete problems recur in modules that grow without an enforced layout:

1. **Wildcard exports.** `FunctionsToExport = '*'` forces PowerShell to load and
   parse the entire module to discover its exports. This slows `Import-Module`
   and `Get-Command -Module`, and it makes the public surface invisible until
   runtime. It also trips the PSScriptAnalyzer `PSUseToExportFieldsInManifest`
   rule that the PSGallery ruleset enforces.
2. **No public/private boundary.** Without a structural split, internal helpers
   leak into the consumer's command surface, and there is no diffable signal
   when the public API changes.
3. **Single-file modules.** A monolithic `.psm1` makes blame useless and merge
   conflicts frequent as the module grows.

## Decision Drivers

1. **Fast, predictable module load.** Explicit exports let PowerShell skip the
   load-and-analyze step.
2. **Reviewable public contract.** Changing the public surface should be a
   deliberate, diffable edit to one line of the manifest.
3. **PSGallery readiness.** The layout must satisfy the rules the PowerShell
   Gallery and the PSGallery PSScriptAnalyzer preset enforce, so a module can be
   published without rework.
4. **Cross-edition support.** Modules should run on both Windows PowerShell and
   PowerShell 7+ unless they declare otherwise.
5. **Green out of the box.** A freshly created repository must pass CI with no
   edits, giving new maintainers a working reference.

## Considered Options

1. `src/` with `Public/` and `Private/`, one function per file, explicit exports.
2. Flat root layout with `.psm1` and `.psd1` at the repository root and all functions inline.
3. `src/` with a single `.psm1` file that contains every function.

## Decision Outcome

Chosen option: **Option 1, `src/` with `Public/` and `Private/`, one function per file, explicit exports.**

- `src/<ModuleName>/` holds the manifest, root module, and `Public/` +
  `Private/` function folders.
- The root module dot-sources every `*.ps1` under `Private/` then `Public/`,
  and exports only the public base names via `Export-ModuleMember`.
- The manifest's `FunctionsToExport` is the authoritative export contract and
  lists each public function by name. `CmdletsToExport`, `AliasesToExport`, and
  `VariablesToExport` are `@()`.
- `CompatiblePSEditions = @('Core', 'Desktop')`; `PowerShellVersion = '5.1'`.

## Pros and Cons of the Options

### Option 1: `src/` with `Public/` and `Private/`, one function per file, explicit exports

- **Good, because** the public API is visible in both the filesystem and the manifest.
- **Good, because** explicit exports avoid wildcard discovery and satisfy the PSGallery analyzer preset.
- **Good, because** one function per file keeps diffs small and lowers merge-conflict risk.
- **Bad, because** adding a public function requires both a new file and a manifest export update.

### Option 2: Flat root layout

- **Good, because** it is simple for very small scripts.
- **Bad, because** it mixes shippable module code with repository scaffolding.
- **Bad, because** public and private functions are not structurally separated.

### Option 3: `src/` with a single `.psm1`

- **Good, because** it keeps module code under `src/`.
- **Bad, because** a monolithic root module makes review, blame, and conflict resolution harder as the module grows.
- **Bad, because** it does not make the public API boundary visible on disk.

## Confirmation

1. `src/<ModuleName>/<ModuleName>.psd1` MUST list each exported public function in `FunctionsToExport`.
2. `FunctionsToExport` MUST NOT use `'*'`.
3. `CmdletsToExport`, `AliasesToExport`, and `VariablesToExport` MUST remain `@()` unless the module intentionally ships those member types.
4. The root module MUST dot-source `Private/` and `Public/` function files and export only public function names.
5. The test suite MUST fail if expected exports drift or wildcard exports are introduced.

## Consequences

### Positive

- Module load and command discovery stay fast and predictable.
- The public API is reviewable in normal diffs.
- The scaffold is PSGallery-ready without layout rework.
- Internal helpers stay out of the consumer command surface.

### Negative

- The layout creates more files than a flat module.
- Maintainers must update the manifest when adding public functions.

### Neutral

- CI exercises PowerShell 7 on Ubuntu; Windows PowerShell 5.1 compatibility remains declared and can be validated locally or by downstream repos that add Windows jobs.

## Assumptions

1. Consumers of this template prefer a publish-ready module scaffold over the smallest possible file count.
2. Most derived modules will start with functions rather than compiled cmdlets, aliases, or exported variables.
3. PowerShell Gallery and PSScriptAnalyzer continue to recommend explicit manifest export fields.

## Supersedes

None.

## Superseded by

None (current).

## Implementing PRs

- The initial module scaffold, manifest, and tests implement this decision.

## Related ADRs

- Reference: [docs/reference/module-structure.md](../../reference/module-structure.md)
- Rationale: [docs/explanation/why-this-layout.md](../../explanation/why-this-layout.md)
- Diagram: [docs/diagrams/module-layout.mmd](../../diagrams/module-layout.mmd)

## Compliance Notes

None.
