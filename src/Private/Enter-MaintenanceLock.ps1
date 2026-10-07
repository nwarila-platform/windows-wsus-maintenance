#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Enter-MaintenanceLock.Failed' = "The run lock '{0}' could not be created: {1}"
  'Enter-MaintenanceLock.Held'   = "Another maintenance run holds the lock '{0}'. This run exits without touching WSUS or the database."
}

Function Enter-MaintenanceLock {
  <#
    .SYNOPSIS
        Takes the system-wide run lock or stops the run.

    .DESCRIPTION
        Prevents concurrent runs on one server. Returns the lock to release with
        Exit-MaintenanceLock. When another run holds the lock the run stops at once
        with the LockHeld exit code; when the lock cannot be created it stops with
        PreconditionFailed. Either way nothing has touched WSUS or the database.

    .PARAMETER Name
        Lock name.

    .EXAMPLE
        $Lock = Enter-MaintenanceLock -Name 'Global\Invoke-WsusMaintenance'

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#enter-maintenancelock',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Object])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Name
  )

  Write-Debug -Message:'[Enter-MaintenanceLock] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Lock = $Null
  [System.Object]$Private:Result = $Null

  Try {
    $Lock = New-MaintenanceLock -Name:$Name
  } Catch {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::ResourceUnavailable) `
      -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
      -Exception:$PSItem.Exception `
      -IsFatal `
      -Message:($Script:Message['Enter-MaintenanceLock.Failed'] -f $Name, $PSItem.Exception.Message) `
      -TargetObject:$Name
  }

  If ($Null -eq $Lock) {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::ResourceBusy) `
      -ErrorId:([MaintenanceExitCode]::LockHeld) `
      -IsFatal `
      -Message:($Script:Message['Enter-MaintenanceLock.Held'] -f $Name) `
      -TargetObject:$Name
  }

  [System.Object]$Result = $Lock
  $Result
  Write-Debug -Message:'[Enter-MaintenanceLock] Exiting'
}
