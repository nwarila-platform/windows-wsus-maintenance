# Functions

Every function in `src/`, in alphabetical order. Each function's `HelpUri` links to its entry
here; the comment-based help in the source is the full reference.

## Connect-MaintenanceServer

Private. Connects to the WSUS administration interface and to SUSDB.

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

## Disconnect-MaintenanceServer

Private. Closes the SUSDB connection of a run.

## Enter-MaintenanceLock

Private. Takes the system-wide run lock or stops the run.

## Exit-MaintenanceLock

Private. Releases the system-wide run lock.

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

## Get-WsusEnvironment

Private. Discovers where SUSDB lives and whether this server is a supported combination.

## Get-WsusServerRole

Private. Detects the server tier: top tier, autonomous downstream or replica downstream.

## Get-WsusSetupValue

Private. Reads the values WSUS setup records in the registry.

## Get-WsusUpdateServer

Private. Connects to the WSUS administration interface.

## Initialize-MaintenanceFolder

Private. Makes sure a folder exists and can be written.

## Invoke-MaintenanceRun

Private. Plans and executes the stages of one run.

## Invoke-MaintenanceStage

Private. Runs one planned stage inside its own error boundary.

## Invoke-SusdbCommand

Private. Runs one parameterized command against SUSDB.

## Invoke-SynchronizationGuard

Private. Makes sure no synchronization runs during maintenance.

## Invoke-WsusMaintenance

Public. Runs one unattended WSUS maintenance pass.

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

## New-SqlConnection

Private. Opens a connection to SQL Server.

## New-SusdbMessageHandler

Private. Creates the handler that collects the messages a database command prints.

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

## Stop-MaintenanceRun

Private. Ends a run that failed a precondition, after reporting the failure.

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

## Test-SusdbPermission

Private. Checks, before any work, which database permissions each stage has.

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
