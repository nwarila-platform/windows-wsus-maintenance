#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Process exit codes. Each member name doubles as the short ErrorId that New-ErrorRecord stamps
#   on a terminating error, so the entry point maps a failure to its exit code by name. StageError
#   also absorbs unhandled failures: an unexpected exception never exits with Success.
Enum MaintenanceExitCode {
  Success = 0
  StageError = 1
  CompletedWithWarnings = 2
  PreconditionFailed = 3
  ConfigurationInvalid = 4
  LockHeld = 5
  DeliveryFailed = 6
}
