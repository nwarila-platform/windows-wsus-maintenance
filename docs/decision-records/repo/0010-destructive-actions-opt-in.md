# ADR-repo/0010: Build Destructive and Approval Actions Behind Explicit Opt-In

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-07                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | High (each is one configuration key)                         |

## Context and Problem Statement

Some actions cannot easily be undone: deleting declined updates (an update comes back only through
a re-import or a resynchronization), approving updates in bulk, deleting computers, and declines
by rule. Others are routine and recommended by Microsoft for every server. Release one must be
safe to deploy with an empty configuration document apart from the backup destination.

## Decision Outcome

- On by default, as Microsoft recommends for routine maintenance: the backup with the backup gate
  required, the custom indexes, the `spDeleteUpdate` fix, obsolete-update deletion, the built-in
  cleanup options except obsolete computers, sync-history cleanup, superseded declines after 90
  days and expired declines (both skipped on replicas), stale-computer removal behind its guard,
  re-indexing, retention and the read-only health checks.
- Built but off by default: declined-update deletion, the accelerated decline policy, decline
  rules (none ship enabled), deferred approval and content staging, and the built-in
  obsolete-computer cleanup (the stale-computer stage replaces it).
- Every action that deletes or alters SUSDB content stays behind the backup gate; the
  stale-computer guard changes nothing when more than 10% or 50 computers would go unless it is
  overridden; and a dry run lists every pending change first.

### Consequences

- Positive: a first deployment does only what Microsoft documents for every server; each riskier
  action is a deliberate configuration choice that the run log records.
- Negative: deployments that want lifecycle automation must enable and configure it.
