#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Exit-MaintenanceLock {
  <#
    .SYNOPSIS
        Releases the system-wide run lock.

    .DESCRIPTION
        Releases and disposes the lock taken by Enter-MaintenanceLock. A release that
        fails (for example because the lock was already released) still disposes the
        handle, so the lock is never left held by this run. A null lock is ignored.

    .PARAMETER Lock
        The lock returned by Enter-MaintenanceLock.

    .EXAMPLE
        Exit-MaintenanceLock -Lock $Lock

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#exit-maintenancelock',
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
    [AllowNull()]
    [System.Object]
    $Lock
  )

  Write-Debug -Message:'[Exit-MaintenanceLock] Entering'

  If ($Null -ne $Lock) {
    Try {
      $Lock.ReleaseMutex()
    } Catch {
      Write-Debug -Message:('[Exit-MaintenanceLock] Release failed: {0}' -f $PSItem.Exception.Message)
    } Finally {
      $Lock.Dispose()
    }
  }

  Write-Debug -Message:'[Exit-MaintenanceLock] Exiting'
}
