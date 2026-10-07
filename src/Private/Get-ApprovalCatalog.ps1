#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-ApprovalCatalog.Failed' = 'The needed updates, approvals or computer groups could not be read: {0}'
}

Function Get-ApprovalCatalog {
  <#
    .SYNOPSIS
        Gathers what the approval stages of a run need from WSUS, once.

    .DESCRIPTION
        Collects, once per run, the updates that are not declined (the decline catalog's list when the
        decline stages read every arrival, less the updates they declined; otherwise a retrieval of its
        own in the evaluation language), how many clients need each update, every approval of the
        approved updates, and the computer groups by name. Needed means the clients whose installation
        state is not installed, downloaded, installed pending a restart, or failed, as Microsoft defines
        it, summed per update by IUpdateServer.GetSummariesPerUpdate. Approvals come from
        IUpdateServer.GetUpdateApprovals and are indexed by update identifier and revision, so an
        approval of an earlier revision does not count for the current one. The catalog is kept with the
        server facts of the run; the stages add to it the approvals they make.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Get-ApprovalCatalog -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-approvalcatalog',
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

  Write-Debug -Message:'[Get-ApprovalCatalog] Entering'

  # Initialize Variable(s)
  [System.Collections.Hashtable]$Private:Approvals = $Null
  [PSCustomObject]$Private:Declines = $Null
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Collections.Hashtable]$Private:Groups = $Null
  [System.String]$Private:Key = [System.String]::Empty
  [System.String]$Private:Language = [System.String]::Empty
  [System.String]$Private:LanguageError = [System.String]::Empty
  [System.Collections.Hashtable]$Private:Needed = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Records = $Null
  [PSCustomObject]$Private:Retrieval = $Null
  [System.Object]$Private:Scope = $Null
  [System.Object]$Private:Source = $Null
  [System.Object]$Private:UpdateServer = $Null
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'ApprovalCatalog' -Default:$Null
  If ($Null -eq $Result) {
    $UpdateServer = Get-WsusConnection -Context:$Context
    $Declines = Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'DeclineCatalog' -Default:$Null
    $Records = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Needed = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Approvals = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Groups = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Language = [System.String]$Context.Configuration.declines.evaluationLanguage

    If (($Null -ne $Declines) -and ([System.String]::IsNullOrEmpty($Declines.Error) -eq $True) -and ([System.Int32]$Context.Configuration.declines.arrivalWindowDays -eq 0)) {
      $Source = $Declines.Records
      $LanguageError = [System.String]$Declines.LanguageError
    } Else {
      $Retrieval = Get-WsusUpdateRecord -AllArrivals -Context:$Context
      $Source = $Retrieval.Records
      $ErrorText = [System.String]$Retrieval.Error
      $LanguageError = [System.String]$Retrieval.LanguageError
    }

    ForEach ($Record In $Source) {
      If (($Null -eq $Declines) -or ($Declines.Claimed.Contains($Record.Id) -eq $False)) {
        $Records.Add($Record)
      }
    }

    If ([System.String]::IsNullOrEmpty($ErrorText) -eq $True) {
      Try {
        # Needed: not installed, downloaded, installed pending a restart, or failed:
        #   https://learn.microsoft.com/previous-versions/windows/desktop/ms744621(v=vs.85)
        $Scope = New-WsusAdministrationObject -TypeName:'UpdateScope'
        $Scope.ApprovedStates = 'NotApproved, LatestRevisionApproved, HasStaleUpdateApprovals'
        ForEach ($Summary In @($UpdateServer.GetSummariesPerUpdate($Scope, (New-WsusAdministrationObject -TypeName:'ComputerTargetScope')))) {
          $Needed[[System.String]$Summary.UpdateId] = [System.Int64]$Summary.NotInstalledCount + [System.Int64]$Summary.DownloadedCount + [System.Int64]$Summary.InstalledPendingRebootCount + [System.Int64]$Summary.FailedCount
        }

        $Scope = New-WsusAdministrationObject -TypeName:'UpdateScope'
        $Scope.ApprovedStates = 'LatestRevisionApproved, HasStaleUpdateApprovals'
        ForEach ($Approval In @($UpdateServer.GetUpdateApprovals($Scope))) {
          $Key = '{0}|{1}' -f [System.String]$Approval.UpdateId.UpdateId, [System.Int32]$Approval.UpdateId.RevisionNumber
          If ($Approvals.ContainsKey($Key) -eq $False) {
            $Approvals[$Key] = [System.Collections.Generic.List[PSCustomObject]]::new()
          }

          $Approvals[$Key].Add([PSCustomObject]@{ GroupId = [System.String]$Approval.ComputerTargetGroupId; Action = [System.String]$Approval.Action; Approval = $Approval })
        }

        ForEach ($Group In @($UpdateServer.GetComputerTargetGroups())) {
          $Groups[[System.String]$Group.Name] = $Group
        }
      } Catch {
        $ErrorText = $PSItem.Exception.GetBaseException().Message
        Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Get-ApprovalCatalog.Failed'] -f $ErrorText) -Stage:$Context.StageName
      }
    }

    [PSCustomObject]$Result = [PSCustomObject]@{
      Records       = $Records
      Needed        = $Needed
      Approvals     = $Approvals
      Groups        = $Groups
      Error         = [System.String]$ErrorText
      LanguageError = [System.String]$LanguageError
      Language      = [System.String]$Language
      ErrorReported = $False
      Selection     = $Null
    }
    $Context.Server | Add-Member -Force -MemberType:'NoteProperty' -Name:'ApprovalCatalog' -Value:$Result
  }

  $Result
  Write-Debug -Message:'[Get-ApprovalCatalog] Exiting'
}
