#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-UpdateApproval {
  <#
    .SYNOPSIS
        Tells whether the current revision of an update is approved for install for a group.

    .DESCRIPTION
        Looks in the approval catalog for an Install approval of the update's current revision, either
        for the given computer group or, with -OtherThan, for any group except the given one.

    .PARAMETER Catalog
        The approval catalog of the run (Get-ApprovalCatalog).

    .PARAMETER GroupId
        Identifier of the computer group.

    .PARAMETER OtherThan
        Look for an approval for any group except GroupId.

    .PARAMETER Record
        The update record.

    .EXAMPLE
        Test-UpdateApproval -Catalog $Catalog -GroupId $Group.Id -Record $Record

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-updateapproval',
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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $OtherThan,

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

  Write-Debug -Message:'[Test-UpdateApproval] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Key = [System.String]::Empty
  [System.Boolean]$Private:Same = $False
  [System.Boolean]$Private:Result = $False

  $Key = '{0}|{1}' -f $Record.Id, $Record.Revision
  If ($Catalog.Approvals.ContainsKey($Key) -eq $True) {
    ForEach ($Entry In $Catalog.Approvals[$Key]) {
      If ($Entry.Action -eq 'Install') {
        $Same = [System.String]::Equals($Entry.GroupId, $GroupId, [System.StringComparison]::OrdinalIgnoreCase)
        If ($Same -ne $OtherThan.IsPresent) {
          $Result = $True
        }
      }
    }
  }

  [System.Boolean]$Result = $Result

  $Result
  Write-Debug -Message:'[Test-UpdateApproval] Exiting'
}
