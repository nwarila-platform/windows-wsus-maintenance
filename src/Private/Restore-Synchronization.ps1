#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Restore-Synchronization.Restarted'           = 'restarted after the run'
  'Restore-Synchronization.RestartedLog'        = 'Synchronization restarted.'
  'Restore-Synchronization.RestartFailed'       = 'The synchronization the run stopped could not be restarted: {0}'
  'Restore-Synchronization.RestartFailedPart'   = 'restart failed: {0}'
  'Restore-Synchronization.ScheduleFailed'      = 'The automatic synchronization schedule could not be switched back on: {0}'
  'Restore-Synchronization.ScheduleFailedPart'  = 'automatic synchronization not restored: {0}'
  'Restore-Synchronization.ScheduleRestored'    = 'automatic synchronization restored'
  'Restore-Synchronization.ScheduleRestoredLog' = 'Automatic synchronization restored.'
  'Restore-Synchronization.StillActive'         = 'not restarted: status {0}'
}

Function Restore-Synchronization {
  <#
    .SYNOPSIS
        Restarts the synchronization the run stopped and restores the schedule it suspended.

    .DESCRIPTION
        Called after the last stage, or after a stop that follows the synchronization guard. When the
        guard stopped a synchronization, starts a new one once the status is NotProcessing; a
        synchronization that is still running is left as it is. When the guard suspended the automatic
        synchronization schedule, switches it back on. A failure to restart or to restore raises a
        Warning notice and never stops the run. Summary extends the guard's summary with what was done.

    .PARAMETER Guard
        Result of Invoke-SynchronizationGuard.

    .PARAMETER Log
        The run log, or null.

    .PARAMETER UpdateServer
        The connected WSUS server (IUpdateServer).

    .EXAMPLE
        Restore-Synchronization -Guard $Guard -UpdateServer $Connection.UpdateServer -Log $Log

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#restore-synchronization',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
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
    $Guard,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Log = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [System.Object]
    $UpdateServer
  )

  Write-Debug -Message:'[Restore-Synchronization] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Collections.Generic.List[System.String]]$Private:Parts = $Null
  [System.Boolean]$Private:Restarted = $False
  [System.Boolean]$Private:ScheduleRestored = $False
  [System.String]$Private:Status = [System.String]::Empty
  [System.Object]$Private:Subscription = $Null
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Parts = [System.Collections.Generic.List[System.String]]::new()

  If ($Guard.StopRequested -eq $True) {
    Try {
      $Subscription = $UpdateServer.GetSubscription()
      $Status = [System.String]$Subscription.GetSynchronizationStatus()
      If ($Status -eq 'NotProcessing') {
        $Subscription.StartSynchronization()
        $Restarted = $True
        $Parts.Add($Script:Message['Restore-Synchronization.Restarted'])
        Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:$Script:Message['Restore-Synchronization.RestartedLog']
      } Else {
        $Parts.Add(($Script:Message['Restore-Synchronization.StillActive'] -f $Status))
      }
    } Catch {
      $Parts.Add(($Script:Message['Restore-Synchronization.RestartFailedPart'] -f $PSItem.Exception.GetBaseException().Message))
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Restore-Synchronization.RestartFailed'] -f $PSItem.Exception.GetBaseException().Message) -Severity:'Warning'))
    }
  }

  If ($Guard.ScheduleSuspended -eq $True) {
    Try {
      $Subscription = $UpdateServer.GetSubscription()
      $Subscription.SynchronizeAutomatically = $True
      $Subscription.Save()
      $ScheduleRestored = $True
      $Parts.Add($Script:Message['Restore-Synchronization.ScheduleRestored'])
      Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:$Script:Message['Restore-Synchronization.ScheduleRestoredLog']
    } Catch {
      $Parts.Add(($Script:Message['Restore-Synchronization.ScheduleFailedPart'] -f $PSItem.Exception.GetBaseException().Message))
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Restore-Synchronization.ScheduleFailed'] -f $PSItem.Exception.GetBaseException().Message) -Severity:'Warning'))
    }
  }

  $Summary = $Guard.Summary
  If ($Parts.Count -gt 0) {
    $Summary = '{0}; {1}' -f $Summary, ($Parts -join '; ')
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Restarted        = [System.Boolean]$Restarted
    ScheduleRestored = [System.Boolean]$ScheduleRestored
    Notices          = [PSCustomObject[]]$Notices.ToArray()
    Summary          = [System.String]$Summary
  }

  $Result
  Write-Debug -Message:'[Restore-Synchronization] Exiting'
}
