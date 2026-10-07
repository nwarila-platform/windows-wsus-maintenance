#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Approval stages' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # The stage context's run start (2026-11-02 01:00 local time) in UTC: the reference for delays.
    $script:Now = [System.DateTime]::new(2026, 11, 2, 1, 0, 0).ToUniversalTime()
    $script:OldId = [System.Guid]::NewGuid()
    $script:Approval = '"approval": { "enabled": true, "groups": [ { "name": "Pilot", "delayDays": 7, "deadlineDays": 3 }, { "name": "Broad", "delayDays": 14 } ], "staging": { "enabled": true, "groupName": "Content Staging" }, "neverApprove": [ "KB5000999" ]'

    # Needed and unneeded updates on both sides of the group delays, with the special cases the
    #   stages handle: a WSUS infrastructure update, a licence, user input, an Upgrades update, an
    #   update on the never-approve list, an expired one and a superseded one.
    Function script:New-ApprovalFleet {
      @(
        New-FakeUpdate -Title 'Old cumulative' -Kb @('5000001') -Needed 10 -Created $script:Now.AddDays(-20) -Local $True -Id $script:OldId
        New-FakeUpdate -Title 'Mid cumulative' -Kb @('5000002') -Needed 3 -Created $script:Now.AddDays(-10)
        New-FakeUpdate -Title 'New cumulative' -Kb @('5000003') -Needed 2 -Created $script:Now.AddDays(-1)
        New-FakeUpdate -Title 'Server component' -Kb @('5000004') -Needed 1 -Created $script:Now.AddDays(-30) -Infrastructure $True -Local $True
        New-FakeUpdate -Title 'Licensed tool' -Kb @('5000005') -Needed 1 -Created $script:Now.AddDays(-40) -Licence $True -Local $True
        New-FakeUpdate -Title 'Interactive tool' -Kb @('5000006') -Needed 1 -Created $script:Now.AddDays(-40) -UserInput $True -Local $True
        New-FakeUpdate -Title 'Unneeded' -Kb @('5000007') -Needed 0 -Created $script:Now.AddDays(-40)
        New-FakeUpdate -Title 'Feature update' -Kb @('5000008') -Classification 'Upgrades' -Needed 4 -Created $script:Now.AddDays(-40)
        New-FakeUpdate -Title 'Never approved' -Kb @('5000999') -Needed 1 -Created $script:Now.AddDays(-40)
        New-FakeUpdate -Title 'Expired' -Kb @('5000010') -Needed 1 -Expired $True -Created $script:Now.AddDays(-40)
        New-FakeUpdate -Title 'Old superseded' -Kb @('5000011') -Needed 1 -Superseded $True -SupersededBy @($script:OldId) -Created $script:Now.AddDays(-60)
      )
    }

    Function script:New-ApprovalServer {
      Param ([System.Object[]]$Updates = (New-ApprovalFleet), [System.String[]]$Groups = @('Pilot', 'Broad', 'Content Staging'), [System.Collections.Hashtable]$Extra = @{})
      New-FakeUpdateServer -Updates $Updates -Groups $Groups @Extra
    }

    Function script:New-ApprovalContext {
      Param ($Server, [System.String]$Approval = $script:Approval, [System.Boolean]$DryRun = $False, [System.String]$Stage = 'DeferredApproval', [System.String]$More = '')
      $Context = New-FakeStageContext -UpdateServer $Server -Extra (', ' + $Approval + ' }' + $More) -DryRun $DryRun -Log $script:Log
      $Context.StageName = $Stage
      $Context | Add-Member -NotePropertyName Events -NotePropertyValue ([PSCustomObject]@{ Name = 'channel' }) -Force
      $Context
    }

    Function script:Get-Approved {
      Param ($Server, [System.String]$Group)
      @($Server.State.Approvals | Where-Object -FilterScript { $PSItem.GroupName -eq $Group } | ForEach-Object -Process { $PSItem.Title })
    }

    $script:Deadline = [System.DateTime]::new(2026, 11, 2, 1, 0, 0).ToUniversalTime().AddDays(3).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    Mock -CommandName New-WsusAdministrationObject -MockWith { New-FakeWsusObject -TypeName $TypeName }
    Mock -CommandName Write-MaintenanceEvent -MockWith { }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  Context 'Invoke-DeferredApproval' {
    It 'approves each needed update for each group once its delay has passed, WSUS infrastructure updates first' {
      $Server = New-ApprovalServer

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Server.State.ApprovalLog[0] | Should -Be ('Pilot:Server component:{0}' -f $script:Deadline)
      Get-Approved -Server $Server -Group 'Pilot' | Should -Be @('Server component', 'Interactive tool', 'Licensed tool', 'Old cumulative', 'Mid cumulative')
      Get-Approved -Server $Server -Group 'Broad' | Should -Be @('Server component', 'Interactive tool', 'Licensed tool', 'Old cumulative')
      $Result.Counts['Approved'] | Should -Be 9
      $Result.Counts['Waiting'] | Should -Be 3
      $Result.Counts['Candidates'] | Should -Be 6
      $Result.Counts['Excluded'] | Should -Be 2
      $Result.Counts['SupersededSkipped'] | Should -Be 1
      $Result.Counts['Needed'] | Should -Be 9
      $Result.Message | Should -Be 'Approved 9 update approval(s) across 2 group(s); 9 needed update(s), 3 waiting for their delay, 1 approved before their files were local, 0 failed.'
    }

    It 'lists each approval with its group, delay, deadline and content state' {
      $Server = New-ApprovalServer

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Result.Items | Should -Contain ('approved for Pilot after 7 day(s), deadline {0} UTC, content local: Old cumulative (KB5000001, created {1})' -f $script:Deadline, $script:Now.AddDays(-20).ToString('yyyy-MM-dd'))
      $Result.Items | Should -Contain ('approved for Broad after 14 day(s), no deadline, content local: Old cumulative (KB5000001, created {0})' -f $script:Now.AddDays(-20).ToString('yyyy-MM-dd'))
      $Result.Items | Should -Contain ('approved for Pilot after 7 day(s), no deadline (the update can request user input), content local: Interactive tool (KB5000006, created {0})' -f $script:Now.AddDays(-40).ToString('yyyy-MM-dd'))
      $Server.State.ApprovalLog | Should -Contain 'Pilot:Interactive tool:none'
    }

    It 'accepts a licence agreement before approving, or leaves the update unapproved when that is not allowed' {
      $Accepting = New-ApprovalServer
      $Refusing = New-ApprovalServer

      $Null = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Accepting)
      $Refused = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Refusing -Approval ($script:Approval + ', "acceptLicenseAgreements": false'))

      $Accepting.State.Licences | Should -Be @('Licensed tool')
      Get-Approved -Server $Accepting -Group 'Pilot' | Should -Contain 'Licensed tool'
      Get-Approved -Server $Refusing -Group 'Pilot' | Should -Not -Contain 'Licensed tool'
      $Refused.Counts['LicenceNotAccepted'] | Should -Be 2
      $Refused.Items | Should -Contain ('not approved for Pilot, licence agreement not accepted: Licensed tool (KB5000005, created {0})' -f $script:Now.AddDays(-40).ToString('yyyy-MM-dd'))
    }

    It 'approves late content on schedule and names each such approval in a Warning notice and an event' {
      $Server = New-ApprovalServer

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Result.Status | Should -Be 'Warning'
      $Result.Counts['LateContent'] | Should -Be 1
      $Result.Notices | Should -HaveCount 1
      $Result.Notices[0].Severity | Should -Be 'Warning'
      $Result.Notices[0].Message | Should -BeLike '1 approval(s) were made before the update files were local; clients wait for the files: Pilot: Mid cumulative (KB5000002, created *)'
      Should -Invoke -CommandName Write-MaintenanceEvent -Times 1 -Exactly -ParameterFilter { ($Kind -eq 'lateContent') -and ($Message -like '1 update(s) were approved before their files were local*Pilot: Mid cumulative*') }
    }

    It 'approves nothing new on a repeat run' {
      $Server = New-ApprovalServer

      $Null = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)
      $Again = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Again.Counts['Approved'] | Should -Be 0
      $Again.Counts['AlreadyApproved'] | Should -Be 9
      $Server.State.Approvals | Should -HaveCount 9
    }

    It 'approves a re-released revision again, because its delay restarts' {
      $Update = New-FakeUpdate -Title 'Revised' -Kb @('5000020') -Needed 1 -Created $script:Now.AddDays(-30) -Local $True -Revision 2
      $Server = New-ApprovalServer -Updates @($Update)
      $Server.State.Approvals.Add([PSCustomObject]@{ UpdateId = [PSCustomObject]@{ UpdateId = $Update.Id.UpdateId; RevisionNumber = 1 }; ComputerTargetGroupId = [System.Guid]$Server.State.Groups[0].Id; Action = 'Install'; GroupName = 'Pilot'; Title = 'Revised' })

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Result.Counts['AlreadyApproved'] | Should -Be 0
      $Result.Counts['Approved'] | Should -Be 2
    }

    It 'changes nothing in a dry run and lists the approvals it would make' {
      $Server = New-ApprovalServer

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server -DryRun $True)

      $Server.State.Approvals | Should -HaveCount 0
      $Server.State.Licences | Should -HaveCount 0
      $Result.Counts['Pending'] | Should -Be 9
      $Result.Items[0] | Should -BeLike 'pending: would approve for Pilot after 7 day(s): Server component (KB5000004, created *)'
      $Result.Message | Should -Be 'pending: 9 approval(s) would be made across 2 group(s); 9 needed update(s), 3 waiting for their delay.'
      Should -Invoke -CommandName Write-MaintenanceEvent -Times 0 -Exactly
    }

    It 'reports a group that does not exist, never creates it, and still approves for the others' {
      $Server = New-ApprovalServer -Groups @('Pilot', 'Content Staging')

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Result.Status | Should -Be 'Error'
      $Result.Counts['MissingGroups'] | Should -Be 1
      $Result.Notices[0].Message | Should -Be "Updates were not approved for the computer group 'Broad': it does not exist. Configuration management creates it; it is never created by the run."
      $Server.State.Groups | Should -HaveCount 2
      Get-Approved -Server $Server -Group 'Pilot' | Should -HaveCount 5
    }

    It 'records a failed approval and carries on' {
      $Server = New-ApprovalServer -Extra @{ FailingUpdates = @('Old cumulative') }

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Result.Status | Should -Be 'Error'
      $Result.Counts['Failed'] | Should -Be 2
      $Result.Items | Should -Contain ('failed: Pilot: Old cumulative (KB5000001, created {0}): The update Old cumulative could not be approved.' -f $script:Now.AddDays(-20).ToString('yyyy-MM-dd'))
      Get-Approved -Server $Server -Group 'Pilot' | Should -Contain 'Mid cumulative'
    }

    It 'stops between approvals when the time budget runs out' {
      $Server = New-ApprovalServer
      $script:BudgetChecks = 0
      Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 2 }

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Server.State.Approvals | Should -HaveCount 2
      $Result.Status | Should -Be 'Warning'
      $Result.Notices[-1].Message | Should -Be 'Time budget reached after 2 approval(s); the rest are approved on the next run.'
    }

    It 'approves nothing, with one Error notice for both stages, when <Case>' -ForEach @(
      @{ Case = 'the needed updates cannot be read'; Extra = @{ SummariesFailure = 'The operation has timed out.' }; Reason = '*could not be read (The operation has timed out.)*' }
      @{ Case = 'the evaluation language cannot be set'; Extra = @{ CultureFails = $True }; Reason = '*the evaluation language en could not be set*Upgrades*' }
    ) {
      $Server = New-ApprovalServer -Extra $Extra
      $Context = New-ApprovalContext -Server $Server

      $Approval = Invoke-DeferredApproval -Context $Context
      $Context.StageName = 'ContentStaging'
      $Staging = Invoke-ContentStaging -Context $Context

      $Server.State.Approvals | Should -HaveCount 0
      $Approval.Status | Should -Be 'Error'
      $Staging.Status | Should -Be 'Error'
      $Approval.Message | Should -BeLike ('nothing approved or staged: {0}' -f $Reason)
      $Approval.Notices | Should -HaveCount 1
      $Approval.Notices[0].Message | Should -BeLike 'No update was approved or staged in this run: *. The other stages still run.'
      $Staging.Notices | Should -HaveCount 0
    }
  }

  Context 'Invoke-ContentStaging' {
    It 'stages every needed update that is not approved anywhere in the empty staging group' {
      $Server = New-ApprovalServer

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')

      $Result.Status | Should -Be 'Success'
      Get-Approved -Server $Server -Group 'Content Staging' | Should -Be @('Server component', 'Interactive tool', 'Licensed tool', 'Old cumulative', 'Mid cumulative', 'New cumulative')
      $Server.State.ApprovalLog[0] | Should -Be 'Content Staging:Server component:none'
      $Result.Counts['Staged'] | Should -Be 6
      $Result.Items[0] | Should -BeLike 'staged in Content Staging: Server component (KB5000004, created *)'
      $Result.Message | Should -Be 'Staged 6 update(s) in Content Staging; 9 needed, 0 already staged, 0 staging approval(s) removed, 0 failed.'
    }

    It 'leaves out updates already approved for a group, and stages nothing new on a repeat run' {
      $Server = New-ApprovalServer
      $Pilot = $Server.State.Groups[0]
      $Null = ($Server.State.Updates | Where-Object -FilterScript { $PSItem.Title -eq 'New cumulative' }).Approve('Install', $Pilot)

      $First = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')
      $Again = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')

      $First.Counts['ApprovedElsewhere'] | Should -Be 1
      $First.Counts['Staged'] | Should -Be 5
      $Again.Counts['Staged'] | Should -Be 0
      $Again.Counts['AlreadyStaged'] | Should -Be 5
    }

    It 'removes a staging approval once the update is approved for a group and its files are local' {
      $Server = New-ApprovalServer
      $Null = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')
      $Null = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')

      $Server.State.RemovedApprovals | Should -Be @('Content Staging:Old cumulative', 'Content Staging:Server component', 'Content Staging:Licensed tool', 'Content Staging:Interactive tool')
      Get-Approved -Server $Server -Group 'Content Staging' | Should -Be @('Mid cumulative', 'New cumulative')
      $Result.Counts['StagingRemoved'] | Should -Be 4
      $Result.Items | Should -Contain ('staging approval removed, files local and approved: Old cumulative (KB5000001, created {0})' -f $script:Now.AddDays(-20).ToString('yyyy-MM-dd'))
    }

    It 'stages nothing and ends in error when the staging group <Case>' -ForEach @(
      @{ Case = 'does not exist'; Groups = @('Pilot', 'Broad'); Members = $False; Message = "Content staging did nothing: the computer group 'Content Staging' does not exist.*" }
      @{ Case = 'has members'; Groups = @('Pilot', 'Broad', 'Content Staging'); Members = $True; Message = "Content staging did nothing: the staging group 'Content Staging' has 1 member(s)*" }
    ) {
      $Server = New-ApprovalServer -Groups $Groups
      If ($Members) {
        $Server.State.Groups[2].Members.Add((New-FakeComputer -Name 'pc.example' -LastSync ([System.DateTime]::UtcNow)))
      }

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')

      $Server.State.Approvals | Should -HaveCount 0
      $Result.Status | Should -Be 'Error'
      @($Result.Notices | Where-Object -FilterScript { $PSItem.Severity -eq 'Error' })[0].Message | Should -BeLike $Message
    }

    It 'reports download settings that differ from the expected ones and never changes them' {
      $Server = New-ApprovalServer -Extra @{ ExpressFiles = $True; DownloadAll = $True; FilesOnMicrosoftUpdate = $True }

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')

      $Result.Status | Should -Be 'Warning'
      @($Result.Notices | Where-Object -FilterScript { $PSItem.Severity -eq 'Warning' }) | Should -HaveCount 3
      $Result.Notices[0].Message | Should -BeLike 'Express installation files are on*it was not changed.'
      $Result.Notices[1].Message | Should -BeLike '*DownloadUpdateBinariesAsNeeded is off*it was not changed.'
      $Result.Notices[2].Message | Should -BeLike '*HostBinariesOnMicrosoftUpdate*it was not changed.'
      $Server.Configuration.DownloadExpressPackages | Should -BeTrue
      $Server.Configuration.DownloadUpdateBinariesAsNeeded | Should -BeFalse
    }

    It 'reports download settings it cannot read' {
      $Server = New-ApprovalServer -Extra @{ ConfigurationFails = $True }

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')

      $Result.Notices[0].Message | Should -Be 'The download settings could not be read: The configuration could not be read.'
    }

    It 'leaves an update with a licence agreement unstaged when accepting it is not allowed' {
      $Server = New-ApprovalServer

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging' -Approval ($script:Approval + ', "acceptLicenseAgreements": false'))

      Get-Approved -Server $Server -Group 'Content Staging' | Should -Not -Contain 'Licensed tool'
      $Result.Counts['LicenceNotAccepted'] | Should -Be 1
      $Result.Items | Should -Contain ('not staged, licence agreement not accepted: Licensed tool (KB5000005, created {0})' -f $script:Now.AddDays(-40).ToString('yyyy-MM-dd'))
    }

    It 'changes nothing in a dry run and lists what it would stage and remove' {
      $Server = New-ApprovalServer
      $Null = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging')
      $Null = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)
      $Server.State.Updates.Add((New-FakeUpdate -Title 'Brand new' -Kb @('5000030') -Needed 1 -Created $script:Now))
      $Server.State.Updates[-1].Server = $Server.State
      $Before = $Server.State.Approvals.Count

      $Result = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Server -Stage 'ContentStaging' -DryRun $True)

      $Server.State.Approvals.Count | Should -Be $Before
      $Server.State.RemovedApprovals | Should -HaveCount 0
      $Result.Items | Should -Contain ('pending: would stage in Content Staging: Brand new (KB5000030, created {0})' -f $script:Now.ToString('yyyy-MM-dd'))
      @($Result.Items | Where-Object -FilterScript { $PSItem -like 'pending: staging approval would be removed*' }) | Should -HaveCount 4
      $Result.Message | Should -Be 'pending: 1 needed update(s) would be staged in Content Staging; 10 needed, 1 already staged.'
    }

    It 'records a failed staging and carries on, and stops at the time budget' {
      $Failing = New-ApprovalServer -Extra @{ FailingUpdates = @('Server component') }
      $Stopping = New-ApprovalServer

      $Failed = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Failing -Stage 'ContentStaging')
      Mock -CommandName Test-MaintenanceBudget -MockWith { $True }
      $Stopped = Invoke-ContentStaging -Context (New-ApprovalContext -Server $Stopping -Stage 'ContentStaging')

      $Failed.Status | Should -Be 'Error'
      $Failed.Counts['Staged'] | Should -Be 5
      $Failed.Notices[0].Message | Should -BeLike '1 content staging action(s) failed. First failure: failed: Server component*'
      $Stopped.Status | Should -Be 'Warning'
      $Stopped.Notices[0].Message | Should -Be 'Time budget reached after staging 0 update(s); the rest are staged on the next run.'
    }
  }

  Context 'one run' {
    It 'reuses the decline stages'' update list, leaving out what they declined' {
      $Server = New-ApprovalServer -Updates @((New-ApprovalFleet) + @(New-FakeUpdate -Title 'Very old superseded' -Needed 1 -Superseded $True -Created $script:Now.AddDays(-200)))
      $Context = New-ApprovalContext -Server $Server

      $Null = Invoke-SupersededDecline -Context $Context
      $Result = Invoke-DeferredApproval -Context $Context

      $Server.State.UpdateScopes | Should -HaveCount 1
      $Server.State.DeclinedUpdates | Should -Be @('Very old superseded')
      $Result.Counts['Needed'] | Should -Be 9
      Get-Approved -Server $Server -Group 'Pilot' | Should -Not -Contain 'Very old superseded'
    }

    It 'retrieves its own list across every arrival when the declines use an arrival window' {
      $Server = New-ApprovalServer
      $Context = New-ApprovalContext -Server $Server -More ', "declines": { "arrivalWindowDays": 1 }'

      $Null = Invoke-ExpiredDecline -Context $Context
      $Result = Invoke-DeferredApproval -Context $Context

      $Server.State.UpdateScopes | Should -HaveCount 2
      $Server.State.UpdateScopes[1].FromArrivalDate | Should -Be ([System.DateTime]::MinValue)
      $Result.Counts['Approved'] | Should -Be 9
    }

    It 'skips a superseded update whose superseding update is approved, and records supersedence it cannot check' {
      $Superseding = New-FakeUpdate -Title 'Superseding' -Needed 0 -Approved $True
      $Superseded = New-FakeUpdate -Title 'Superseded' -Needed 1 -Superseded $True -SupersededBy @($Superseding.Id.UpdateId) -Created $script:Now.AddDays(-30)
      $Broken = New-FakeUpdate -Title 'Broken' -Needed 1 -Superseded $True -Created $script:Now.AddDays(-30)
      $Broken | Add-Member -Force -MemberType ScriptMethod -Name GetRelatedUpdates -Value { Param ($Relationship) Throw 'Relationship lookup failed.' }
      $Server = New-ApprovalServer -Updates @($Superseding, $Superseded, $Broken)

      $Result = Invoke-DeferredApproval -Context (New-ApprovalContext -Server $Server)

      $Server.State.Approvals | Should -HaveCount 0
      $Result.Counts['SupersededSkipped'] | Should -Be 2
      $Result.Status | Should -Be 'Error'
      $Result.Items | Should -Contain ('supersedence not checked, left unapproved: Broken (no Knowledge Base article, created {0}): Relationship lookup failed.' -f $script:Now.AddDays(-30).ToString('yyyy-MM-dd'))
    }
  }
}
