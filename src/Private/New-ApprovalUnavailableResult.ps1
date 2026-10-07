#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'New-ApprovalUnavailableResult.NoLanguage' = 'the evaluation language {0} could not be set ({1}), so the Upgrades classification and the excluded classifications cannot be recognised reliably'
  'New-ApprovalUnavailableResult.NoList'     = 'the needed updates, approvals or computer groups could not be read ({0})'
  'New-ApprovalUnavailableResult.Notice'     = 'No update was approved or staged in this run: {0}. The other stages still run.'
  'New-ApprovalUnavailableResult.Summary'    = 'nothing approved or staged: {0}'
}

Function New-ApprovalUnavailableResult {
  <#
    .SYNOPSIS
        Builds the result of an approval stage that could not act.

    .DESCRIPTION
        When the needed updates, approvals or computer groups could not be read, or the evaluation
        language could not be set (so the Upgrades classification and the excluded classifications
        cannot be recognised reliably), no approval stage acts. The first approval stage of the run
        raises one Error notice that says why; each approval stage ends in error and changes nothing.

    .PARAMETER Catalog
        The approval catalog of the run (Get-ApprovalCatalog).

    .PARAMETER Stage
        Name of the approval stage.

    .EXAMPLE
        New-ApprovalUnavailableResult -Catalog $Catalog -Stage 'DeferredApproval'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-approvalunavailableresult',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Stage
  )

  Write-Debug -Message:'[New-ApprovalUnavailableResult] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String]$Private:Reason = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  If ([System.String]::IsNullOrEmpty($Catalog.Error) -eq $False) {
    $Reason = $Script:Message['New-ApprovalUnavailableResult.NoList'] -f $Catalog.Error
  } Else {
    $Reason = $Script:Message['New-ApprovalUnavailableResult.NoLanguage'] -f $Catalog.Language, $Catalog.LanguageError
  }

  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  If ($Catalog.ErrorReported -eq $False) {
    $Catalog.ErrorReported = $True
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['New-ApprovalUnavailableResult.Notice'] -f $Reason) -Severity:'Error' -Stage:$Stage))
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Message:($Script:Message['New-ApprovalUnavailableResult.Summary'] -f $Reason) -Notice:$Notices.ToArray() -Status:'Error'

  $Result
  Write-Debug -Message:'[New-ApprovalUnavailableResult] Exiting'
}
