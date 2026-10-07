#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Write-MaintenanceEvent.Failed'        = "Event {0} could not be written: {1}"
  'Write-MaintenanceEvent.NotRegistered' = 'the source is not registered in that log'
  'Write-MaintenanceEvent.Unavailable'   = "Event source '{0}' cannot be used in the '{1}' event log ({2}); this run writes no events."
}

Function Write-MaintenanceEvent {
  <#
    .SYNOPSIS
        Writes a run event to the Windows Event Log, if the event source allows it.

    .DESCRIPTION
        Maps the kind of event to its configured identifier and entry type: run started and run
        completed successfully are Information, completed with warnings and approvals made before
        their content was local are Warning, and completed with errors, a stage error, a
        precondition failure and an invalid configuration are Error. On the first event of the run
        the source is checked; when it is not registered in the configured log, or cannot be
        checked, one warning goes to the run log and the run writes no events but continues. The message passes through Protect-MaintenanceText. A failure to write an entry is
        logged and never stops the run. Nothing is written while eventLog.enabled is false.

    .PARAMETER Channel
        The channel from New-MaintenanceEventChannel.

    .PARAMETER Kind
        Kind of event; names the eventLog.eventIds key.

    .PARAMETER Message
        Entry text.

    .EXAMPLE
        Write-MaintenanceEvent -Channel $Events -Kind 'runStarted' -Message 'Run 20261101-020000-1a2b3c4d started.'

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#write-maintenanceevent',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Channel,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('runStarted', 'runSucceeded', 'runWarning', 'runFailed', 'stageError', 'preconditionFailure', 'configurationInvalid', 'lateContent')]
    [System.String]
    $Kind,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Message
  )

  Write-Debug -Message:'[Write-MaintenanceEvent] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Detail = [System.String]::Empty
  [System.Collections.Hashtable]$Private:EntryTypes = @{ runStarted = 'Information'; runSucceeded = 'Information'; runWarning = 'Warning'; runFailed = 'Error'; stageError = 'Error'; preconditionFailure = 'Error'; configurationInvalid = 'Error'; lateContent = 'Warning' }
  [System.String]$Private:Text = [System.String]::Empty

  If (($Channel.Enabled -eq $True) -and ($Null -eq $Channel.Available)) {
    Try {
      $Channel.Available = [System.Boolean](Test-MaintenanceEventSource -LogName:$Channel.LogName -Source:$Channel.Source)
      $Detail = $Script:Message['Write-MaintenanceEvent.NotRegistered']
    } Catch {
      $Channel.Available = $False
      $Detail = $PSItem.Exception.GetBaseException().Message
    }

    If ($Channel.Available -eq $False) {
      Write-MaintenanceLog -Level:'Warning' -Log:$Channel.Log -Message:($Script:Message['Write-MaintenanceEvent.Unavailable'] -f $Channel.Source, $Channel.LogName, $Detail)
    }
  }

  If (($Channel.Enabled -eq $True) -and ($Channel.Available -eq $True)) {
    $Text = Protect-MaintenanceText -Text:$Message
    # An event message is limited to about 31,000 characters.
    If ($Text.Length -gt 30000) {
      $Text = $Text.Substring(0, 30000)
    }

    Try {
      Write-MaintenanceEventEntry -EntryType:$EntryTypes[$Kind] -EventId:([System.Int32]$Channel.EventIds.$Kind) -Message:$Text -Source:$Channel.Source
      $Channel.Written = $Channel.Written + 1
    } Catch {
      Write-MaintenanceLog -Level:'Warning' -Log:$Channel.Log -Message:($Script:Message['Write-MaintenanceEvent.Failed'] -f $Channel.EventIds.$Kind, $PSItem.Exception.GetBaseException().Message)
    }
  }

  Write-Debug -Message:'[Write-MaintenanceEvent] Exiting'
}
