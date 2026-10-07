#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceRunResult {
  <#
    .SYNOPSIS
        Creates the typed result object one maintenance run emits.

    .DESCRIPTION
        Builds the WsusMaintenance.RunResult contract. The overall status decides the
        process exit code, so the two can never disagree: Success maps to exit code 0,
        Warning to CompletedWithWarnings and Error to StageError.

    .PARAMETER Notice
        Conditions that need attention, ordered by the caller.

    .PARAMETER Run
        Run facts: stages requested with -Stage, dry-run flag, start, end, duration and
        deadline. Null for a run that only validated its configuration.

    .PARAMETER Stage
        One entry per stage that ran or was skipped.

    .PARAMETER Status
        Overall run status: Success, Warning or Error.

    .PARAMETER Validation
        Configuration validation outcome, when the run validated a configuration.

    .EXAMPLE
        New-MaintenanceRunResult -Status Success

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancerunresult',
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
    [AllowNull()]
    [PSCustomObject]
    $Run = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Stage = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Success', 'Warning', 'Error')]
    [System.String]
    $Status,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Validation = $Null
  )

  Write-Debug -Message:'[New-MaintenanceRunResult] Entering'

  # Initialize Variable(s)
  [MaintenanceExitCode]$Private:ExitCode = [MaintenanceExitCode]::Success
  [PSCustomObject]$Private:Result = $Null

  Switch ($Status) {
    'Warning' {
      $ExitCode = [MaintenanceExitCode]::CompletedWithWarnings
    }
    'Error' {
      $ExitCode = [MaintenanceExitCode]::StageError
    }
    Default {
      $ExitCode = [MaintenanceExitCode]::Success
    }
  }

  # It's always desirable to explicitly set the Result object with its desired class as close
  #   to the soft return to ensure the output is predictable and easily traceable.
  [PSCustomObject]$Result = [PSCustomObject]@{
    Status         = [System.String]$Status
    ExitCode       = [System.Int32]$ExitCode
    Stages         = [PSCustomObject[]]@($Stage)
    Notices        = [PSCustomObject[]]@($Notice)
    Run            = $Run
    Validation     = $Validation
    GeneratedAtUtc = [System.DateTime]::UtcNow
  }
  $Result.PSTypeNames.Insert(0, 'WsusMaintenance.RunResult')

  # Do a  'soft'  return by outputting the result to the pipe without using the return function
  #   which would immediately end the function,  this enables us to have the very last
  #   executing item be write-debug giving us a valuable breakpoint & enabling better
  #   debugging functionality and output.
  $Result
  Write-Debug -Message:'[New-MaintenanceRunResult] Exiting'
}
