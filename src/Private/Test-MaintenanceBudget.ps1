#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceBudget {
  <#
    .SYNOPSIS
        Reports whether the run's time budget has been used up.

    .DESCRIPTION
        True once the deadline has passed. No stage starts after that, and a stage that
        works item by item checks this between items so it stops at a safe item boundary.
        A null deadline means the budget is unlimited.

    .PARAMETER Deadline
        Local time at which the budget runs out, or null.

    .EXAMPLE
        Test-MaintenanceBudget -Deadline $Context.Deadline

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancebudget',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
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
    $Deadline
  )

  Write-Debug -Message:'[Test-MaintenanceBudget] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Result = $False

  If ($Deadline -is [System.DateTime]) {
    $Result = (Get-MaintenanceTime) -ge $Deadline
  }

  [System.Boolean]$Result = $Result
  $Result
  Write-Debug -Message:'[Test-MaintenanceBudget] Exiting'
}
