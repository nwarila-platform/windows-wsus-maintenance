#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeAll {
  . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
}

Describe 'Get-SusdbIndexAction' {
  It 'chooses <Expected> for density <Density>, fill factor <FillFactor>, fragmentation <Fragmentation> and <RecordCount> rows' -ForEach @(
    @{ Density = 80.0; FillFactor = 90; Fragmentation = 50.0; RecordCount = 10000; Expected = 'Reorganize' }
    @{ Density = 75.0; FillFactor = 90; Fragmentation = 90.0; RecordCount = 10000; Expected = 'Reorganize' }
    @{ Density = 85.0; FillFactor = 90; Fragmentation = 90.0; RecordCount = 10000; Expected = 'Reorganize' }
    @{ Density = 85.1; FillFactor = 90; Fragmentation = 90.0; RecordCount = 10000; Expected = 'Rebuild' }
    @{ Density = 74.9; FillFactor = 90; Fragmentation = 90.0; RecordCount = 10000; Expected = 'Rebuild' }
    @{ Density = 60.0; FillFactor = 0; Fragmentation = 29.9; RecordCount = 10000; Expected = 'Reorganize' }
    @{ Density = 60.0; FillFactor = 0; Fragmentation = 30.0; RecordCount = 5000; Expected = 'RebuildWithFillFactor' }
    @{ Density = 80.0; FillFactor = 0; Fragmentation = 50.0; RecordCount = 5000; Expected = 'RebuildWithFillFactor' }
    @{ Density = 60.0; FillFactor = 0; Fragmentation = 40.0; RecordCount = 4999; Expected = 'Rebuild' }
    @{ Density = 60.0; FillFactor = 80; Fragmentation = 40.0; RecordCount = 10000; Expected = 'Rebuild' }
  ) {
    Get-SusdbIndexAction -Density $Density -FillFactor $FillFactor -Fragmentation $Fragmentation -RecordCount $RecordCount | Should -Be $Expected
  }
}

Describe 'Invoke-SusdbIndexMaintenance' {
  BeforeAll {
    Function script:New-IndexRow {
      Param ($ObjectId, $IndexId, $Table, $Index, $Density, $Fragmentation, $RecordCount, $FillFactor, $UsedPages)
      [PSCustomObject]@{
        ObjectId      = $ObjectId
        IndexId       = $IndexId
        TableName     = $Table
        IndexName     = $Index
        Density       = [System.Double]$Density
        Fragmentation = [System.Double]$Fragmentation
        RecordCount   = [System.Int64]$RecordCount
        FillFactor    = $FillFactor
        UsedPages     = [System.Int64]$UsedPages
      }
    }

    $script:Indexes = @(
      New-IndexRow 1 1 '[dbo].[tbA]' '[PK_A]' 60 20 100 0 100
      New-IndexRow 2 3 '[dbo].[tbB]' '[nclB]' 50 70 20000 0 400
      New-IndexRow 3 2 '[dbo].[tbC]' '[nclC]' 50 70 100 0 50
    )
    $script:After = @(
      [PSCustomObject]@{ ObjectId = 1; IndexId = 1; UsedPages = [System.Int64]90 }
      [PSCustomObject]@{ ObjectId = 2; IndexId = 3; UsedPages = [System.Int64]250 }
      [PSCustomObject]@{ ObjectId = 9; IndexId = 1; UsedPages = [System.Int64]5 }
    )

    # A SUSDB whose fragmentation query returns -Indexes and whose page query returns -After;
    #   commands matching -FailOn fail.
    Function script:New-ReindexDatabase {
      Param ([System.Object[]]$Indexes = $script:Indexes, [System.Object[]]$After = $script:After, [System.String]$FailOn = '')
      $Responder = {
        Param ($Text, $Parameters, $NonQuery)
        If (($FailOn -ne '') -and ($Text -match $FailOn)) { Throw 'Transaction was deadlocked on lock resources.' }
        If ($NonQuery) { -1 }
        ElseIf ($Text -match 'dm_db_index_physical_stats') { $Indexes }
        ElseIf ($Text -match 'dm_db_partition_stats') { $After }
      }.GetNewClosure()
      New-FakeSqlConnection -Responder $Responder
    }

    Function script:Get-Writes {
      Param ($Database)
      @(Get-FakeCommandText -Connection $Database | Where-Object -FilterScript { ($PSItem -notlike 'SELECT*') -and ($PSItem -notlike 'WITH Fragmented AS*') })
    }

    $script:Owner = [PSCustomObject]@{ Checked = $True; OwnerOrSysadmin = $True; LoginName = 'NT AUTHORITY\SYSTEM' }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'defragments each selected index as the published script decides, then updates statistics' {
    $Database = New-ReindexDatabase

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner -Log $script:Log)

    $Result.Status | Should -Be 'Success'
    Get-Writes -Database $Database | Should -Be @(
      'ALTER INDEX [PK_A] ON [dbo].[tbA] REORGANIZE'
      'ALTER INDEX [nclB] ON [dbo].[tbB] REBUILD WITH (FILLFACTOR = 90)'
      'ALTER INDEX [nclC] ON [dbo].[tbC] REBUILD'
      'EXEC sp_updatestats'
    )
    $Result.Items | Should -Be @(
      '[PK_A] on [dbo].[tbA]: reorganize (fragmentation 20.0%, page density 60.0%)'
      '[nclB] on [dbo].[tbB]: rebuild with fill factor 90 (fragmentation 70.0%, page density 50.0%)'
      '[nclC] on [dbo].[tbC]: rebuild (fragmentation 70.0%, page density 50.0%)'
    )
    $Result.Counts['Selected'] | Should -Be 3
    $Result.Counts['Reorganized'] | Should -Be 1
    $Result.Counts['Rebuilt'] | Should -Be 2
    $Result.Counts['PagesBefore'] | Should -Be 550
    $Result.Counts['PagesAfter'] | Should -Be 390
    $Result.Counts['PagesFreed'] | Should -Be 160
    $Result.Counts['StatisticsUpdated'] | Should -Be 1
    $Result.Message | Should -Be 'Reorganized 1 and rebuilt 2 index(es); 0 failed; about 160 page(s) freed; statistics updated.'
    @(Get-Content -LiteralPath $script:Log.Path | Where-Object -FilterScript { $PSItem -like '*Reindex: Progress*' }) | Should -HaveCount 3
  }

  It 'selects with the published thresholds from a sampled scan of the leaf level' {
    $Database = New-ReindexDatabase -Indexes @()

    $Null = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner)

    $Query = $Database.Commands[0].CommandText
    $Query | Should -Match "sys\.dm_db_index_physical_stats\(DB_ID\(\), NULL, NULL, NULL, 'SAMPLED'\)"
    $Query | Should -Match 'WHERE f\.index_id > 0'
    $Query | Should -Match 'PARTITION BY f\.object_id, f\.index_id'
    $Query | Should -Match 'WHERE f\.RowRank = 1'
    $Query | Should -Match 'f\.avg_page_space_used_in_percent < 85\.0'
    $Query | Should -Match 'f\.page_count > 50 AND f\.avg_fragmentation_in_percent > 15\.0'
    $Query | Should -Match 'f\.page_count > 10 AND f\.avg_fragmentation_in_percent > 80\.0'
  }

  It 'still updates statistics when no index needs work' {
    $Database = New-ReindexDatabase -Indexes @()

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner)

    Get-Writes -Database $Database | Should -Be @('EXEC sp_updatestats')
    $Result.Message | Should -Be 'Reorganized 0 and rebuilt 0 index(es); 0 failed; about 0 page(s) freed; statistics updated.'
  }

  It 'updates statistics when the permissions could not be checked' {
    $Database = New-ReindexDatabase -Indexes @()

    $Null = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission ([PSCustomObject]@{ Checked = $False; OwnerOrSysadmin = $False; LoginName = '' }))

    Get-Writes -Database $Database | Should -Be @('EXEC sp_updatestats')
  }

  It 'skips the statistics with the command that fixes it when the identity is neither owner nor sysadmin' {
    $Database = New-ReindexDatabase

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission ([PSCustomObject]@{ Checked = $True; OwnerOrSysadmin = $False; LoginName = 'EXAMPLE\wsus-maint' }))

    $Result.Status | Should -Be 'Warning'
    Get-Writes -Database $Database | Should -Not -Contain 'EXEC sp_updatestats'
    $Result.Counts['Rebuilt'] | Should -Be 2
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'Statistics were not updated: login EXAMPLE\wsus-maint is neither the SUSDB owner nor sysadmin, which sp_updatestats requires. Make the run identity the database owner or a sysadmin.'
    $Result.Notices[0].Command | Should -Be 'ALTER AUTHORIZATION ON DATABASE::[SUSDB] TO [EXAMPLE\wsus-maint];'
    $Result.Message | Should -BeLike '*; statistics not updated.'
  }

  It 'records a failed index, carries on and leaves the statistics alone' {
    $Database = New-ReindexDatabase -FailOn '^ALTER INDEX \[nclB\]'

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner -Log $script:Log)

    $Result.Status | Should -Be 'Error'
    $Result.Counts['Failed'] | Should -Be 1
    $Result.Counts['Rebuilt'] | Should -Be 1
    Get-Writes -Database $Database | Should -Not -Contain 'EXEC sp_updatestats'
    $Result.Items[1] | Should -BeLike '[[]nclB] on [[]dbo].[[]tbB]: rebuild with fill factor 90 (*): failed: *deadlocked*'
    $Result.Notices[0].Severity | Should -Be 'Error'
    $Result.Notices[0].Message | Should -Be '1 index(es) could not be defragmented; statistics were not updated for this run.'
    (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Error\s+\[RUN\] Reindex: \[nclB\]'
  }

  It 'ends in error when the statistics update fails' {
    $Database = New-ReindexDatabase -Indexes @() -FailOn 'sp_updatestats'

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner)

    $Result.Status | Should -Be 'Error'
    $Result.Counts['StatisticsUpdated'] | Should -Be 0
    $Result.Notices[0].Message | Should -BeLike 'Statistics could not be updated: *deadlocked*'
  }

  It 'stops between indexes when the time budget runs out and leaves the statistics for the next run' {
    $Database = New-ReindexDatabase
    $script:BudgetChecks = 0
    Mock -CommandName Test-MaintenanceBudget -MockWith { $script:BudgetChecks++; $script:BudgetChecks -gt 1 }

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner)

    $Result.Status | Should -Be 'Warning'
    Get-Writes -Database $Database | Should -Be @('ALTER INDEX [PK_A] ON [dbo].[tbA] REORGANIZE')
    $Result.Notices[0].Message | Should -Be 'Time budget reached before every selected index was handled; statistics were not updated. The rest is done on the next run.'
  }

  It 'changes nothing in a dry run and lists what it would do' {
    $Database = New-ReindexDatabase

    $Result = Invoke-SusdbIndexMaintenance -Context (New-FakeStageContext -Database $Database -Permission $script:Owner -DryRun $True)

    @(Get-FakeCommandText -Connection $Database) | Should -HaveCount 1
    $Result.Status | Should -Be 'Success'
    $Result.Items | Should -HaveCount 3
    $Result.Message | Should -Be 'Would defragment 3 index(es) and then update statistics.'
  }
}
