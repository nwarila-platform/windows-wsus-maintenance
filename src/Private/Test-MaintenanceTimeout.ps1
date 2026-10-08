#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceTimeout {
  <#
    .SYNOPSIS
        Tells whether an exception, or any exception inside it, is a time-out.

    .DESCRIPTION
        Walks the exception and its inner exceptions and returns true for a System.TimeoutException, a
        System.Net.WebException with the Timeout status, a SQL Server command time-out (error number -2),
        or a message that says the operation timed out. Stages use it to retry only time-outs.

    .PARAMETER Exception
        The exception to examine.

    .EXAMPLE
        Test-MaintenanceTimeout -Exception $PSItem.Exception

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancetimeout',
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
    [ValidateNotNull()]
    [System.Exception]
    $Exception
  )

  Write-Debug -Message:'[Test-MaintenanceTimeout] Entering'

  # Initialize Variable(s)
  [System.Exception]$Private:Current = $Null
  [System.Boolean]$Private:Result = $False

  $Current = $Exception
  While (($Null -ne $Current) -and ($Result -eq $False)) {
    If ($Current -is [System.TimeoutException]) {
      $Result = $True
    } ElseIf (($Current -is [System.Net.WebException]) -and ($Current.Status -eq [System.Net.WebExceptionStatus]::Timeout)) {
      $Result = $True
    } ElseIf (($Current.GetType().FullName -eq 'System.Data.SqlClient.SqlException') -and ($Current.Number -eq -2)) {
      $Result = $True
    } ElseIf ([System.Text.RegularExpressions.Regex]::IsMatch([System.String]$Current.Message, '(?i)\btime[- ]?out\b|\btimed[- ]out\b') -eq $True) {
      $Result = $True
    }

    $Current = $Current.InnerException
  }

  [System.Boolean]$Result = $Result

  $Result
  Write-Debug -Message:'[Test-MaintenanceTimeout] Exiting'
}
