# ADR-repo/0005: Detect the Server Tier Every Run and Never Change It

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-06                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Low                                                          |

## Context and Problem Statement

The script must support top-tier, autonomous downstream and replica downstream servers. A replica
inherits approvals, declines and computer groups from its upstream and refuses to decline locally.
Switching replica mode off to make a decline possible would silently change the hierarchy.

## Decision Outcome

- Every run reads `IsReplicaServer` and `SyncFromMicrosoftUpdate` and classifies the server as
  TopTier, Autonomous or Replica, and every report shows it.
- On a replica, every action that declines updates or changes approvals or computer groups is
  skipped with the reason "skipped: replica": the decline policies, declined-update deletion, the
  built-in cleanup's decline options and stale-computer moves.
- If the tier cannot be determined, every gated action is skipped with a warning.
- The script never changes the replica setting.
- No environment is hard-coded: deployments configure behaviour per server; the tier itself is
  always detected.
