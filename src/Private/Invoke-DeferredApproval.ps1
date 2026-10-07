#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-DeferredApproval.Approved'            = 'approved for {0} after {1} day(s), {2}, content {3}: {4}'
  'Invoke-DeferredApproval.Budget'              = 'Time budget reached after {0} approval(s); the rest are approved on the next run.'
  'Invoke-DeferredApproval.DeadlineAt'          = 'deadline {0} UTC'
  'Invoke-DeferredApproval.DrySummary'          = 'pending: {0} approval(s) would be made across {1} group(s); {2} needed update(s), {3} waiting for their delay.'
  'Invoke-DeferredApproval.Failed'              = 'failed: {0}: {1}: {2}'
  'Invoke-DeferredApproval.FailedNotice'        = '{0} approval(s) failed. First failure: {1}'
  'Invoke-DeferredApproval.LateEvent'           = '{0} update(s) were approved before their files were local; clients wait for the files: {1}'
  'Invoke-DeferredApproval.LateItem'            = '{0}: {1}'
  'Invoke-DeferredApproval.LateNotice'          = '{0} approval(s) were made before the update files were local; clients wait for the files: {1}'
  'Invoke-DeferredApproval.LicenceNotAccepted'  = 'not approved for {0}, licence agreement not accepted: {1}'
  'Invoke-DeferredApproval.Local'               = 'local'
  'Invoke-DeferredApproval.NoDeadline'          = 'no deadline'
  'Invoke-DeferredApproval.NoDeadlineUserInput' = 'no deadline (the update can request user input)'
  'Invoke-DeferredApproval.NoGroup'             = 'Updates were not approved for the computer group ''{0}'': it does not exist. Configuration management creates it; it is never created by the run.'
  'Invoke-DeferredApproval.NotLocal'            = 'not yet local'
  'Invoke-DeferredApproval.Summary'             = 'Approved {0} update approval(s) across {1} group(s); {2} needed update(s), {3} waiting for their delay, {4} approved before their files were local, {5} failed.'
  'Invoke-DeferredApproval.WouldApprove'        = 'pending: would approve for {0} after {1} day(s): {2}'
}

Function Invoke-DeferredApproval {
  <#
    .SYNOPSIS
        Approves needed updates for each configured group once its delay has passed.

    .DESCRIPTION
        For each needed candidate (Select-ApprovalCandidate; WSUS infrastructure updates first) and each
        group in approval.groups, approves the update for install (IUpdate.Approve) once delayDays have
        passed since its revision CreationDate, unless that revision is already approved for the group.
        A group that does not exist is reported and never created. The install deadline is deadlineDays
        after the approval, in UTC; an update that can request user input is approved without one, as
        WSUS requires, and so is a group without deadlineDays. A licence agreement is accepted first when
        approval.acceptLicenseAgreements is set; otherwise the update is left unapproved. When the files
        of an update are not yet local on its approval date, it is approved on schedule and a Warning
        notice and a late-content event name each such approval. Every approval is listed with its group,
        delay, deadline and content state. A dry run changes nothing and lists the approvals it would
        make.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-DeferredApproval -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-deferredapproval',
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

  Write-Debug -Message:'[Invoke-DeferredApproval] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Approval = $Null
  [System.Int32]$Private:BatchSize = 1
  [PSCustomObject]$Private:Catalog = $Null
  [System.String]$Private:ContentText = [System.String]::Empty
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.DateTime]$Private:Deadline = [System.DateTime]::MinValue
  [System.String]$Private:DeadlineText = [System.String]::Empty
  [PSCustomObject]$Private:Events = $Null
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.String]$Private:GroupId = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Collections.Generic.List[System.String]]$Private:Late = $Null
  [System.Boolean]$Private:Local = $False
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.DateTime]$Private:Now = [System.DateTime]::MinValue
  [PSCustomObject]$Private:Record = $Null
  [PSCustomObject]$Private:Selection = $Null
  [System.Object]$Private:Settings = $Null
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Targets = $Null
  [System.String]$Private:Text = [System.String]::Empty
  [System.Boolean]$Private:UserInput = $False
  [PSCustomObject]$Private:Result = $Null

  $Catalog = Get-ApprovalCatalog -Context:$Context
  If (([System.String]::IsNullOrEmpty($Catalog.Error) -eq $False) -or ([System.String]::IsNullOrEmpty($Catalog.LanguageError) -eq $False)) {
    [PSCustomObject]$Result = New-ApprovalUnavailableResult -Catalog:$Catalog -Stage:$Context.StageName
  } Else {
    $Settings = $Context.Configuration.approval
    $Now = $Context.RunStart.ToUniversalTime()
    $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
    $Items = [System.Collections.Generic.List[System.String]]::new()
    $Failures = [System.Collections.Generic.List[System.String]]::new()
    $Late = [System.Collections.Generic.List[System.String]]::new()
    $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Targets = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
    ForEach ($Name In @('Needed', 'Candidates', 'Approved', 'AlreadyApproved', 'Waiting', 'Pending', 'LateContent', 'LicencesAccepted', 'LicenceNotAccepted', 'Excluded', 'SupersededSkipped', 'MissingGroups', 'Failed')) {
      $Counts[$Name] = [System.Int64]0
    }

    ForEach ($Entry In @($Settings.groups)) {
      If ($Null -eq $Entry) {
        Continue
      }

      If ($Catalog.Groups.ContainsKey([System.String]$Entry.name) -eq $True) {
        $Targets.Add([PSCustomObject]@{
            Group        = $Catalog.Groups[[System.String]$Entry.name]
            DelayDays    = [System.Int32]$Entry.delayDays
            DeadlineDays = Get-MaintenancePropertyValue -InputObject:$Entry -Name:'deadlineDays' -Default:$Null
          })
      } Else {
        $Counts['MissingGroups'] = $Counts['MissingGroups'] + 1
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-DeferredApproval.NoGroup'] -f $Entry.name) -Severity:'Error' -Stage:$Context.StageName))
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

    # Approval, deadlines in UTC, licence agreements first:
    #   https://learn.microsoft.com/previous-versions/windows/desktop/ms747129(v=vs.85)
    # No deadline for an update that requires user input:
    #   https://learn.microsoft.com/windows-server/administration/windows-server-update-services/manage/updates-operations
    $Started = Get-MaintenanceTime
    For ($Position = 1; ($Position -le $Selection.Candidates.Count) -and ($Stopped -eq $False); $Position++) {
      $Record = $Selection.Candidates[$Position - 1]
      $Text = ConvertTo-DeclineItemText -Record:$Record
      ForEach ($Target In $Targets) {
        $GroupId = [System.String]$Target.Group.Id
        If ((Test-UpdateApproval -Catalog:$Catalog -GroupId:$GroupId -Record:$Record) -eq $True) {
          $Counts['AlreadyApproved'] = $Counts['AlreadyApproved'] + 1
          Continue
        }

        If ($Record.CreationDate -gt $Now.AddDays(-$Target.DelayDays)) {
          $Counts['Waiting'] = $Counts['Waiting'] + 1
          Continue
        }

        If ($Context.DryRun -eq $True) {
          $Counts['Pending'] = $Counts['Pending'] + 1
          Add-UpdateApproval -Catalog:$Catalog -GroupId:$GroupId -Record:$Record
          $Items.Add(($Script:Message['Invoke-DeferredApproval.WouldApprove'] -f $Target.Group.Name, $Target.DelayDays, $Text))
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
              $Items.Add(($Script:Message['Invoke-DeferredApproval.LicenceNotAccepted'] -f $Target.Group.Name, $Text))
              Continue
            }

            $Record.Update.AcceptLicenseAgreement()
            $Counts['LicencesAccepted'] = $Counts['LicencesAccepted'] + 1
          }

          $Local = [System.String]$Record.Update.State -eq 'Ready'
          $UserInput = [System.Boolean](Get-MaintenancePropertyValue -InputObject:$Record.Update.InstallationBehavior -Name:'CanRequestUserInput' -Default:$False)
          If (($Null -ne $Target.DeadlineDays) -and ($UserInput -eq $False)) {
            $Deadline = (Get-MaintenanceTime).ToUniversalTime().AddDays([System.Int32]$Target.DeadlineDays)
            $Approval = $Record.Update.Approve('Install', $Target.Group, $Deadline)
            $DeadlineText = $Script:Message['Invoke-DeferredApproval.DeadlineAt'] -f $Deadline.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
          } Else {
            $Approval = $Record.Update.Approve('Install', $Target.Group)
            $DeadlineText = $Script:Message['Invoke-DeferredApproval.NoDeadline']
            If (($Null -ne $Target.DeadlineDays) -and ($UserInput -eq $True)) {
              $DeadlineText = $Script:Message['Invoke-DeferredApproval.NoDeadlineUserInput']
            }
          }

          Add-UpdateApproval -Approval:$Approval -Catalog:$Catalog -GroupId:$GroupId -Record:$Record
          $Counts['Approved'] = $Counts['Approved'] + 1
          If ($Local -eq $True) {
            $ContentText = $Script:Message['Invoke-DeferredApproval.Local']
          } Else {
            $ContentText = $Script:Message['Invoke-DeferredApproval.NotLocal']
            $Late.Add(($Script:Message['Invoke-DeferredApproval.LateItem'] -f $Target.Group.Name, $Text))
          }

          $Items.Add(($Script:Message['Invoke-DeferredApproval.Approved'] -f $Target.Group.Name, $Target.DelayDays, $DeadlineText, $ContentText, $Text))
        } Catch {
          $Failures.Add(($Script:Message['Invoke-DeferredApproval.Failed'] -f $Target.Group.Name, $Text, $PSItem.Exception.GetBaseException().Message))
          Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-DeferredApproval.Failed'] -f $Target.Group.Name, $Text, $PSItem.Exception.GetBaseException().Message) -Stage:$Context.StageName
        }
      }

      Write-MaintenanceProgress -BatchSize:$BatchSize -Item:$Record.Title -Log:$Context.Log -Position:$Position -Stage:$Context.StageName -StartedAt:$Started -Total:$Selection.Candidates.Count
    }

    $Counts['LateContent'] = [System.Int64]$Late.Count
    If ($Late.Count -gt 0) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-DeferredApproval.LateNotice'] -f $Late.Count, ($Late -join '; ')) -Severity:'Warning' -Stage:$Context.StageName))
      $Events = Get-MaintenancePropertyValue -InputObject:$Context -Name:'Events' -Default:$Null
      If ($Null -ne $Events) {
        Write-MaintenanceEvent -Channel:$Events -Kind:'lateContent' -Message:($Script:Message['Invoke-DeferredApproval.LateEvent'] -f $Late.Count, ($Late -join [System.Environment]::NewLine))
      }
    }

    $Counts['Failed'] = [System.Int64]$Failures.Count
    If (($Failures.Count -gt 0) -or ($Counts['MissingGroups'] -gt 0)) {
      $Status = 'Error'
      If ($Failures.Count -gt 0) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-DeferredApproval.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Error' -Stage:$Context.StageName))
      }
    } ElseIf (($Stopped -eq $True) -or ($Late.Count -gt 0)) {
      $Status = 'Warning'
    }

    If ($Stopped -eq $True) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-DeferredApproval.Budget'] -f $Counts['Approved']) -Severity:'Warning' -Stage:$Context.StageName))
    }

    If ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Invoke-DeferredApproval.DrySummary'] -f $Counts['Pending'], $Targets.Count, $Counts['Needed'], $Counts['Waiting']
    } Else {
      $Summary = $Script:Message['Invoke-DeferredApproval.Summary'] -f $Counts['Approved'], $Targets.Count, $Counts['Needed'], $Counts['Waiting'], $Counts['LateContent'], $Counts['Failed']
    }

    [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status
  }

  $Result
  Write-Debug -Message:'[Invoke-DeferredApproval] Exiting'
}
