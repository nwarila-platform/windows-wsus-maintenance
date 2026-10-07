#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceList {
  <#
    .SYNOPSIS
        Splits command-line values that hold comma-separated lists.

    .DESCRIPTION
        Returns every value of the option split at its commas, with the surrounding spaces removed and
        empty parts dropped, so that "-Stage Backup,Reindex" means the same whether the shell passed one
        string or two. powershell.exe -File, which a scheduled task uses, passes each argument as one
        literal string:
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_powershell_exe

    .PARAMETER Value
        The values given for the option.

    .EXAMPLE
        ConvertTo-MaintenanceList -Value @('Backup,Reindex')

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenancelist',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Value
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceList] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.String[]]$Private:Result = @()

  $Items = [System.Collections.Generic.List[System.String]]::new()
  ForEach ($Entry In $Value) {
    ForEach ($Part In ([System.String]$Entry -split ',')) {
      If ([System.String]::IsNullOrWhiteSpace($Part) -eq $False) {
        $Items.Add($Part.Trim())
      }
    }
  }

  [System.String[]]$Result = $Items.ToArray()

  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceList] Exiting'
}
