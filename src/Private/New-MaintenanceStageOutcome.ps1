#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceStageOutcome {
  <#
    .SYNOPSIS
        Creates the record of what one stage did.

    .DESCRIPTION
        One outcome per stage in the plan, whether it ran or not. Status is Success,
        Warning or Error for a stage that ran, Skipped for one that did not need to run,
        and NotRun for one the time budget stopped from starting.

    .PARAMETER Counts
        Stage-specific counters.

    .PARAMETER DurationSeconds
        How long the stage ran.

    .PARAMETER ErrorMessage
        Error text, for a stage that failed.

    .PARAMETER ErrorTime
        When the error happened.

    .PARAMETER Item
        Items the stage acted on (or would act on, in a dry run), one text per item.

    .PARAMETER Message
        One-line summary from the stage.

    .PARAMETER Notice
        Notices the stage raised.

    .PARAMETER Reason
        Why the stage ran, or why it did not.

    .PARAMETER Stage
        The plan entry.

    .PARAMETER StartedAt
        When the stage started.

    .PARAMETER Status
        Success, Warning, Error, Skipped or NotRun.

    .EXAMPLE
        New-MaintenanceStageOutcome -Stage $Entry -Status 'Skipped' -Reason $Entry.Reason

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancestageoutcome',
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
    $Counts = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, [System.Double]::MaxValue)]
    [System.Double]
    $DurationSeconds = 0,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $ErrorMessage = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $ErrorTime = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Item = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Message = '',

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
    [AllowEmptyString()]
    [System.String]
    $Reason,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Stage,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $StartedAt = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Success', 'Warning', 'Error', 'Skipped', 'NotRun')]
    [System.String]
    $Status
  )

  Write-Debug -Message:'[New-MaintenanceStageOutcome] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = [PSCustomObject]@{
    Name            = [System.String]$Stage.Name
    Order           = [System.Int32]$Stage.Order
    Status          = [System.String]$Status
    Reason          = [System.String]$Reason
    StartedAt       = $StartedAt
    DurationSeconds = [System.Double]$DurationSeconds
    Counts          = $Counts
    Message         = [System.String]$Message
    Items           = [System.String[]]@($Item)
    Notices         = [PSCustomObject[]]@($Notice)
    ErrorMessage    = [System.String]$ErrorMessage
    ErrorTime       = $ErrorTime
  }
  $Result.PSTypeNames.Insert(0, 'WsusMaintenance.StageOutcome')

  $Result
  Write-Debug -Message:'[New-MaintenanceStageOutcome] Exiting'
}
