#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Remove-SyncHistory' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # A SUSDB holding -Matching old synchronization-history records; each batched delete removes
    #   up to its batch size. -NoColumn removes the TimeAtServer column.
    Function script:New-HistoryDatabase {
      Param ([System.Int64]$Matching = 0, [System.Boolean]$NoColumn = $False)
      $State = @{ Left = $Matching }
      $Responder = {
        Param ($Text, $Parameters, $NonQuery)
        If ($NonQuery) {
          $Removed = [System.Math]::Min($State.Left, [System.Int64]$Parameters['@batch'])
          $State.Left = $State.Left - $Removed
          $Removed
        } ElseIf ($Text -match 'COL_LENGTH') {
          [PSCustomObject]@{ Length = $(If ($NoColumn) { $Null } Else { 8 }) }
        } ElseIf ($Text -match 'COUNT_BIG') {
          [PSCustomObject]@{ Total = $State.Left }
        }
      }.GetNewClosure()
      New-FakeSqlConnection -Responder $Responder
    }

    Function script:Get-Deletes {
      Param ($Database)
      @($Database.Commands | Where-Object -FilterScript { $PSItem.CommandText -like 'DELETE*' })
    }
  }

  It 'removes the records older than the retention in batches' {
    $Database = New-HistoryDatabase -Matching 25000

    $Result = Remove-SyncHistory -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Success'
    $Result.Counts['Matched'] | Should -Be 25000
    $Result.Counts['Removed'] | Should -Be 25000
    $Result.Message | Should -Be 'Removed 25000 synchronization-history record(s) older than 90 day(s).'
    $Deletes = Get-Deletes -Database $Database
    $Deletes | Should -HaveCount 3
    $Deletes[0].CommandText | Should -Be "DELETE TOP (@batch) FROM dbo.tbEventInstance WHERE EventNamespaceID = '2' AND EventID IN ('381', '382', '384', '386', '387', '389') AND TimeAtServer < DATEADD(DAY, -@days, GETUTCDATE())"
    $Deletes[0].Parameters.Values['@days'] | Should -Be 90
    $Deletes[0].Parameters.Values['@batch'] | Should -Be 10000
    $Database.Commands[0].CommandText | Should -Be "SELECT COL_LENGTH(N'dbo.tbEventInstance', N'TimeAtServer') AS Length"
  }

  It 'removes every such record without an age test when the retention is zero' {
    $Database = New-HistoryDatabase -Matching 3

    $Result = Remove-SyncHistory -Context (New-FakeStageContext -Database $Database -Extra ', "syncHistory": { "retentionDays": 0 }')

    $Result.Counts['Removed'] | Should -Be 3
    $Result.Message | Should -Be 'Removed 3 synchronization-history record(s) of any age (retention 0).'
    (Get-Deletes -Database $Database)[0].CommandText | Should -Not -Match 'TimeAtServer'
    @(Get-FakeCommandText -Connection $Database | Where-Object -FilterScript { $PSItem -match 'COL_LENGTH' }) | Should -HaveCount 0
  }

  It 'deletes nothing and warns when the age of a record cannot be determined' {
    $Database = New-HistoryDatabase -Matching 3 -NoColumn $True

    $Result = Remove-SyncHistory -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Warning'
    $Result.Message | Should -Be 'not cleaned: record age cannot be determined'
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -BeLike 'Synchronization history was not cleaned: dbo.tbEventInstance has no TimeAtServer column*'
    @(Get-FakeCommandText -Connection $Database) | Should -HaveCount 1
  }

  It 'stops between batches when the time budget runs out' {
    $Database = New-HistoryDatabase -Matching 25000
    $script:BudgetChecks = 0
    Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 1 }

    $Result = Remove-SyncHistory -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Warning'
    $Result.Counts['Removed'] | Should -Be 10000
    $Result.Notices[0].Message | Should -Be 'Time budget reached after removing 10000 synchronization-history record(s); the rest are removed on the next run.'
  }

  It 'only counts in a dry run' {
    $Database = New-HistoryDatabase -Matching 42

    $Result = Remove-SyncHistory -Context (New-FakeStageContext -Database $Database -DryRun $True)

    Get-Deletes -Database $Database | Should -HaveCount 0
    $Result.Counts['Matched'] | Should -Be 42
    $Result.Message | Should -Be 'Would remove 42 synchronization-history record(s) older than 90 day(s).'
  }
}
