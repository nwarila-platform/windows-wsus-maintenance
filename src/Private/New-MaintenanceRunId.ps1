#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceRunId {
  <#
    .SYNOPSIS
        Creates the unique identifier of one run.

    .DESCRIPTION
        The run identifier names the run log, the reports and the summary, and prefixes every log
        entry, so each report item can be traced to the log entries of the same run. It is the run's
        start time (local, to the second) followed by eight random hexadecimal digits, which keeps two
        runs started in the same second apart. Tests replace it to make file names predictable.

    .PARAMETER RunStart
        The run's start time, local.

    .EXAMPLE
        New-MaintenanceRunId -RunStart (Get-MaintenanceTime)

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancerunid',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $RunStart
  )

  Write-Debug -Message:'[New-MaintenanceRunId] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = '{0}-{1}' -f $RunStart.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture), [System.Guid]::NewGuid().ToString('N').Substring(0, 8)

  $Result
  Write-Debug -Message:'[New-MaintenanceRunId] Exiting'
}
