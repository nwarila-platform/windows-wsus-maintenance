#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-ObsoleteUpdateCleanup' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # A SUSDB whose obsolete-update procedure returns -Identifiers; deleting an identifier listed
    #   in -Failing fails.
    Function script:New-ObsoleteDatabase {
      Param ([System.Int32[]]$Identifiers = @(), [System.Int32[]]$Failing = @())
      $Responder = {
        Param ($Text, $Parameters, $NonQuery)
        If ($NonQuery) {
          If ($Failing -contains $Parameters['@localUpdateID']) { Throw 'The DELETE statement conflicted with the REFERENCE constraint.' }
          1
        } Else {
          ForEach ($Identifier In $Identifiers) { [PSCustomObject]@{ LocalUpdateID = $Identifier } }
        }
      }.GetNewClosure()
      New-FakeSqlConnection -Responder $Responder
    }

    Function script:Get-Deletions {
      Param ($Database)
      @($Database.Commands | Where-Object -FilterScript { $PSItem.CommandText -like 'EXEC dbo.spDeleteUpdate*' } | ForEach-Object -Process { $PSItem.Parameters.Values['@localUpdateID'] })
    }
  }

  BeforeEach {
    $script:Clock = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Clock }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'deletes every obsolete update one at a time and logs each deletion' {
    $Database = New-ObsoleteDatabase -Identifiers @(101, 102, 103)

    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database -Log $script:Log)

    $Result.Status | Should -Be 'Success'
    $Result.Message | Should -Be 'Found 3 obsolete update(s); deleted 3; 0 failed.'
    $Result.Items | Should -Be @('101', '102', '103')
    $Result.Notices | Should -HaveCount 0
    @($Result.Counts.Keys) | Should -Be @('Found', 'Selected', 'Deleted', 'Failed')
    $Result.Counts['Deleted'] | Should -Be 3
    Get-Deletions -Database $Database | Should -Be @(101, 102, 103)
    $Database.Commands[0].CommandText | Should -Be 'EXEC dbo.spGetObsoleteUpdatesToCleanup'
    $Database.Commands[1].CommandText | Should -Be 'EXEC dbo.spDeleteUpdate @localUpdateID = @localUpdateID'
    $Progress = @(Get-Content -LiteralPath $script:Log.Path | Where-Object -FilterScript { $PSItem -like '*ObsoleteUpdates: Progress*' })
    $Progress | Should -HaveCount 3
    $Progress[0] | Should -BeLike '*Progress 1 of 3: update 101 deleted in 0.0 s (0.0 s elapsed).'
    $Progress[2] | Should -BeLike '*Progress 3 of 3: update 103 deleted in 0.0 s (0.0 s elapsed).'
  }

  It 'logs progress once per batch and for the last update' {
    $Database = New-ObsoleteDatabase -Identifiers @(1, 2, 3, 4, 5)

    $Null = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database -Log $script:Log -Extra ', "run": { "progressBatchSize": 2 }')

    @(Get-Content -LiteralPath $script:Log.Path | Where-Object -FilterScript { $PSItem -like '*ObsoleteUpdates: Progress*' }) | Should -HaveCount 3
  }

  It 'deletes exactly the capped number and warns that the cap was reached' {
    $Database = New-ObsoleteDatabase -Identifiers @(1, 2, 3, 4, 5)

    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database -Extra ', "obsoleteUpdates": { "maxDeletions": 2 }')

    Get-Deletions -Database $Database | Should -Be @(1, 2)
    $Result.Status | Should -Be 'Warning'
    $Result.Counts['Found'] | Should -Be 5
    $Result.Counts['Selected'] | Should -Be 2
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'Cap reached: obsoleteUpdates.maxDeletions allows 2 deletions per run and 5 obsolete updates were found; the rest are deleted on later runs.'
  }

  It 'records a failed deletion, carries on and ends in error' {
    $Database = New-ObsoleteDatabase -Identifiers @(1, 2, 3) -Failing @(2)

    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database -Log $script:Log)

    Get-Deletions -Database $Database | Should -Be @(1, 2, 3)
    $Result.Status | Should -Be 'Error'
    $Result.Counts['Deleted'] | Should -Be 2
    $Result.Counts['Failed'] | Should -Be 1
    $Result.Items[-1] | Should -BeLike '2: deletion failed: *REFERENCE constraint.'
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Error'
    $Result.Notices[0].Message | Should -BeLike '1 obsolete update(s) could not be deleted. First failure: 2: deletion failed: *'
    $Text = Get-Content -LiteralPath $script:Log.Path -Raw
    $Text | Should -Match 'Error\s+\[RUN\] ObsoleteUpdates: 2: deletion failed'
    $Text | Should -Match 'Progress 2 of 3: update 2 failed after 0\.0 s'
  }

  It 'stops at the first refusal on a replica and reports it as rejected by server role' {
    $Database = New-ObsoleteDatabase -Identifiers @(1, 2, 3) -Failing @(1, 2, 3)

    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database -Tier 'Replica')

    Get-Deletions -Database $Database | Should -Be @(1)
    $Result.Status | Should -Be 'Warning'
    $Result.Message | Should -Be 'rejected by server role'
    $Result.Counts['Failed'] | Should -Be 0
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -BeLike 'The database rejected the deletion of obsolete updates, as expected on a replica (rejected by server role): *'
  }

  It 'stops between deletions when the time budget runs out' {
    $Database = New-ObsoleteDatabase -Identifiers @(1, 2, 3, 4)
    $script:BudgetChecks = 0
    Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 2 }

    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database)

    Get-Deletions -Database $Database | Should -Be @(1, 2)
    $Result.Status | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'Time budget reached after deleting 2 of 4 selected obsolete updates; the rest are deleted on the next run.'
  }

  It 'deletes nothing in a dry run and lists what it would delete' {
    $Database = New-ObsoleteDatabase -Identifiers @(7, 8, 9)

    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database $Database -DryRun $True -Extra ', "obsoleteUpdates": { "maxDeletions": 2 }')

    Get-Deletions -Database $Database | Should -HaveCount 0
    $Result.Message | Should -Be 'Would delete 2 of 3 obsolete update(s).'
    $Result.Items | Should -Be @('7', '8')
  }

  It 'succeeds with nothing to delete' {
    $Result = Invoke-ObsoleteUpdateCleanup -Context (New-FakeStageContext -Database (New-ObsoleteDatabase))

    $Result.Status | Should -Be 'Success'
    $Result.Message | Should -Be 'Found 0 obsolete update(s); deleted 0; 0 failed.'
  }
}
