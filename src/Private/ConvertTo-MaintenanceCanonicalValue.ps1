#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceCanonicalValue {
  <#
    .SYNOPSIS
        Gives a command-line value the spelling the configuration uses.

    .DESCRIPTION
        Returns the allowed value that equals the given one without regard to case, so that
        -Verbosity debug means Debug, as PowerShell matches parameter values; a value that matches none
        is returned unchanged, for validation to report.

    .PARAMETER Allowed
        The values the configuration allows.

    .PARAMETER Value
        The value given on the command line.

    .EXAMPLE
        ConvertTo-MaintenanceCanonicalValue -Value 'debug' -Allowed @('Error', 'Warning', 'Information', 'Verbose', 'Debug')

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenancecanonicalvalue',
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
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $Allowed,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Value
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceCanonicalValue] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = $Value
  ForEach ($Candidate In $Allowed) {
    If ($Candidate -ieq $Value) {
      [System.String]$Result = $Candidate
    }
  }

  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceCanonicalValue] Exiting'
}
