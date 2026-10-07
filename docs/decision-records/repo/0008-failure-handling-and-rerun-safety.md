# ADR-repo/0008: Report Every Failure and Leave Nothing Half-Done for the Next Run

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Status         | Accepted                                                     |
| Date           | 2026-10-07                                                   |
| Decision-maker | Nick Warila (repository owner)                               |
| Reversibility  | Medium                                                       |

## Context and Problem Statement

A nightly job is sometimes terminated, by a reboot or by the task's time limit, and its code can
meet an error nobody anticipated. Either way the operator must learn what happened from the
report and the exit code, the synchronization the run stopped must start again, and the next
night must be able to finish the work without manual repair.

## Decision Outcome

- **Failures stay inside their stage.** Each stage runs in its own error boundary, and an item
  that fails inside a stage is recorded while the next item proceeds; peripheral failures (a
  report file, an event) only lower the run status.
- **An unexpected error is still reported.** Once the run log is open, any error that is not one
  of the coded stops is caught at the top: the synchronization the guard stopped is restarted,
  the database connection is closed and the lock released, and the run saves a failure report and
  summary (failure kind `StageError`, with the point the run reached), writes the run-failed event
  and exits with code 1. Only an error before the run log exists exits 1 without a report; nothing
  has been changed on the server at that point.
- **Every change is safe to repeat.** Stages decide from the server's current state on every run
  and keep no state between runs
  ([repo/0006](0006-nightly-run-of-every-stage.md)), so a run after an interruption finds exactly
  the work left: obsolete-update deletion resumes from what remains, declines and approvals skip
  what is already done, retention and stale-computer removal re-evaluate, and the backup keeps
  one file per day.
- **No change is half-applied.** Every change is one atomic operation: each update, approval,
  computer and file is changed by one call; the synchronization history is deleted in batches of
  one statement each; the `spDeleteUpdate` fix is one `ALTER PROCEDURE`; and a custom index is
  created together with the tag that marks it as the script's in one transaction that any error
  rolls back (`SET XACT_ABORT ON`), so the removal action can always recognise it.

### Consequences

- Positive: an interrupted night costs only time; every run leaves a report and an exit code that
  match what happened.
- Negative: item-by-item work is slower than set-based deletes; the work of a long built-in
  cleanup option that is interrupted is repeated by the next run.
