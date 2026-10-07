# ADR-repo/0004: Fixed Exit Codes Mapped from Error Identifiers

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-06                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Low (consumers act on the codes)                             |

## Decision Outcome

The `MaintenanceExitCode` enum is the exit-code table, and each member name is also the short
ErrorId that `New-ErrorRecord` stamps on a terminating error. The entry point maps a failure to its
code by that name, as the certificate exporter does.

| Code | Member | Meaning |
|---|---|---|
| 0 | Success | Completed |
| 1 | StageError | One or more stage errors, and every unhandled failure |
| 2 | CompletedWithWarnings | Completed with warnings |
| 3 | PreconditionFailed | Aborted on a precondition |
| 4 | ConfigurationInvalid | Invalid configuration document or options |
| 5 | LockHeld | Another run holds the lock |
| 6 | DeliveryFailed | Reserved for the delivery test |

The overall run status is the worst of the stage outcomes and notices (severities Information,
Warning, High, Error; High raises the status to warning, Error to error) and decides the exit code
of a run that completes. The table is fixed rather than configurable: changing a code silently
would break every consumer that acts on it.
