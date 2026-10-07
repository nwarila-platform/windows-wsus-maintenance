#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceRunRecord {
  <#
    .SYNOPSIS
        Records the facts of one run for the result, the report and the summary.

    .DESCRIPTION
        Captures the run identifier, the stages listed with -Stage (empty for a full run), the dry-run
        flag, the start and completion times (completion is now), the duration and the time-budget
        deadline. The Artifacts member is filled in once the log, reports and summary are written.

    .PARAMETER Deadline
        Time-budget deadline, or null when unlimited.

    .PARAMETER DryRun
        Whether the run simulated its changes.

    .PARAMETER RunId
        Run identifier.

    .PARAMETER RunStart
        The run's start time, local.

    .PARAMETER Stage
        Stages listed with -Stage.

    .EXAMPLE
        New-MaintenanceRunRecord -RunId $RunId -RunStart $RunStart -Stage $Resolution.Stages -DryRun $True

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancerunrecord',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Deadline = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Boolean]
    $DryRun = $False,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $RunId,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $RunStart,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Stage = @()
  )

  Write-Debug -Message:'[New-MaintenanceRunRecord] Entering'

  # Initialize Variable(s)
  [System.DateTime]$Private:CompletedAt = [System.DateTime]::MinValue
  [PSCustomObject]$Private:Result = $Null

  $CompletedAt = Get-MaintenanceTime

  [PSCustomObject]$Result = [PSCustomObject]@{
    RunId           = [System.String]$RunId
    Stages          = [System.String[]]@($Stage)
    DryRun          = [System.Boolean]$DryRun
    StartedAt       = $RunStart
    CompletedAt     = $CompletedAt
    DurationSeconds = [System.Double][System.Math]::Max([System.Double]0, ($CompletedAt - $RunStart).TotalSeconds)
    Deadline        = $Deadline
    Artifacts       = $Null
  }

  $Result
  Write-Debug -Message:'[New-MaintenanceRunRecord] Exiting'
}
