#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-ErrorRecord {
  <#
    .SYNOPSIS
        Creates or throws a structured PowerShell error record.

    .DESCRIPTION
        Creates an ErrorRecord using one of the maintenance exit-code ErrorIds.
        The short ErrorId is the leading segment used by the EntryPoint exit-code
        resolver.

    .PARAMETER Message
        Human-readable error message.

    .PARAMETER ErrorId
        Stable error identifier.

    .PARAMETER Exception
        Original exception to preserve as the structured error's inner
        exception.

    .PARAMETER Category
        PowerShell error category.

    .PARAMETER TargetObject
        Object related to the error.

    .PARAMETER IsFatal
        Throws the record as a terminating error instead of returning it.

    .EXAMPLE
        New-ErrorRecord -Message 'Example failure.' -ErrorId ConfigurationInvalid

    .OUTPUTS
        [System.Management.Automation.ErrorRecord]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-errorrecord',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.ErrorRecord])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.ErrorCategory]
    $Category = [System.Management.Automation.ErrorCategory]::InvalidOperation,

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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Exception]
    $Exception = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $IsFatal,

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
    [AllowNull()]
    [System.Object]
    $TargetObject = $Null
  )

  # Initialize Variable(s)
  [System.Management.Automation.ErrorRecord]$Private:ErrorRecord = $Null
  [System.InvalidOperationException]$Private:RecordException = $Null

  If ($Null -eq $Exception) {
    $RecordException = [System.InvalidOperationException]::new($Message)
  } Else {
    $RecordException = [System.InvalidOperationException]::new($Message, $Exception)
  }

  $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
    $RecordException,
    $ErrorId.ToString(),
    $Category,
    $TargetObject
  )

  If ($IsFatal.IsPresent -eq $True) {
    $PSCmdlet.ThrowTerminatingError($ErrorRecord)
  }

  $ErrorRecord
}
