#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceStageResult {
  <#
    .SYNOPSIS
        Creates the result a stage handler returns.

    .DESCRIPTION
        Gives every stage the same result shape: a status (Success, Warning or Error), named counts,
        the items it acted on (or would act on in a dry run), a one-line message and the notices it
        raised. Invoke-MaintenanceStage turns this into the stage outcome.

    .PARAMETER Counts
        Named counts, in report order.

    .PARAMETER Item
        One text per item acted on.

    .PARAMETER Message
        One-line summary.

    .PARAMETER Notice
        Notices raised by the stage.

    .PARAMETER Status
        Stage status.

    .EXAMPLE
        New-MaintenanceStageResult -Status 'Success' -Message 'Nothing to do.'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancestageresult',
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
    [System.Collections.Specialized.OrderedDictionary]
    $Counts = $Null,

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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Success', 'Warning', 'Error')]
    [System.String]
    $Status = 'Success'
  )

  Write-Debug -Message:'[New-MaintenanceStageResult] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = [PSCustomObject]@{
    Status  = [System.String]$Status
    Counts  = $Counts
    Items   = [System.String[]]@($Item)
    Message = [System.String]$Message
    Notices = [PSCustomObject[]]@($Notice)
  }

  $Result
  Write-Debug -Message:'[New-MaintenanceStageResult] Exiting'
}
