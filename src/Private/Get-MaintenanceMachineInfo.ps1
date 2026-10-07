#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceMachineInfo {
  <#
    .SYNOPSIS
        Reports the computer model and its logical-processor count.

    .DESCRIPTION
        A seam around Win32_ComputerSystem, so that tests can replace it. Returns the manufacturer and
        model, which tell a virtual machine from a physical one, and the number of logical processors.

    .EXAMPLE
        Get-MaintenanceMachineInfo

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancemachineinfo',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceMachineInfo] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:System = $Null
  [PSCustomObject]$Private:Result = $Null

  $System = Get-CimInstance -ClassName:'Win32_ComputerSystem' -ErrorAction:'Stop' -Verbose:$False
  [PSCustomObject]$Result = [PSCustomObject]@{
    Manufacturer      = [System.String]$System.Manufacturer
    Model             = [System.String]$System.Model
    LogicalProcessors = [System.Int32]$System.NumberOfLogicalProcessors
  }

  $Result
  Write-Debug -Message:'[Get-MaintenanceMachineInfo] Exiting'
}
