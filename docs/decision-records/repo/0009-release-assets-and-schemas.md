# ADR-repo/0009: Publish the Script, Its Schemas and Their Provenance Together

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-07                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | High                                                         |

## Context and Problem Statement

Deployments pin a release of the script by tag and SHA-256 digest. They also write the
configuration document and read the run summaries, whose formats the two JSON schemas describe,
and those schemas must match the script version that is installed.

## Decision Outcome

- Each release (a `v*` tag) carries `Invoke-WsusMaintenance.ps1`, its `.sha256` sidecar,
  `maintenance.schema.json` (the configuration document) and `summary.schema.json` (the run
  summary), all from one sealed build, and the signed build provenance.
- The provenance subjects cover the script and both schemas. Before publishing, the release job
  checks the script against the sealed digest and every asset against the sealed subjects, so a
  schema cannot drift from the script it was built with.
- The schemas in `docs/reference/` stay the source; the release copies them unchanged.

### Consequences

- Positive: a deployment can fetch the schema of exactly the version it pins and validate its
  configuration before installing; consumers of the summary know its format per version.
- Negative: three assets to fetch instead of one when a deployment wants the schemas.
