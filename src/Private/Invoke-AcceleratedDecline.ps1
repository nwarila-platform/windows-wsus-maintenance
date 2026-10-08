#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Invoke-AcceleratedDecline {
  <#
    .SYNOPSIS
        Declines superseded updates of selected classifications after a shorter age.

    .DESCRIPTION
        The accelerated superseded-update policy: the same selection as the superseded-update policy,
        limited to the classifications in declines.accelerated.classifications and with its own age
        threshold, declines.accelerated.ageDays (Invoke-SupersededPolicy). Updates outside those
        classifications are never declined by it.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-AcceleratedDecline -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-accelerateddecline',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Context
  )

  Write-Debug -Message:'[Invoke-AcceleratedDecline] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = Invoke-SupersededPolicy -AgeDays:([System.Int32]$Context.Configuration.declines.accelerated.ageDays) -Classification:([System.String[]]@($Context.Configuration.declines.accelerated.classifications)) -Context:$Context

  $Result
  Write-Debug -Message:'[Invoke-AcceleratedDecline] Exiting'
}
