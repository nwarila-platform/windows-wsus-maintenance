#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Select-SupersededUpdate {
  <#
    .SYNOPSIS
        Selects the superseded updates a superseded-update policy declines.

    .DESCRIPTION
        Walks the undeclined updates of the catalog that no earlier policy of the run has taken, keeps
        the superseded ones (optionally only in the given classifications), and selects those whose
        revision creation date is older than the age threshold, as Microsoft's superseded-update script
        does. It leaves out updates on the never-decline list, intermediate updates of a supersedence chain
        (updates that supersede others) when last-level-only is set, and approved updates when approved
        updates are not eligible, and counts each group for the report.

    .PARAMETER AgeDays
        Age threshold in days; newer revisions are kept.

    .PARAMETER Catalog
        The decline catalog of the run (Get-DeclineCatalog).

    .PARAMETER Classification
        Classification titles to limit the policy to; empty means all.

    .PARAMETER IncludeApproved
        Whether approved superseded updates are eligible.

    .PARAMETER LastLevelOnly
        Whether only the last level of each supersedence chain is eligible.

    .PARAMETER NeverDecline
        Knowledge Base numbers and update GUIDs that are never declined.

    .PARAMETER Now
        Run start in UTC.

    .EXAMPLE
        Select-SupersededUpdate -AgeDays 90 -Catalog $Catalog -IncludeApproved $True -LastLevelOnly $False -Now $Now

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#select-supersededupdate',
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
    [System.Int32]
    $AgeDays,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Catalog,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Classification = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Boolean]
    $IncludeApproved,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Boolean]
    $LastLevelOnly,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $NeverDecline = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $Now
  )

  Write-Debug -Message:'[Select-SupersededUpdate] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Approved = 0
  [System.Collections.Generic.List[PSCustomObject]]$Private:Candidates = $Null
  [System.DateTime]$Private:Cutoff = [System.DateTime]::MinValue
  [System.Int32]$Private:Intermediate = 0
  [System.Int32]$Private:Protected = 0
  [System.Int32]$Private:Superseded = 0
  [System.Int32]$Private:Within = 0
  [PSCustomObject]$Private:Result = $Null

  # The selection follows Microsoft's superseded-update decline script:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/decline-superseded-updates
  $Cutoff = $Now.AddDays(-$AgeDays)
  $Candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
  ForEach ($Record In $Catalog.Records) {
    If (($Catalog.Claimed.Contains($Record.Id) -eq $True) -or ($Record.IsSuperseded -eq $False)) {
      Continue
    }

    If (($Classification.Count -gt 0) -and ($Classification -notcontains $Record.ClassificationTitle)) {
      Continue
    }

    $Superseded++
    If ((Test-UpdateIdentity -Identity:$NeverDecline -Record:$Record) -eq $True) {
      $Protected++
    } ElseIf ($Record.CreationDate -ge $Cutoff) {
      $Within++
    } ElseIf (($LastLevelOnly -eq $True) -and ($Record.SupersedesOthers -eq $True)) {
      $Intermediate++
    } ElseIf (($IncludeApproved -eq $False) -and ($Record.IsApproved -eq $True)) {
      $Approved++
    } Else {
      $Candidates.Add($Record)
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Candidates       = [PSCustomObject[]]$Candidates.ToArray()
    Superseded       = [System.Int32]$Superseded
    WithinThreshold  = [System.Int32]$Within
    IntermediateKept = [System.Int32]$Intermediate
    ApprovedKept     = [System.Int32]$Approved
    Protected        = [System.Int32]$Protected
  }

  $Result
  Write-Debug -Message:'[Select-SupersededUpdate] Exiting'
}
