#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Stop-MaintenanceRun.Stopped' = 'The run stopped at the {0}: {1}'
}

Function Stop-MaintenanceRun {
  <#
    .SYNOPSIS
        Ends a run that failed a precondition, after reporting the failure.

    .DESCRIPTION
        Logs the failure, publishes a failure report and summary that state what happened, the point
        the run reached and what to do (Publish-MaintenanceRunOutput, which also writes the matching
        event), and then throws the error record whose identifier decides the exit code. Nothing has
        been changed on the server when this is called.

    .PARAMETER Category
        Error category of the thrown record.

    .PARAMETER Discovery
        Discovered facts for the report header, or null.

    .PARAMETER ErrorId
        PreconditionFailed or ConfigurationInvalid.

    .PARAMETER Guidance
        What to do about it.

    .PARAMETER Message
        What happened.

    .PARAMETER Notice
        Notices of the run so far.

    .PARAMETER Output
        The run output from Open-MaintenanceRunOutput.

    .PARAMETER Point
        The point the run reached.

    .PARAMETER Run
        The run record (New-MaintenanceRunRecord).

    .PARAMETER TargetObject
        Target object of the thrown record.

    .PARAMETER Validation
        The validation summary.

    .EXAMPLE
        Stop-MaintenanceRun -ErrorId ([MaintenanceExitCode]::PreconditionFailed) -Category PermissionDenied -Point 'elevation check' -Message $Text -Guidance $Advice -Output $Output -Run $Record -Validation $Summary

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#stop-maintenancerun',
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
    [System.Management.Automation.ErrorCategory]
    $Category,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Discovery = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [MaintenanceExitCode]
    $ErrorId,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Guidance,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Message,

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
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Output,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Point,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Run,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $TargetObject = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Validation
  )

  Write-Debug -Message:'[Stop-MaintenanceRun] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Failure = $Null

  Write-MaintenanceLog -Level:'Error' -Log:$Output.Log -Message:($Script:Message['Stop-MaintenanceRun.Stopped'] -f $Point, $Message)

  $Failure = [PSCustomObject]@{
    Kind     = [System.String]$ErrorId
    Point    = [System.String]$Point
    Message  = [System.String]$Message
    Guidance = [System.String]$Guidance
  }

  $Null = Publish-MaintenanceRunOutput `
    -Discovery:$Discovery `
    -ExitCode:([System.Int32]$ErrorId) `
    -Failure:$Failure `
    -Notice:$Notice `
    -Output:$Output `
    -Run:$Run `
    -Status:'Error' `
    -Validation:$Validation

  New-ErrorRecord `
    -Category:$Category `
    -ErrorId:$ErrorId `
    -IsFatal `
    -Message:$Message `
    -TargetObject:$TargetObject

  Write-Debug -Message:'[Stop-MaintenanceRun] Exiting'
}
