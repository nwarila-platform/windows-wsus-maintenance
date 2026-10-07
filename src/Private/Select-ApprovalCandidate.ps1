#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Select-ApprovalCandidate.SupersedenceFailed' = 'supersedence not checked, left unapproved: {0}: {1}'
}

Function Select-ApprovalCandidate {
  <#
    .SYNOPSIS
        Selects the updates the approval stages consider.

    .DESCRIPTION
        From the approval catalog, keeps the updates that at least one client needs and that are not
        expired (an expired update can only be approved for removal), leaves out every update in the
        Upgrades classification, in approval.excludedClassifications or on approval.neverApprove, and
        then leaves out a superseded update when an update that supersedes it
        (IUpdate.GetRelatedUpdates with UpdatesThatSupersedeThisUpdate) is approved or is itself a
        candidate. WSUS infrastructure updates come first, because Microsoft notes that other updates
        cannot be approved until the WSUS server update is; the rest follow by revision creation date.
        The selection is computed once per run and kept in the catalog.

    .PARAMETER Catalog
        The approval catalog of the run (Get-ApprovalCatalog).

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Select-ApprovalCandidate -Catalog $Catalog -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#select-approvalcandidate',
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
    $Catalog,

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

  Write-Debug -Message:'[Select-ApprovalCandidate] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:Candidates = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Eligible = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:EligibleIds = $Null
  [System.String[]]$Private:Excluded = @()
  [System.Int32]$Private:ExcludedCount = 0
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.String[]]$Private:NeverApprove = @()
  [System.Object]$Private:Settings = $Null
  [System.Boolean]$Private:Skip = $False
  [System.Int32]$Private:SupersededCount = 0
  [PSCustomObject]$Private:Result = $Null

  If ($Null -ne $Catalog.Selection) {
    [PSCustomObject]$Result = $Catalog.Selection
  } Else {
    $Settings = $Context.Configuration.approval
    $NeverApprove = [System.String[]]@($Settings.neverApprove)
    $Excluded = [System.String[]](@('Upgrades') + @($Settings.excludedClassifications | Where-Object -FilterScript:({ $Null -ne $PSItem })))
    $Eligible = [System.Collections.Generic.List[PSCustomObject]]::new()
    $EligibleIds = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Failures = [System.Collections.Generic.List[System.String]]::new()

    ForEach ($Record In $Catalog.Records) {
      If (($Catalog.Needed.ContainsKey($Record.Id) -eq $False) -or ($Catalog.Needed[$Record.Id] -le 0) -or ($Record.IsExpired -eq $True)) {
        Continue
      }

      If (((Test-UpdateIdentity -Identity:$NeverApprove -Record:$Record) -eq $True) -or ($Excluded -contains $Record.ClassificationTitle)) {
        $ExcludedCount++
      } Else {
        $Eligible.Add($Record)
        $Null = $EligibleIds.Add($Record.Id)
      }
    }

    # Supersedence: https://learn.microsoft.com/previous-versions/windows/desktop/ms747148(v=vs.85)
    # WSUS server updates first:
    #   https://learn.microsoft.com/windows-server/administration/windows-server-update-services/manage/updates-operations
    ForEach ($Record In $Eligible) {
      $Skip = $False
      If ($Record.IsSuperseded -eq $True) {
        Try {
          ForEach ($Superseding In @($Record.Update.GetRelatedUpdates('UpdatesThatSupersedeThisUpdate'))) {
            If (([System.Boolean]$Superseding.IsApproved -eq $True) -or ($EligibleIds.Contains([System.String]$Superseding.Id.UpdateId) -eq $True)) {
              $Skip = $True
            }
          }
        } Catch {
          $Skip = $True
          $Failures.Add(($Script:Message['Select-ApprovalCandidate.SupersedenceFailed'] -f (ConvertTo-DeclineItemText -Record:$Record), $PSItem.Exception.GetBaseException().Message))
        }
      }

      If ($Skip -eq $True) {
        $SupersededCount++
      } Else {
        $Candidates.Add($Record)
      }
    }

    [PSCustomObject]$Result = [PSCustomObject]@{
      Candidates = [PSCustomObject[]]@($Candidates | Sort-Object -Property:@{ Expression = { [System.Boolean]$PSItem.Update.IsWsusInfrastructureUpdate }; Descending = $True }, @{ Expression = 'CreationDate'; Descending = $False }, @{ Expression = 'Title'; Descending = $False })
      Needed     = [System.Int32]($Eligible.Count + $ExcludedCount)
      Excluded   = [System.Int32]$ExcludedCount
      Superseded = [System.Int32]$SupersededCount
      Failures   = [System.String[]]$Failures.ToArray()
    }
    $Catalog.Selection = $Result
  }

  $Result
  Write-Debug -Message:'[Select-ApprovalCandidate] Exiting'
}
