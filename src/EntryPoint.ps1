#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Runs unattended maintenance for a Windows Server Update Services server.

  .DESCRIPTION
      Invoke-WsusMaintenance.ps1 is assembled by build.ps1 from the sources under src/.
      It emits one WsusMaintenance.RunResult object and exits with the code documented
      in docs/reference/cli-contract.md.

  .PARAMETER ConfigPath
      Configuration document to read. Defaults to
      %ProgramData%\NWarila\WsusMaintenance\maintenance.json.

  .PARAMETER DryRun
      Report intended changes without changing anything.

  .PARAMETER ReportFolder
      Report folder for this run.

  .PARAMETER ReportFormat
      Report formats for this run: Text, Html, or both.

  .PARAMETER Stage
      Run only these stages, in their fixed order. Without it every enabled stage runs.

  .PARAMETER ValidateOnly
      Validate the configuration and options, then stop.

  .PARAMETER Verbosity
      Log verbosity for this run.

  .EXAMPLE
      .\Invoke-WsusMaintenance.ps1 -ConfigPath 'D:\Maintenance\maintenance.json' -ValidateOnly
#>
[CmdletBinding(
  ConfirmImpact = 'None',
  DefaultParameterSetName = 'default',
  HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/cli-contract.md',
  PositionalBinding = $False,
  SupportsPaging = $False,
  SupportsShouldProcess = $False
)]
Param (
  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $ConfigPath,

  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [System.Management.Automation.SwitchParameter]
  $DryRun,

  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $ReportFolder,

  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [ValidateSet('Text', 'Html')]
  [System.String[]]
  $ReportFormat,

  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [ValidateNotNullOrEmpty()]
  [System.String[]]
  $Stage,

  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [System.Management.Automation.SwitchParameter]
  $ValidateOnly,

  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
  [System.String]
  $Verbosity
)

# This file is not a function. build.ps1 folds this body after the merged
# Private/Public function definitions.

Trap {
  # Anything that reaches the trap is unhandled. It exits with StageError, never Success.
  $Script:ExitCode = [System.Int32][MaintenanceExitCode]::StageError
  Write-Error -ErrorRecord $PSItem -ErrorAction Continue

  Exit ([System.Int32]$Script:ExitCode)
}

#region Initialization

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$Script:ExitCode = [System.Int32][MaintenanceExitCode]::Success

$EnvironmentContext = [PSCustomObject]@{
  Platform  = [System.Environment]::OSVersion.Platform.ToString()
  PSVersion = $PSVersionTable.PSVersion.ToString()
}

Write-Debug -Message:(
  '[EntryPoint] Runtime context: PowerShell {0} on {1}' -f
  $EnvironmentContext.PSVersion,
  $EnvironmentContext.Platform
)

#endregion

#region Execution

# Forward exactly the options the caller gave, so the orchestrator can tell a default from a choice.
$MaintenanceParameters = @{}
ForEach ($BoundName In $PSBoundParameters.Keys) {
  $MaintenanceParameters[$BoundName] = $PSBoundParameters[$BoundName]
}

Try {
  Write-Debug -Message '[EntryPoint] Invoking Invoke-WsusMaintenance'
  $Result = Invoke-WsusMaintenance @MaintenanceParameters

  If ($Null -ne $Result) {
    $Result
    $Script:ExitCode = [System.Int32]$Result.ExitCode
  }

  Write-Debug -Message ('[EntryPoint] Exiting with code {0}' -f $Script:ExitCode)
  Exit ([System.Int32]$Script:ExitCode)
} Catch {
  # Map a known maintenance ErrorId to its process exit code. The short id is the leading segment
  #   before the first comma (ThrowTerminatingError appends ",<FunctionName>"). Success and unknown
  #   ids resolve to $Null, so the Throw below routes them to the trap as unhandled (StageError).
  $ShortErrorId = ([System.String]$PSItem.FullyQualifiedErrorId -split ',', 2)[0]
  $ResolvedExitCode = $Null

  If ([System.Enum]::IsDefined([MaintenanceExitCode], $ShortErrorId) -eq $True) {
    $CandidateExitCode = [MaintenanceExitCode]$ShortErrorId

    If ($CandidateExitCode -ne [MaintenanceExitCode]::Success) {
      $ResolvedExitCode = [System.Int32]$CandidateExitCode
    }
  }

  If ($Null -ne $ResolvedExitCode) {
    $Script:ExitCode = [System.Int32]$ResolvedExitCode
    Write-Error -ErrorRecord $PSItem -ErrorAction Continue
    Exit ([System.Int32]$Script:ExitCode)
  }

  Throw
}

#endregion
