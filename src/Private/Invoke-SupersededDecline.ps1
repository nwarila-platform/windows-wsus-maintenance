#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Invoke-SupersededDecline {
  <#
    .SYNOPSIS
        Declines superseded updates older than the age threshold.

    .DESCRIPTION
        The superseded-update policy: every superseded update that is not declined and whose revision
        was created more than declines.superseded.ageDays days before the run, with approved updates
        eligible when declines.superseded.includeApproved is set and only the last level of each
        supersedence chain when declines.superseded.lastLevelOnly is set (Invoke-SupersededPolicy).

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-SupersededDecline -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-supersededdecline',
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

  Write-Debug -Message:'[Invoke-SupersededDecline] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = Invoke-SupersededPolicy -AgeDays:([System.Int32]$Context.Configuration.declines.superseded.ageDays) -Context:$Context

  $Result
  Write-Debug -Message:'[Invoke-SupersededDecline] Exiting'
}
