# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) governing this repository, split into
three scopes per [org/0001](org/0001-use-architecture-decision-records.md):

- [`org/`](org/) - mirrors of the organisation-baseline ADRs.
- [`template/`](template/) - mirrors of type-template ADRs inherited from
  [`NWarila/powershell-template`](https://github.com/NWarila/powershell-template/tree/main/docs/decision-records/template).
- [`repo/`](repo/) - repository-specific ADRs that apply only to this repository.

The three scopes use independent four-digit numbering namespaces.

## Index

### Org-Mirrored

| # | Title | Status |
| --- | --- | --- |
| [org/0001](org/0001-use-architecture-decision-records.md) | Use Architecture Decision Records to Document Design Rationale | Accepted |
| [org/0002](org/0002-adopt-diataxis-documentation-framework.md) | Adopt Diataxis as the Documentation Framework | Accepted |
| [org/0003](org/0003-use-deny-all-gitignore-strategy.md) | Use a Deny-All `.gitignore` Strategy | Accepted |
| [org/0004](org/0004-use-renovate-for-dependency-updates.md) | Use Renovate for Dependency Updates with Per-Template Baselines | Accepted |

### Template-Mirrored

| # | Title | Status |
| --- | --- | --- |
| [template/0001](template/0001-module-layout.md) | Use Public and Private Function Folders with Explicit Manifest Exports | Accepted; this repository ships a single script instead, per [repo/0001](repo/0001-single-script-project.md) |

### Repository-Specific

| # | Title | Status |
| --- | --- | --- |
| [repo/0001](repo/0001-single-script-project.md) | Assemble a Single Installed Script from Structured Source | Accepted |
| [repo/0002](repo/0002-script-structure-and-test-seams.md) | Confine Platform Access to Mockable Seams | Accepted |
| [repo/0003](repo/0003-configuration-document-and-validation.md) | One Validated JSON Configuration Document, One Parameter Catalogue | Accepted |
| [repo/0004](repo/0004-exit-codes-and-run-status.md) | Fixed Exit Codes Mapped from Error Identifiers | Accepted |
| [repo/0005](repo/0005-server-tier-gating.md) | Detect the Server Tier Every Run and Never Change It | Accepted |
| [repo/0006](repo/0006-nightly-run-of-every-stage.md) | Run Every Enabled Stage Each Night and Keep No State Between Runs | Accepted |
