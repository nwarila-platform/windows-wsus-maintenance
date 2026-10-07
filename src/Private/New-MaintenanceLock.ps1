#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceLock {
  <#
    .SYNOPSIS
        Tries to take the system-wide run lock without waiting.

    .DESCRIPTION
        Opens the named mutex and tries to own it immediately. Returns the owned mutex,
        or $Null when another run owns it. A mutex left abandoned by a run that ended
        abnormally is taken over: the operating system releases a mutex when its owning
        process exits, so a crashed run never blocks the next one. Throws when the mutex
        cannot be created, which the caller reports as a precondition failure.

    .PARAMETER Name
        Mutex name, including the Global\ prefix so every session shares it.

    .EXAMPLE
        New-MaintenanceLock -Name 'Global\Invoke-WsusMaintenance'

    .OUTPUTS
        [System.Threading.Mutex]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancelock',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Threading.Mutex])]
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

  Write-Debug -Message:'[New-MaintenanceLock] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Acquired = $False
  [System.Threading.Mutex]$Private:Mutex = $Null
  [System.Threading.Mutex]$Private:Result = $Null

  $Mutex = [System.Threading.Mutex]::new($False, $Name)

  Try {
    $Acquired = $Mutex.WaitOne(0)
  } Catch [System.Threading.AbandonedMutexException] {
    $Acquired = $True
  }

  If ($Acquired -eq $True) {
    [System.Threading.Mutex]$Result = $Mutex
    $Result
  } Else {
    $Mutex.Dispose()
  }

  Write-Debug -Message:'[New-MaintenanceLock] Exiting'
}
