#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Add-UpdateApproval {
  <#
    .SYNOPSIS
        Records in the approval catalog an approval the run has made.

    .DESCRIPTION
        Adds an Install approval of the update's current revision for the computer group to the approval
        catalog, so that later checks of the run, and the next stage, see it without reading WSUS again.

    .PARAMETER Approval
        The approval WSUS returned, or null in a dry run.

    .PARAMETER Catalog
        The approval catalog of the run (Get-ApprovalCatalog).

    .PARAMETER GroupId
        Identifier of the computer group.

    .PARAMETER Record
        The update record.

    .EXAMPLE
        Add-UpdateApproval -Approval $Approval -Catalog $Catalog -GroupId $Group.Id -Record $Record

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#add-updateapproval',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Approval = $Null,

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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $GroupId,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Record
  )

  Write-Debug -Message:'[Add-UpdateApproval] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Key = [System.String]::Empty

  $Key = '{0}|{1}' -f $Record.Id, $Record.Revision
  If ($Catalog.Approvals.ContainsKey($Key) -eq $False) {
    $Catalog.Approvals[$Key] = [System.Collections.Generic.List[PSCustomObject]]::new()
  }

  $Catalog.Approvals[$Key].Add([PSCustomObject]@{ GroupId = $GroupId; Action = 'Install'; Approval = $Approval })

  Write-Debug -Message:'[Add-UpdateApproval] Exiting'
}
