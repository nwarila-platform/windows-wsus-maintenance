#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Decline policies' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # The stage context's run start (2026-11-02 01:00 local time) in UTC: the reference for ages.
    $script:Now = [System.DateTime]::new(2026, 11, 2, 1, 0, 0).ToUniversalTime()

    Function script:New-DeclineContext {
      Param ($Server, [System.String]$Declines = '', [System.Boolean]$DryRun = $False, [System.String]$Stage = 'Stage')
      $Extra = ''
      If ($Declines -ne '') {
        $Extra = ', "declines": { ' + $Declines + ' }'
      }
      $Context = New-FakeStageContext -UpdateServer $Server -Extra $Extra -DryRun $DryRun -Log $script:Log
      $Context.StageName = $Stage
      $Context
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    Mock -CommandName New-WsusAdministrationObject -MockWith { New-FakeWsusObject -TypeName $TypeName }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  Context 'Invoke-SupersededDecline' {
    BeforeAll {
      # Superseded updates on both sides of the 90-day threshold, in and out of a chain, approved
      #   or not, plus updates that are not superseded or already declined.
      Function script:New-SupersededFleet {
        @(
          New-FakeUpdate -Title 'Old leaf' -Kb @('5000001') -Superseded $True -Created $script:Now.AddDays(-200)
          New-FakeUpdate -Title 'Old middle' -Kb @('5000002') -Superseded $True -SupersedesOthers $True -Created $script:Now.AddDays(-150)
          New-FakeUpdate -Title 'Old approved' -Kb @('5000003') -Superseded $True -Approved $True -Created $script:Now.AddDays(-120)
          New-FakeUpdate -Title 'Young leaf' -Kb @('5000004') -Superseded $True -Created $script:Now.AddDays(-30)
          New-FakeUpdate -Title 'Current' -Kb @('5000005') -Created $script:Now.AddDays(-300)
          New-FakeUpdate -Title 'Already declined' -Kb @('5000006') -Superseded $True -Declined $True -Created $script:Now.AddDays(-300)
        )
      }
    }

    It 'declines the superseded updates older than the threshold, approved ones included, and counts the newer ones' {
      $Server = New-FakeUpdateServer -Updates (New-SupersededFleet)

      $Result = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server -Stage 'SupersededDecline')

      $Result.Status | Should -Be 'Success'
      $Server.State.DeclinedUpdates | Should -Be @('Old leaf', 'Old middle', 'Old approved')
      $Result.Counts['Evaluated'] | Should -Be 5
      $Result.Counts['Superseded'] | Should -Be 4
      $Result.Counts['WithinThreshold'] | Should -Be 1
      $Result.Counts['Declined'] | Should -Be 3
      $Result.Items[0] | Should -Be ('declined: Old leaf (KB5000001, created {0})' -f $script:Now.AddDays(-200).ToString('yyyy-MM-dd'))
      $Result.Message | Should -Be 'Declined 3 of 3 superseded update(s) older than 90 day(s); 1 newer kept; 0 failed. 5 update(s) evaluated.'
      $Server.State.UpdateScopes[0].ApprovedStates | Should -Be 'NotApproved, LatestRevisionApproved, HasStaleUpdateApprovals'
    }

    It 'keeps the intermediate updates of a chain with last-level-only, and approved updates when they are not eligible' {
      $Server = New-FakeUpdateServer -Updates (New-SupersededFleet)

      $Result = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server -Declines '"superseded": { "lastLevelOnly": true, "includeApproved": false }')

      $Server.State.DeclinedUpdates | Should -Be @('Old leaf')
      $Result.Counts['IntermediateKept'] | Should -Be 1
      $Result.Counts['ApprovedKept'] | Should -Be 1
    }

    It 'never declines an update on the never-decline list, by Knowledge Base number or identifier' {
      $Fleet = New-SupersededFleet
      $Server = New-FakeUpdateServer -Updates $Fleet
      $Guid = $Fleet[1].Id.UpdateId.ToString().ToUpperInvariant()

      $Result = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server -Declines ('"neverDecline": [ "KB5000001", "' + $Guid + '" ]'))

      $Server.State.DeclinedUpdates | Should -Be @('Old approved')
      $Result.Counts['Protected'] | Should -Be 2
    }

    It 'declines nothing on a repeat run' {
      $Server = New-FakeUpdateServer -Updates (New-SupersededFleet)

      $Null = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server)
      $Again = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server)

      $Again.Counts['Declined'] | Should -Be 0
      $Again.Counts['Superseded'] | Should -Be 1
      $Server.State.DeclinedUpdates | Should -HaveCount 3
    }

    It 'declines nothing in a dry run and reports the pending declines' {
      $Server = New-FakeUpdateServer -Updates (New-SupersededFleet)

      $Result = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server -DryRun $True)

      $Server.State.DeclinedUpdates | Should -HaveCount 0
      $Result.Counts['Pending'] | Should -Be 3
      $Result.Items[0] | Should -BeLike 'pending: Old leaf (KB5000001, created *)'
      $Result.Message | Should -Be 'pending: 3 superseded update(s) older than 90 day(s) would be declined; 1 newer kept. 5 update(s) evaluated.'
    }

    It 'records a failed decline, carries on and ends in error' {
      $Server = New-FakeUpdateServer -Updates (New-SupersededFleet) -FailingUpdates @('Old middle')

      $Result = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server)

      $Server.State.DeclinedUpdates | Should -Be @('Old leaf', 'Old approved')
      $Result.Status | Should -Be 'Error'
      $Result.Counts['Failed'] | Should -Be 1
      $Result.Items[-1] | Should -BeLike 'failed: Old middle (KB5000002, created *): *could not be declined*'
      $Result.Notices[0].Severity | Should -Be 'Error'
      $Result.Notices[0].Message | Should -BeLike '1 update(s) could not be declined. First failure: failed: Old middle*'
    }

    It 'stops between declines when the time budget runs out' {
      $Server = New-FakeUpdateServer -Updates (New-SupersededFleet)
      $script:BudgetChecks = 0
      Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 1 }

      $Result = Invoke-SupersededDecline -Context (New-DeclineContext -Server $Server)

      $Server.State.DeclinedUpdates | Should -Be @('Old leaf')
      $Result.Status | Should -Be 'Warning'
      $Result.Notices[0].Message | Should -Be 'Time budget reached after 1 of 3 decline(s); the rest are declined on the next run.'
    }
  }

  Context 'Invoke-AcceleratedDecline' {
    It 'declines superseded updates of the selected classifications only, after its own age' {
      $Server = New-FakeUpdateServer -Updates @(
        New-FakeUpdate -Title 'Definition 1' -Classification 'Definition Updates' -Superseded $True -Created $script:Now.AddDays(-3)
        New-FakeUpdate -Title 'Definition 2' -Classification 'definition updates' -Superseded $True -Created $script:Now.AddDays(-1)
        New-FakeUpdate -Title 'Security 1' -Classification 'Security Updates' -Superseded $True -Created $script:Now.AddDays(-30)
      )

      $Result = Invoke-AcceleratedDecline -Context (New-DeclineContext -Server $Server -Declines '"accelerated": { "enabled": true, "classifications": [ "Definition Updates" ], "ageDays": 2 }')

      $Server.State.DeclinedUpdates | Should -Be @('Definition 1')
      $Result.Counts['Superseded'] | Should -Be 2
      $Result.Counts['WithinThreshold'] | Should -Be 1
      $Result.Message | Should -Be 'Declined 1 of 1 superseded update(s) in Definition Updates older than 2 day(s); 1 newer kept; 0 failed. 3 update(s) evaluated.'
    }
  }

  Context 'Invoke-ExpiredDecline' {
    It 'declines every expired update that is not declined, except those on the never-decline list' {
      $Server = New-FakeUpdateServer -Updates @(
        New-FakeUpdate -Title 'Expired 1' -Kb @('5000101') -Expired $True
        New-FakeUpdate -Title 'Expired 2' -Kb @('5000102') -Expired $True
        New-FakeUpdate -Title 'Expired declined' -Expired $True -Declined $True
        New-FakeUpdate -Title 'Published'
      )

      $Result = Invoke-ExpiredDecline -Context (New-DeclineContext -Server $Server -Declines '"neverDecline": [ "5000102" ]')

      $Server.State.DeclinedUpdates | Should -Be @('Expired 1')
      $Result.Counts['Expired'] | Should -Be 2
      $Result.Counts['Protected'] | Should -Be 1
      $Result.Message | Should -Be 'Declined 1 of 1 expired update(s); 0 failed. 3 update(s) evaluated.'
    }

    It 'records a failed decline as an error and a budget stop as a warning' {
      $Failing = New-FakeUpdateServer -Updates @(New-FakeUpdate -Title 'Expired 1' -Expired $True) -FailingUpdates @('Expired 1')
      $Stopping = New-FakeUpdateServer -Updates @(New-FakeUpdate -Title 'Expired 2' -Expired $True)

      $Failed = Invoke-ExpiredDecline -Context (New-DeclineContext -Server $Failing)
      Mock -CommandName Test-MaintenanceBudget -MockWith { $True }
      $Stopped = Invoke-ExpiredDecline -Context (New-DeclineContext -Server $Stopping)

      $Failed.Status | Should -Be 'Error'
      $Failed.Notices[0].Message | Should -BeLike '1 update(s) could not be declined. First failure: failed: Expired 1*'
      $Stopped.Status | Should -Be 'Warning'
      $Stopped.Notices[0].Message | Should -Be 'Time budget reached after 0 of 1 decline(s); the rest are declined on the next run.'
    }

    It 'reports the pending declines in a dry run' {
      $Server = New-FakeUpdateServer -Updates @(New-FakeUpdate -Title 'Expired 1' -Expired $True)

      $Result = Invoke-ExpiredDecline -Context (New-DeclineContext -Server $Server -DryRun $True)

      $Server.State.DeclinedUpdates | Should -HaveCount 0
      $Result.Message | Should -Be 'pending: 1 expired update(s) would be declined. 1 update(s) evaluated.'
    }
  }

  Context 'Invoke-RuleDecline' {
    BeforeAll {
      Function script:New-RuleFleet {
        @(
          New-FakeUpdate -Title 'Windows 10 Preview Build' -Kb @('5000201') -Products @('Windows 10') -Created $script:Now.AddDays(-10)
          New-FakeUpdate -Title 'Itanium Security Update' -Kb @('5000202') -Products @('Windows Server 2008 R2') -Created $script:Now.AddDays(-400)
          New-FakeUpdate -Title 'Driver from a vendor' -Kb @() -Classification 'Drivers' -Source 'Other' -Created $script:Now.AddDays(-50)
          New-FakeUpdate -Title 'Kept update' -Kb @('5000204') -Products @('Windows Server 2022') -Created $script:Now.AddDays(-5)
        )
      }

      $script:Rules = '"rules": [ ' +
      '{ "name": "Previews", "enabled": true, "condition": { "all": [ { "field": "Title", "operator": "Like", "value": "*preview*" }, { "not": { "field": "ProductTitles", "operator": "Equals", "value": "Windows Server 2022" } } ] } }, ' +
      '{ "name": "Old Itanium", "enabled": true, "group": "Legacy", "condition": { "any": [ { "field": "Title", "operator": "Match", "value": "itanium|ia64" }, { "field": "KnowledgeBaseArticles", "operator": "Equals", "value": "KB9999999" } ] } }, ' +
      '{ "name": "Third party", "enabled": true, "condition": { "all": [ { "field": "UpdateSource", "operator": "Equals", "value": "Other" }, { "field": "CreationDate", "operator": "OlderThanDays", "value": 30 } ] } }, ' +
      '{ "name": "Switched off", "enabled": false, "condition": { "field": "Title", "operator": "Contains", "value": "Kept" } } ]'
    }

    It 'declines exactly what each enabled rule describes and reports each rule' {
      $Server = New-FakeUpdateServer -Updates (New-RuleFleet)

      $Result = Invoke-RuleDecline -Context (New-DeclineContext -Server $Server -Declines ($script:Rules + ', "groups": [ { "name": "Legacy", "enabled": true } ]'))

      $Result.Status | Should -Be 'Success'
      $Server.State.DeclinedUpdates | Should -Be @('Windows 10 Preview Build', 'Itanium Security Update', 'Driver from a vendor')
      $Result.Counts['Rules'] | Should -Be 3
      $Result.Items | Should -Contain 'rule Previews: 1 matched, 1 declined, 0 failed'
      $Result.Items | Should -Contain ('declined: [Old Itanium] Itanium Security Update (KB5000202, created {0})' -f $script:Now.AddDays(-400).ToString('yyyy-MM-dd'))
      $Result.Items | Should -Contain ('declined: [Third party] Driver from a vendor (no Knowledge Base article, created {0})' -f $script:Now.AddDays(-50).ToString('yyyy-MM-dd'))
      $Result.Message | Should -Be 'Evaluated 3 rule(s) over 4 update(s) in language en: 3 matched, 3 declined, 0 failed.'
      $Server.State.Cultures | Should -Be @('en', '')
    }

    It 'runs no rule of a disabled group, and never declines an update on the never-decline list' {
      $Server = New-FakeUpdateServer -Updates (New-RuleFleet)

      $Result = Invoke-RuleDecline -Context (New-DeclineContext -Server $Server -Declines ($script:Rules + ', "groups": [ { "name": "legacy", "enabled": false } ], "neverDecline": [ "KB5000201" ]'))

      $Server.State.DeclinedUpdates | Should -Be @('Driver from a vendor')
      $Result.Counts['Rules'] | Should -Be 2
      $Result.Counts['Protected'] | Should -Be 1
      $Result.Items | Should -Contain 'rule Previews: 1 matched, 0 declined, 0 failed'
    }

    It 'reports zero new declines for updates an earlier policy of the run declined' {
      $Server = New-FakeUpdateServer -Updates (New-RuleFleet)
      $Context = New-DeclineContext -Server $Server -Declines ('"rules": [ { "name": "Everything old", "enabled": true, "condition": { "field": "CreationDate", "operator": "OlderThanDays", "value": 30 } }, { "name": "Itanium again", "enabled": true, "condition": { "field": "Title", "operator": "Contains", "value": "itanium" } } ]')

      $Result = Invoke-RuleDecline -Context $Context

      $Result.Items | Should -Contain 'rule Everything old: 2 matched, 2 declined, 0 failed'
      $Result.Items | Should -Contain 'rule Itanium again: 0 matched, 0 declined, 0 failed'
    }

    It 'lists a failed decline of a rule and stops the rules at the time budget' {
      $Failing = New-FakeUpdateServer -Updates (New-RuleFleet) -FailingUpdates @('Driver from a vendor')
      $Stopping = New-FakeUpdateServer -Updates (New-RuleFleet)

      $Failed = Invoke-RuleDecline -Context (New-DeclineContext -Server $Failing -Declines $script:Rules)
      Mock -CommandName Test-MaintenanceBudget -MockWith { $True }
      $Stopped = Invoke-RuleDecline -Context (New-DeclineContext -Server $Stopping -Declines $script:Rules)

      $Failed.Status | Should -Be 'Error'
      $Failed.Items[-1] | Should -BeLike 'failed: [[]Third party] Driver from a vendor (*): *could not be declined*'
      $Failed.Notices[0].Message | Should -BeLike '1 rule decline(s) failed. First failure: failed: *'
      $Stopped.Status | Should -Be 'Warning'
      $Stopped.Counts['Rules'] | Should -Be 1
      $Stopped.Notices[0].Message | Should -Be 'Time budget reached while rule Previews was declining; the remaining declines and rules run on the next run.'
    }

    It 'lists the pending declines of each rule in a dry run' {
      $Server = New-FakeUpdateServer -Updates (New-RuleFleet)

      $Result = Invoke-RuleDecline -Context (New-DeclineContext -Server $Server -Declines $script:Rules -DryRun $True)

      $Server.State.DeclinedUpdates | Should -HaveCount 0
      $Result.Items | Should -Contain 'rule Previews: 1 matched, pending: 1'
      $Result.Message | Should -Be 'pending: 3 update(s) would be declined by 3 rule(s); 3 matched of 4 update(s) evaluated in language en.'
    }

    It 'skips the rules with an Error notice when the evaluation language cannot be set, while age-based declines still run' {
      $Server = New-FakeUpdateServer -Updates @((New-RuleFleet) + @(New-FakeUpdate -Title 'Old leaf' -Superseded $True -Created $script:Now.AddDays(-200))) -CultureFails $True
      $Context = New-DeclineContext -Server $Server -Declines $script:Rules

      $Rules = Invoke-RuleDecline -Context $Context
      $Superseded = Invoke-SupersededDecline -Context $Context

      $Rules.Status | Should -Be 'Error'
      $Rules.Message | Should -Be 'skipped: the evaluation language could not be set'
      $Rules.Notices[0].Message | Should -BeLike 'Rule-based declines were skipped: the evaluation language en could not be set (*not supported*). The age- and state-based declines still ran.'
      $Superseded.Counts['Declined'] | Should -Be 1
      $Server.State.DeclinedUpdates | Should -Be @('Old leaf')
      (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'The evaluation language en could not be set'
    }

    It 'reports a rule that cannot be evaluated and runs the next one' {
      $Server = New-FakeUpdateServer -Updates (New-RuleFleet)

      $Result = Invoke-RuleDecline -Context (New-DeclineContext -Server $Server -Declines '"rules": [ { "name": "Broken", "enabled": true, "condition": { "field": "Title", "operator": "Match", "value": "(" } }, { "name": "Previews", "enabled": true, "condition": { "field": "Title", "operator": "Contains", "value": "preview" } } ]')

      $Result.Status | Should -Be 'Error'
      @($Result.Items | Where-Object -FilterScript { $PSItem -like 'rule Broken could not be evaluated: *' }) | Should -HaveCount 1
      $Server.State.DeclinedUpdates | Should -Be @('Windows 10 Preview Build')
    }
  }

  Context 'decline policies over one run' {
    It 'retrieves the update list once, in the evaluation language, and restores the previous language' {
      $Server = New-FakeUpdateServer -Updates @(New-FakeUpdate -Title 'Expired 1' -Expired $True)
      $Server.State.Culture = 'de'
      $Context = New-DeclineContext -Server $Server -Declines '"evaluationLanguage": "en-US"'

      $Null = Invoke-SupersededDecline -Context $Context
      $Null = Invoke-ExpiredDecline -Context $Context

      $Server.State.UpdateScopes | Should -HaveCount 1
      $Server.State.Cultures | Should -Be @('en-US', 'de')
      $Server.State.Culture | Should -Be 'de'
      (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Update titles and category names are retrieved in language en-US\.'
    }

    It 'makes no decline, with one Error notice naming the likely cause, when the update list cannot be retrieved' {
      $Server = New-FakeUpdateServer -Updates @(New-FakeUpdate -Title 'Expired 1' -Expired $True) -UpdatesFailure 'The operation has timed out.'
      $Context = New-DeclineContext -Server $Server

      $Results = @(
        Invoke-SupersededDecline -Context $Context
        Invoke-ExpiredDecline -Context $Context
        Invoke-RuleDecline -Context $Context
      )

      $Server.State.DeclinedUpdates | Should -HaveCount 0
      $Server.State.Culture | Should -Be ''
      ForEach ($Result In $Results) {
        $Result.Status | Should -Be 'Error'
        $Result.Message | Should -Be 'no declines were made: the update list could not be retrieved (The operation has timed out.)'
      }
      $Results[0].Notices | Should -HaveCount 1
      $Results[0].Notices[0].Message | Should -BeLike 'The update list could not be retrieved, so no decline policy acted in this run: The operation has timed out. A common cause is memory exhaustion of the WsusPool application pool in IIS.*'
      $Results[1].Notices | Should -HaveCount 0
    }

    It 'logs a warning when the previous language cannot be restored' {
      $Server = New-FakeUpdateServer -Updates @(New-FakeUpdate -Title 'Expired 1' -Expired $True)
      $Server | Add-Member -Force -MemberType ScriptProperty -Name PreferredCulture -Value { 'fr' } -SecondValue {
        Param ($Value)
        If ($Value -ne 'en') { Throw 'The culture could not be changed back.' }
      }

      $Result = Invoke-ExpiredDecline -Context (New-DeclineContext -Server $Server)

      $Result.Counts['Declined'] | Should -Be 1
      (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match "Warning\s+\[RUN\] Stage: The previous language preference 'fr' could not be restored: .*could not be changed back"
    }

    It 'evaluates only updates that arrived within the arrival window when one is set' {
      $Server = New-FakeUpdateServer -Updates @(
        New-FakeUpdate -Title 'Recent' -Expired $True -Arrived $script:Now.AddDays(-5)
        New-FakeUpdate -Title 'Old arrival' -Expired $True -Arrived $script:Now.AddDays(-50)
      )

      $Result = Invoke-ExpiredDecline -Context (New-DeclineContext -Server $Server -Declines '"arrivalWindowDays": 30')

      $Server.State.DeclinedUpdates | Should -Be @('Recent')
      $Result.Counts['Evaluated'] | Should -Be 1
      $Server.State.UpdateScopes[0].FromArrivalDate | Should -Be $script:Now.AddDays(-30)
    }

    It 'needs the WSUS connection discovery opens' {
      { Invoke-ExpiredDecline -Context (New-FakeStageContext) } | Should -Throw -ExpectedMessage 'No WSUS connection is open; the stage needs the discovery steps to have run.'
    }
  }
}
