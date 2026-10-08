#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-SusdbIndexAction {
  <#
    .SYNOPSIS
        Chooses how to defragment one index, as Microsoft's WSUS re-index script does.

    .DESCRIPTION
        Applies the decision of Microsoft's re-index script for SUSDB to one selected index: reorganize
        when the page density is between 75 and 85 percent and the index has a fill factor set, or when
        fragmentation is below 30 percent; otherwise rebuild with a fill factor of 90 when the index has
        at least 5,000 rows and no fill factor set; otherwise rebuild.

    .PARAMETER Density
        Average page space used, in percent.

    .PARAMETER FillFactor
        The index fill factor; 0 means not set.

    .PARAMETER Fragmentation
        Average fragmentation, in percent.

    .PARAMETER RecordCount
        Rows in the index.

    .EXAMPLE
        Get-SusdbIndexAction -Density 70.2 -FillFactor 0 -Fragmentation 45.0 -RecordCount 12000

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-susdbindexaction',
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
    [System.Double]
    $Density,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 100)]
    [System.Int32]
    $FillFactor,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Double]
    $Fragmentation,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Int64]
    $RecordCount
  )

  Write-Debug -Message:'[Get-SusdbIndexAction] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  # The same decision as the re-index script Microsoft publishes for SUSDB:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/reindex-the-wsus-database
  If ((($Density -ge 75.0) -and ($Density -le 85.0) -and ($FillFactor -ne 0)) -or ($Fragmentation -lt 30.0)) {
    [System.String]$Result = 'Reorganize'
  } ElseIf (($RecordCount -ge 5000) -and ($FillFactor -eq 0)) {
    [System.String]$Result = 'RebuildWithFillFactor'
  } Else {
    [System.String]$Result = 'Rebuild'
  }

  $Result
  Write-Debug -Message:'[Get-SusdbIndexAction] Exiting'
}
