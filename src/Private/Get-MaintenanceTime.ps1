#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceTime {
  <#
    .SYNOPSIS
        Returns the current local time.

    .DESCRIPTION
        The single clock the script reads: the run's start time, every later time-budget
        check, and the timestamps in the run log, the reports and the summary. Tests
        replace it to control time.

    .EXAMPLE
        Get-MaintenanceTime

    .OUTPUTS
        [System.DateTime]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancetime',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.DateTime])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceTime] Entering'

  # Initialize Variable(s)
  [System.DateTime]$Private:Result = [System.DateTime]::MinValue

  [System.DateTime]$Result = [System.DateTime]::Now
  $Result
  Write-Debug -Message:'[Get-MaintenanceTime] Exiting'
}
