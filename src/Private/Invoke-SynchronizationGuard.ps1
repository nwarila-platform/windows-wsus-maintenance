#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-SynchronizationGuard.AttemptFailed' = 'Synchronization guard attempt {0} of {1} failed; status {2}.'
  'Invoke-SynchronizationGuard.DryRun'        = '{0} at start; left alone (dry run)'
  'Invoke-SynchronizationGuard.Error'         = 'not established: {0}'
  'Invoke-SynchronizationGuard.Finished'      = '{0} at start; finished before the stages'
  'Invoke-SynchronizationGuard.GaveUp'        = '{0} at start; still {2} after {1} attempt(s)'
  'Invoke-SynchronizationGuard.Idle'          = 'not running'
  'Invoke-SynchronizationGuard.Initial'       = 'Synchronization status at start: {0}.'
  'Invoke-SynchronizationGuard.ScheduleNote'  = 'automatic synchronization suspended for the run'
  'Invoke-SynchronizationGuard.Stopped'       = 'running at start; stopped by the run (attempt {0})'
  'Invoke-SynchronizationGuard.StopRequested' = 'Synchronization guard attempt {0}: stop requested.'
  'Invoke-SynchronizationGuard.Suspended'     = 'Automatic synchronization suspended for the run.'
  'Invoke-SynchronizationGuard.Unrecognized'  = 'Synchronization status {0} is not recognized; the attempt counts as failed.'
}

Function Invoke-SynchronizationGuard {
  <#
    .SYNOPSIS
        Makes sure no synchronization runs during maintenance.

    .DESCRIPTION
        Before any stage, reads the synchronization status. NotProcessing passes at once. While a
        synchronization is Running the guard asks it to stop; while it is Running or Stopping the guard
        polls every syncGuard.pollIntervalSeconds for up to syncGuard.waitSeconds per attempt. When the
        status has not reached NotProcessing, it waits syncGuard.retryDelaySeconds and tries again, up to
        syncGuard.maxAttempts attempts; a status it does not recognize counts as a failed attempt. With
        syncGuard.suspendSchedule the automatic synchronization schedule is switched off first, for the
        run. A dry run only observes: it never stops a synchronization or suspends the schedule, and it
        does not fail. Succeeded is false when the guard gave up or could not read the status; the
        caller then restores what the guard changed and stops the run with the precondition-failure
        code.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER Log
        The run log, or null.

    .PARAMETER UpdateServer
        The connected WSUS server (IUpdateServer).

    .EXAMPLE
        Invoke-SynchronizationGuard -Configuration $Effective -UpdateServer $Connection.UpdateServer -Log $Log

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-synchronizationguard',
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
    $Configuration,

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

  Write-Debug -Message:'[Invoke-SynchronizationGuard] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Attempts = 0
  [System.Boolean]$Private:DryRun = $False
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Boolean]$Private:Found = $False
  [System.String]$Private:Initial = [System.String]::Empty
  [System.Boolean]$Private:ScheduleSuspended = $False
  [System.Object]$Private:Settings = $Null
  [System.Int32]$Private:Slice = 0
  [System.String]$Private:Status = [System.String]::Empty
  [System.Boolean]$Private:StopRequested = $False
  [System.Object]$Private:Subscription = $Null
  [System.Boolean]$Private:Succeeded = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Int32]$Private:Waited = 0
  [PSCustomObject]$Private:Result = $Null

  $Settings = $Configuration.syncGuard
  $DryRun = [System.Boolean]$Configuration.run.dryRun

  Try {
    $Subscription = $UpdateServer.GetSubscription()
    If (($Settings.suspendSchedule -eq $True) -and ($DryRun -eq $False) -and ($Subscription.SynchronizeAutomatically -eq $True)) {
      $Subscription.SynchronizeAutomatically = $False
      $Subscription.Save()
      $ScheduleSuspended = $True
      Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:$Script:Message['Invoke-SynchronizationGuard.Suspended']
    }

    For ($Attempt = 1; $Attempt -le $Settings.maxAttempts; $Attempt++) {
      $Attempts = $Attempt
      $Status = [System.String]$Subscription.GetSynchronizationStatus()
      If ($Attempt -eq 1) {
        $Initial = $Status
        $Found = @('Running', 'Stopping') -contains $Status
        Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-SynchronizationGuard.Initial'] -f $Status)
      }

      If (($Status -eq 'NotProcessing') -or ($DryRun -eq $True)) {
        $Succeeded = $True
        Break
      }

      If (@('Running', 'Stopping') -contains $Status) {
        If ($Status -eq 'Running') {
          $Subscription.StopSynchronization()
          $StopRequested = $True
          Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-SynchronizationGuard.StopRequested'] -f $Attempt)
        }

        $Waited = 0
        While (($Waited -lt $Settings.waitSeconds) -and ($Succeeded -eq $False)) {
          $Slice = [System.Math]::Min([System.Int32]$Settings.pollIntervalSeconds, [System.Int32]($Settings.waitSeconds - $Waited))
          Wait-MaintenanceInterval -Seconds:$Slice
          $Waited = $Waited + $Slice
          $Status = [System.String]$Subscription.GetSynchronizationStatus()
          $Succeeded = $Status -eq 'NotProcessing'
        }

        If ($Succeeded -eq $True) {
          Break
        }
      } Else {
        Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-SynchronizationGuard.Unrecognized'] -f $Status)
      }

      Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-SynchronizationGuard.AttemptFailed'] -f $Attempt, $Settings.maxAttempts, $Status)
      If ($Attempt -lt $Settings.maxAttempts) {
        Wait-MaintenanceInterval -Seconds:([System.Int32]$Settings.retryDelaySeconds)
      }
    }
  } Catch {
    $Succeeded = $False
    $ErrorText = $PSItem.Exception.GetBaseException().Message
  }

  If ([System.String]::IsNullOrEmpty($ErrorText) -eq $False) {
    $Summary = $Script:Message['Invoke-SynchronizationGuard.Error'] -f $ErrorText
  } ElseIf ($Succeeded -eq $False) {
    $Summary = $Script:Message['Invoke-SynchronizationGuard.GaveUp'] -f $Initial, $Attempts, $Status
  } ElseIf (($Found -eq $True) -and ($DryRun -eq $True)) {
    $Summary = $Script:Message['Invoke-SynchronizationGuard.DryRun'] -f $Initial
  } ElseIf ($StopRequested -eq $True) {
    $Summary = $Script:Message['Invoke-SynchronizationGuard.Stopped'] -f $Attempts
  } ElseIf ($Found -eq $True) {
    $Summary = $Script:Message['Invoke-SynchronizationGuard.Finished'] -f $Initial
  } Else {
    $Summary = $Script:Message['Invoke-SynchronizationGuard.Idle']
  }

  If ($ScheduleSuspended -eq $True) {
    $Summary = '{0}; {1}' -f $Summary, $Script:Message['Invoke-SynchronizationGuard.ScheduleNote']
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Initial           = [System.String]$Initial
    Found             = [System.Boolean]$Found
    StopRequested     = [System.Boolean]$StopRequested
    Succeeded         = [System.Boolean]$Succeeded
    Attempts          = [System.Int32]$Attempts
    LastStatus        = [System.String]$Status
    ScheduleSuspended = [System.Boolean]$ScheduleSuspended
    Summary           = [System.String]$Summary
    Error             = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Invoke-SynchronizationGuard] Exiting'
}
