# Functions

Every function in `src/`, in alphabetical order. Each function's `HelpUri` links to its entry
here; the comment-based help in the source is the full reference.

## Add-UpdateApproval

Private. Records in the approval catalog an approval the run has made.

## Backup-Susdb

Private. Creates the nightly full SUSDB backup and applies the backup retention.

## Connect-MaintenanceServer

Private. Connects to the WSUS administration interface and to SUSDB.

## ConvertTo-DeclineItemText

Private. Describes an update for a decline or deletion list.

## ConvertTo-DeclineRecord

Private. Reads the attributes the decline policies use from one update.

## ConvertTo-DeleteUpdateFix

Private. Works out whether spDeleteUpdate carries Microsoft's fix, and the edited definition if not.

## ConvertTo-MaintenanceByteText

Private. Writes a number of bytes in human-readable units.

## ConvertTo-MaintenanceConfigurationSchema

Private. Renders the configuration catalogue as a JSON Schema document.

## ConvertTo-MaintenanceDisplayValue

Private. Renders a configuration value for a validation message.

## ConvertTo-MaintenanceEffectiveConfiguration

Private. Builds the effective configuration from a validated document.

## ConvertTo-MaintenanceObjectTree

Private. Converts nested ordered dictionaries into nested objects.

## ConvertTo-MaintenanceReportHtml

Private. Renders a run report as a self-contained HTML page.

## ConvertTo-MaintenanceReportText

Private. Renders a run report as plain text.

## ConvertTo-SqlIdentifier

Private. Quotes a name as a SQL Server identifier.

## ConvertTo-StaleComputerText

Private. Describes a client computer for the stale-computer list.

## Disconnect-MaintenanceServer

Private. Closes the SUSDB connection of a run.

## Enter-MaintenanceLock

Private. Takes the system-wide run lock or stops the run.

## Exit-MaintenanceLock

Private. Releases the system-wide run lock.

## Get-ApprovalCatalog

Private. Gathers what the approval stages of a run need from WSUS, once.

## Get-BackupDestinationSpace

Private. Returns the free space of the volume holding the backup folder.

## Get-DeclineCatalog

Private. Returns the undeclined updates every decline policy of the run evaluates.

## Get-MaintenanceConfigurationRule

Private. Returns the configuration parameter catalogue.

## Get-MaintenanceDefaultConfigurationPath

Private. Returns the fixed default location of the configuration document.

## Get-MaintenanceDocumentValue

Private. Looks up one dotted configuration path in a parsed document.

## Get-MaintenanceIdentity

Private. Returns the name of the identity the run uses.

## Get-MaintenanceOperatingSystem

Private. Returns the operating system the script runs on.

## Get-MaintenanceOutputSetting

Private. Works out where and how this run reports, even when the configuration is invalid.

## Get-MaintenancePropertyValue

Private. Reads a property that an object may not have.

## Get-MaintenanceStageCatalog

Private. Lists the maintenance stages in their mandatory execution order.

## Get-MaintenanceStageHandler

Private. Returns the script block that carries out a stage, if this build has one.

## Get-MaintenanceStagePlan

Private. Decides, for every stage in its fixed order, whether it runs.

## Get-MaintenanceTime

Private. Returns the current local time.

## Get-SusdbConnection

Private. Returns the open SUSDB connection a stage works with.

## Get-SusdbIndexAction

Private. Chooses how to defragment one index, as Microsoft's WSUS re-index script does.

## Get-WsusConnection

Private. Returns the WSUS administration connection a stage works with.

## Get-WsusEnvironment

Private. Discovers where SUSDB lives and whether this server is a supported combination.

## Get-WsusServerRole

Private. Detects the server tier: top tier, autonomous downstream or replica downstream.

## Get-WsusSetupValue

Private. Reads the values WSUS setup records in the registry.

## Get-WsusUpdateRecord

Private. Retrieves updates from WSUS in the evaluation language, as decline records.

## Get-WsusUpdateServer

Private. Connects to the WSUS administration interface.

## Initialize-MaintenanceFolder

Private. Makes sure a folder exists and can be written.

## Invoke-AcceleratedDecline

Private. Declines superseded updates of selected classifications after a shorter age.

## Invoke-ContentStaging

Private. Starts the content download of needed updates before their approval date.

## Invoke-DeclineSelection

Private. Declines the updates a decline policy selected, one at a time.

## Invoke-DeferredApproval

Private. Approves needed updates for each configured group once its delay has passed.

## Invoke-ExpiredDecline

Private. Declines expired updates.

## Invoke-MaintenanceRun

Private. Plans and executes the stages of one run.

## Invoke-MaintenanceStage

Private. Runs one planned stage inside its own error boundary.

## Invoke-ObsoleteUpdateCleanup

Private. Deletes obsolete updates one at a time with the SUSDB procedures Microsoft documents.

## Invoke-RuleDecline

Private. Declines the updates that the configured decline rules describe.

## Invoke-StaleComputerCleanup

Private. Deletes, or moves into a group, the computers that have stopped synchronizing.

## Invoke-SupersededDecline

Private. Declines superseded updates older than the age threshold.

## Invoke-SupersededPolicy

Private. Applies a superseded-update decline policy.

## Invoke-SusdbCommand

Private. Runs one parameterized command against SUSDB.

## Invoke-SusdbIndexMaintenance

Private. Defragments fragmented SUSDB indexes and then updates statistics.

## Invoke-SynchronizationGuard

Private. Makes sure no synchronization runs during maintenance.

## Invoke-WsusBuiltInCleanup

Private. Runs the built-in WSUS cleanup, one option at a time.

## Invoke-WsusMaintenance

Public. Runs one unattended WSUS maintenance pass.

## New-ApprovalUnavailableResult

Private. Builds the result of an approval stage that could not act.

## New-DeclineUnavailableResult

Private. Builds the result of a decline policy that could not act because the update list was missing.

## New-ErrorRecord

Private. Creates or throws a structured PowerShell error record.

## New-MaintenanceEventChannel

Private. Prepares the Windows Event Log channel for one run.

## New-MaintenanceLock

Private. Tries to take the system-wide run lock without waiting.

## New-MaintenanceLog

Private. Creates the run log file.

## New-MaintenanceNotice

Private. Creates a notice: a condition that needs attention.

## New-MaintenanceReport

Private. Builds the report of one run, ready to render.

## New-MaintenanceRunId

Private. Creates the unique identifier of one run.

## New-MaintenanceRunRecord

Private. Records the facts of one run for the result, the report and the summary.

## New-MaintenanceRunResult

Private. Creates the typed result object one maintenance run emits.

## New-MaintenanceStageOutcome

Private. Creates the record of what one stage did.

## New-MaintenanceStageResult

Private. Creates the result a stage handler returns.

## New-SqlConnection

Private. Opens a connection to SQL Server.

## New-SusdbMessageHandler

Private. Creates the handler that collects the messages a database command prints.

## New-WsusAdministrationObject

Private. Creates a scope object of the WSUS administration API.

## Open-MaintenanceRunOutput

Private. Opens the run log and prepares the event channel and the report and summary folders.

## Protect-MaintenanceText

Private. Removes secrets from text before it is written anywhere.

## Publish-MaintenanceRunOutput

Private. Writes the report, summary, closing log entries and events of a run.

## Read-MaintenanceConfiguration

Private. Reads and parses the configuration document.

## Register-MaintenanceSecret

Private. Registers a secret value so that it is never written anywhere.

## Remove-BackupFile

Private. Applies the backup retention to the backup files this script created.

## Remove-DeclinedUpdate

Private. Deletes declined updates from WSUS.

## Remove-SyncHistory

Private. Deletes old synchronization-history records from SUSDB.

## Resolve-MaintenanceOutputFolder

Private. Chooses the folder a report or summary is saved to.

## Resolve-MaintenanceOverride

Private. Validates the command-line options and applies their one-run overrides.

## Resolve-MaintenancePath

Private. Expands environment variables in a configured folder path.

## Resolve-MaintenanceRunStatus

Private. Derives the overall run status.

## Restore-Synchronization

Private. Restarts the synchronization the run stopped and restores the schedule it suspended.

## Save-MaintenanceReport

Private. Saves the rendered report files of one run.

## Select-ApprovalCandidate

Private. Selects the updates the approval stages consider.

## Select-SupersededUpdate

Private. Selects the superseded updates a superseded-update policy declines.

## Set-DeleteUpdateProcedureFix

Private. Applies Microsoft's fix for the slow spDeleteUpdate procedure when it is missing.

## Set-SusdbCustomIndex

Private. Ensures the non-clustered SUSDB indexes Microsoft recommends exist.

## Stop-MaintenanceRun

Private. Ends a run that failed a precondition, after reporting the failure.

## Test-BackupGate

Private. Decides whether stages that alter SUSDB may run, given the backup state.

## Test-DeclineRuleCondition

Private. Evaluates a decline-rule condition against one update.

## Test-MaintenanceBudget

Private. Reports whether the run's time budget has been used up.

## Test-MaintenanceConfiguration

Private. Validates a parsed configuration document completely.

## Test-MaintenanceConfigurationCrossField

Private. Applies the rules that relate one configuration value to another.

## Test-MaintenanceConfigurationValue

Private. Validates one configuration value against its catalogue rule.

## Test-MaintenanceDeclineCondition

Private. Validates one decline-rule condition tree.

## Test-MaintenanceDocumentStructure

Private. Checks that a configuration document uses only known keys.

## Test-MaintenanceDocumentText

Private. Scans a configuration value for embedded expressions and plain-text secrets.

## Test-MaintenanceElevation

Private. Reports whether the run is elevated or runs as LocalSystem.

## Test-MaintenanceEntryArray

Private. Validates an array of structured configuration entries.

## Test-MaintenanceEventSource

Private. Tells whether an event source is registered in a given event log.

## Test-MaintenanceIntegerValue

Private. Validates one whole-number configuration value.

## Test-MaintenancePathValue

Private. Validates one folder-path configuration value.

## Test-MaintenanceStageEnabled

Private. Reports whether configuration enables a stage.

## Test-MaintenanceStringValue

Private. Validates one text configuration value.

## Test-MaintenanceTimeout

Private. Tells whether an exception, or any exception inside it, is a time-out.

## Test-SusdbPermission

Private. Checks, before any work, which database permissions each stage has.

## Test-UpdateApproval

Private. Tells whether the current revision of an update is approved for install for a group.

## Test-UpdateIdentity

Private. Tells whether an update is named in a list of Knowledge Base numbers and update identifiers.

## Wait-MaintenanceInterval

Private. Waits for a number of seconds.

## Write-MaintenanceEvent

Private. Writes a run event to the Windows Event Log, if the event source allows it.

## Write-MaintenanceEventEntry

Private. Writes one entry to the Windows Event Log.

## Write-MaintenanceLog

Private. Appends one entry to the run log.

## Write-MaintenanceProgress

Private. Logs the progress of a stage that works item by item.

## Write-MaintenanceSummary

Private. Writes the machine-readable JSON summary of one run.
