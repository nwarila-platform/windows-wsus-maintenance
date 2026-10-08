#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-ContentStaging.Budget'             = 'Time budget reached after staging {0} update(s); the rest are staged on the next run.'
  'Invoke-ContentStaging.DownloadAll'        = 'The server downloads the files of every synchronized update (DownloadUpdateBinariesAsNeeded is off), so content staging adds nothing. Configuration management owns this setting; it was not changed.'
  'Invoke-ContentStaging.DrySummary'         = 'pending: {0} needed update(s) would be staged in {1}; {2} needed, {3} already staged.'
  'Invoke-ContentStaging.ExpressOn'          = 'Express installation files are on (DownloadExpressPackages); they are larger and cost upstream bandwidth. Configuration management owns this setting; it was not changed.'
  'Invoke-ContentStaging.Failed'             = 'failed: {0}: {1}'
  'Invoke-ContentStaging.FailedNotice'       = '{0} content staging action(s) failed. First failure: {1}'
  'Invoke-ContentStaging.LicenceNotAccepted' = 'not staged, licence agreement not accepted: {0}'
  'Invoke-ContentStaging.NoGroup'            = 'Content staging did nothing: the computer group ''{0}'' does not exist. Configuration management creates it; it is never created by the run.'
  'Invoke-ContentStaging.NoGroupSummary'     = 'nothing staged: the staging group {0} does not exist'
  'Invoke-ContentStaging.NotEmpty'           = 'Content staging did nothing: the staging group ''{0}'' has {1} member(s), and an approval for it would offer updates to them. The staging group must stay empty.'
  'Invoke-ContentStaging.NotEmptySummary'    = 'nothing staged: the staging group {0} has members'
  'Invoke-ContentStaging.OnMicrosoftUpdate'  = 'Update files are left on Microsoft Update (HostBinariesOnMicrosoftUpdate), so nothing is downloaded to this server and content staging adds nothing. Configuration management owns this setting; it was not changed.'
  'Invoke-ContentStaging.RemoveFailed'       = 'staging approval not removed: {0}: {1}'
  'Invoke-ContentStaging.Removed'            = 'staging approval removed, files local and approved: {0}'
  'Invoke-ContentStaging.SettingsUnreadable' = 'The download settings could not be read: {0}'
  'Invoke-ContentStaging.Staged'             = 'staged in {0}: {1}'
  'Invoke-ContentStaging.Summary'            = 'Staged {0} update(s) in {1}; {2} needed, {3} already staged, {4} staging approval(s) removed, {5} failed.'
  'Invoke-ContentStaging.WouldRemove'        = 'pending: staging approval would be removed, files local and approved: {0}'
  'Invoke-ContentStaging.WouldStage'         = 'pending: would stage in {0}: {1}'
}

Function Invoke-ContentStaging {
  <#
    .SYNOPSIS
        Starts the content download of needed updates before their approval date.

    .DESCRIPTION
        Approves each needed candidate (Select-ApprovalCandidate) that is not approved for install for
        any group, and not already staged, for the empty staging group approval.staging.groupName. With
        deferred downloads WSUS downloads an update only once it is approved, so this starts the download
        at once while no client is offered the update. The group must exist (it is never created) and
        must have no members, including in its subgroups; otherwise nothing is staged. A licence
        agreement is accepted first when approval.acceptLicenseAgreements is set; otherwise such an
        update is not staged. Once an update is approved for a real group and its files are local, its
        staging approval is removed. The server's download settings are only reported: a Warning notice
        when express installation files are on, when every synchronized update is downloaded, or when
        files are left on Microsoft Update; configuration management owns them and they are never
        changed. A dry run changes nothing and lists what it would stage.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-ContentStaging -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-contentstaging',
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

  Write-Debug -Message:'[Invoke-ContentStaging] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Catalog = $Null
  [System.Object]$Private:Approval = $Null
  [System.Int32]$Private:BatchSize = 1
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.Object]$Private:Group = $Null
  [System.String]$Private:GroupId = [System.String]::Empty
  [System.String]$Private:GroupName = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.String]$Private:Key = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Record = $Null
  [PSCustomObject]$Private:Selection = $Null
  [System.Object]$Private:ServerSettings = $Null
  [System.Object]$Private:Settings = $Null
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.String]$Private:Text = [System.String]::Empty
  [System.Object]$Private:UpdateServer = $Null
  [PSCustomObject]$Private:Result = $Null

  $Catalog = Get-ApprovalCatalog -Context:$Context
  If (([System.String]::IsNullOrEmpty($Catalog.Error) -eq $False) -or ([System.String]::IsNullOrEmpty($Catalog.LanguageError) -eq $False)) {
    [PSCustomObject]$Result = New-ApprovalUnavailableResult -Catalog:$Catalog -Stage:$Context.StageName
  } Else {
    $UpdateServer = Get-WsusConnection -Context:$Context
    $Settings = $Context.Configuration.approval
    $GroupName = [System.String]$Settings.staging.groupName
    $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
    $Items = [System.Collections.Generic.List[System.String]]::new()
    $Failures = [System.Collections.Generic.List[System.String]]::new()
    $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
    ForEach ($Name In @('Needed', 'Candidates', 'Staged', 'AlreadyStaged', 'ApprovedElsewhere', 'Pending', 'StagingRemoved', 'LicencesAccepted', 'LicenceNotAccepted', 'Excluded', 'SupersededSkipped', 'Failed')) {
      $Counts[$Name] = [System.Int64]0
    }

    # Download settings, reported and never changed:
    #   https://learn.microsoft.com/previous-versions/windows/desktop/ms752728(v=vs.85)
    Try {
      $ServerSettings = $UpdateServer.GetConfiguration()
      If ([System.Boolean]$ServerSettings.DownloadExpressPackages -eq $True) {
        $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Invoke-ContentStaging.ExpressOn'] -Severity:'Warning' -Stage:$Context.StageName))
      }

      If ([System.Boolean]$ServerSettings.DownloadUpdateBinariesAsNeeded -eq $False) {
        $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Invoke-ContentStaging.DownloadAll'] -Severity:'Warning' -Stage:$Context.StageName))
      }

      If ([System.Boolean]$ServerSettings.HostBinariesOnMicrosoftUpdate -eq $True) {
        $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Invoke-ContentStaging.OnMicrosoftUpdate'] -Severity:'Warning' -Stage:$Context.StageName))
      }
    } Catch {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ContentStaging.SettingsUnreadable'] -f $PSItem.Exception.GetBaseException().Message) -Severity:'Warning' -Stage:$Context.StageName))
    }

    If ($Catalog.Groups.ContainsKey($GroupName) -eq $True) {
      $Group = $Catalog.Groups[$GroupName]
    }

    If ($Null -eq $Group) {
      $Status = 'Error'
      $Summary = $Script:Message['Invoke-ContentStaging.NoGroupSummary'] -f $GroupName
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ContentStaging.NoGroup'] -f $GroupName) -Severity:'Error' -Stage:$Context.StageName))
    } ElseIf (@($Group.GetComputerTargets($True)).Count -gt 0) {
      $Status = 'Error'
      $Summary = $Script:Message['Invoke-ContentStaging.NotEmptySummary'] -f $Group.Name
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ContentStaging.NotEmpty'] -f $Group.Name, @($Group.GetComputerTargets($True)).Count) -Severity:'Error' -Stage:$Context.StageName))
    } Else {
      $GroupId = [System.String]$Group.Id

      # A staging approval is removed once a real approval exists and the files are local:
      #   https://learn.microsoft.com/previous-versions/windows/desktop/ms746895(v=vs.85)
      ForEach ($Record In $Catalog.Records) {
        $Key = '{0}|{1}' -f $Record.Id, $Record.Revision
        If (($Catalog.Approvals.ContainsKey($Key) -eq $False) -or ((Test-UpdateApproval -Catalog:$Catalog -GroupId:$GroupId -Record:$Record) -eq $False)) {
          Continue
        }

        If (((Test-UpdateApproval -Catalog:$Catalog -GroupId:$GroupId -OtherThan -Record:$Record) -eq $True) -and ([System.String]$Record.Update.State -eq 'Ready')) {
          $Text = ConvertTo-DeclineItemText -Record:$Record
          If ($Context.DryRun -eq $True) {
            $Items.Add(($Script:Message['Invoke-ContentStaging.WouldRemove'] -f $Text))
            Continue
          }

          Try {
            ForEach ($Entry In @($Catalog.Approvals[$Key] | Where-Object -FilterScript:({ $PSItem.Action -eq 'Install' }))) {
              If (([System.String]::Equals($Entry.GroupId, $GroupId, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) -and ($Null -ne $Entry.Approval)) {
                $Entry.Approval.Delete()
                $Entry.Action = 'Removed'
              }
            }

            $Counts['StagingRemoved'] = $Counts['StagingRemoved'] + 1
            $Items.Add(($Script:Message['Invoke-ContentStaging.Removed'] -f $Text))
          } Catch {
            $Failures.Add(($Script:Message['Invoke-ContentStaging.RemoveFailed'] -f $Text, $PSItem.Exception.GetBaseException().Message))
          }
        }
      }

      $Selection = Select-ApprovalCandidate -Catalog:$Catalog -Context:$Context
      $Counts['Needed'] = [System.Int64]$Selection.Needed
      $Counts['Excluded'] = [System.Int64]$Selection.Excluded
      $Counts['SupersededSkipped'] = [System.Int64]$Selection.Superseded
      $Counts['Candidates'] = [System.Int64]$Selection.Candidates.Count
      ForEach ($Line In $Selection.Failures) {
        $Failures.Add($Line)
      }

      $Started = Get-MaintenanceTime
      For ($Position = 1; $Position -le $Selection.Candidates.Count; $Position++) {
        $Record = $Selection.Candidates[$Position - 1]
        If ((Test-UpdateApproval -Catalog:$Catalog -GroupId:$GroupId -OtherThan -Record:$Record) -eq $True) {
          $Counts['ApprovedElsewhere'] = $Counts['ApprovedElsewhere'] + 1
          Continue
        }

        If ((Test-UpdateApproval -Catalog:$Catalog -GroupId:$GroupId -Record:$Record) -eq $True) {
          $Counts['AlreadyStaged'] = $Counts['AlreadyStaged'] + 1
          Continue
        }

        $Text = ConvertTo-DeclineItemText -Record:$Record
        If ($Context.DryRun -eq $True) {
          $Counts['Pending'] = $Counts['Pending'] + 1
          $Items.Add(($Script:Message['Invoke-ContentStaging.WouldStage'] -f $Group.Name, $Text))
          Continue
        }

        If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
          $Stopped = $True
          Break
        }

        Try {
          If ([System.Boolean]$Record.Update.RequiresLicenseAgreementAcceptance -eq $True) {
            If ([System.Boolean]$Settings.acceptLicenseAgreements -eq $False) {
              $Counts['LicenceNotAccepted'] = $Counts['LicenceNotAccepted'] + 1
              $Items.Add(($Script:Message['Invoke-ContentStaging.LicenceNotAccepted'] -f $Text))
              Continue
            }

            $Record.Update.AcceptLicenseAgreement()
            $Counts['LicencesAccepted'] = $Counts['LicencesAccepted'] + 1
          }

          $Approval = $Record.Update.Approve('Install', $Group)
          Add-UpdateApproval -Approval:$Approval -Catalog:$Catalog -GroupId:$GroupId -Record:$Record
          $Counts['Staged'] = $Counts['Staged'] + 1
          $Items.Add(($Script:Message['Invoke-ContentStaging.Staged'] -f $Group.Name, $Text))
        } Catch {
          $Failures.Add(($Script:Message['Invoke-ContentStaging.Failed'] -f $Text, $PSItem.Exception.GetBaseException().Message))
          Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-ContentStaging.Failed'] -f $Text, $PSItem.Exception.GetBaseException().Message) -Stage:$Context.StageName
        }

        Write-MaintenanceProgress -BatchSize:$BatchSize -Item:$Record.Title -Log:$Context.Log -Position:$Position -Stage:$Context.StageName -StartedAt:$Started -Total:$Selection.Candidates.Count
      }

      $Counts['Failed'] = [System.Int64]$Failures.Count
      If ($Failures.Count -gt 0) {
        $Status = 'Error'
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ContentStaging.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Error' -Stage:$Context.StageName))
      } ElseIf (($Stopped -eq $True) -or ($Notices.Count -gt 0)) {
        $Status = 'Warning'
      }

      If ($Stopped -eq $True) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-ContentStaging.Budget'] -f $Counts['Staged']) -Severity:'Warning' -Stage:$Context.StageName))
      }

      If ($Context.DryRun -eq $True) {
        $Summary = $Script:Message['Invoke-ContentStaging.DrySummary'] -f $Counts['Pending'], $Group.Name, $Counts['Needed'], $Counts['AlreadyStaged']
      } Else {
        $Summary = $Script:Message['Invoke-ContentStaging.Summary'] -f $Counts['Staged'], $Group.Name, $Counts['Needed'], $Counts['AlreadyStaged'], $Counts['StagingRemoved'], $Counts['Failed']
      }
    }

    If (($Status -eq 'Success') -and ($Notices.Count -gt 0)) {
      $Status = 'Warning'
    }

    [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status
  }

  $Result
  Write-Debug -Message:'[Invoke-ContentStaging] Exiting'
}
