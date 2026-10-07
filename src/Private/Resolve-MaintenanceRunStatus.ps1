#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Resolve-MaintenanceRunStatus {
  <#
    .SYNOPSIS
        Derives the overall run status.

    .DESCRIPTION
        The run status is the worst of the stage outcomes and the notices. A stage Error
        or an Error notice makes the run Error. A stage Warning, a stage the time budget
        stopped (NotRun), or a Warning or High notice makes it Warning. Skipped stages and
        Information notices leave it Success. The status decides the exit code.

    .PARAMETER Notice
        Run-level notices and the notices stages raised.

    .PARAMETER Stage
        Stage outcomes.

    .EXAMPLE
        Resolve-MaintenanceRunStatus -Stage $Outcomes -Notice $Notices

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#resolve-maintenancerunstatus',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Notice = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Stage = @()
  )

  Write-Debug -Message:'[Resolve-MaintenanceRunStatus] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Rank = 0
  [System.String]$Private:Result = [System.String]::Empty

  ForEach ($Outcome In @($Stage)) {
    If ($Outcome.Status -eq 'Error') {
      $Rank = [System.Math]::Max($Rank, 2)
    } ElseIf (@('Warning', 'NotRun') -contains $Outcome.Status) {
      $Rank = [System.Math]::Max($Rank, 1)
    }
  }

  ForEach ($Item In @($Notice)) {
    If ($Item.Severity -eq 'Error') {
      $Rank = [System.Math]::Max($Rank, 2)
    } ElseIf (@('Warning', 'High') -contains $Item.Severity) {
      $Rank = [System.Math]::Max($Rank, 1)
    }
  }

  [System.String]$Result = @('Success', 'Warning', 'Error')[$Rank]
  $Result
  Write-Debug -Message:'[Resolve-MaintenanceRunStatus] Exiting'
}
