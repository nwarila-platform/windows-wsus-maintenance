#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Resolve-MaintenancePath {
  <#
    .SYNOPSIS
        Expands environment variables in a configured folder path.

    .DESCRIPTION
        Configuration paths may start with one %VARIABLE% (for example %ProgramData%);
        this expands it for the account the run executes under. Paths are otherwise
        returned unchanged.

    .PARAMETER Path
        The configured path.

    .EXAMPLE
        Resolve-MaintenancePath -Path '%ProgramData%\NWarila\WsusMaintenance\State'

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#resolve-maintenancepath',
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
    [System.String]
    $Path
  )

  Write-Debug -Message:'[Resolve-MaintenancePath] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = [System.Environment]::ExpandEnvironmentVariables($Path)
  $Result
  Write-Debug -Message:'[Resolve-MaintenancePath] Exiting'
}
