#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Set-SusdbCustomIndex' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # A SUSDB whose index state is a table keyed by index name: TableExists, IndexExists and
    #   CreatedByScript as the state query returns them. Unlisted indexes are absent from tables
    #   that exist. Commands matching -FailOn fail.
    Function script:New-IndexDatabase {
      Param ([System.Collections.Hashtable]$State = @{}, [System.String]$FailOn = '')
      $Responder = {
        Param ($Text, $Parameters, $NonQuery)
        If (($FailOn -ne '') -and ($Text -match $FailOn)) { Throw 'Lock request time out period exceeded.' }
        If ($NonQuery) { 0 } Else {
          $Entry = $State[[System.String]$Parameters['@name']]
          If ($Null -eq $Entry) { [PSCustomObject]@{ TableExists = 1; IndexExists = 0; CreatedByScript = 0 } } Else { $Entry }
        }
      }.GetNewClosure()
      New-FakeSqlConnection -Responder $Responder
    }

    Function script:New-IndexState {
      Param ([System.Int32]$Table = 1, [System.Int32]$Index = 1, [System.Int32]$Ours = 0)
      [PSCustomObject]@{ TableExists = $Table; IndexExists = $Index; CreatedByScript = $Ours }
    }

    Function script:Get-Writes {
      Param ($Database)
      @($Database.Commands | Where-Object -FilterScript { $PSItem.CommandText -notlike 'SELECT*' })
    }
  }

  It 'creates each missing Microsoft index and tags it as created by the script' {
    $Database = New-IndexDatabase

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Success'
    $Result.Counts['Created'] | Should -Be 2
    $Result.Items | Should -Be @('nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision: created', 'nclSupercededUpdateID on dbo.tbRevisionSupersedesUpdate: created')
    $Result.Message | Should -Be 'Created 2 and removed 0 index(es); 0 already present; 0 failed.'
    $Writes = Get-Writes -Database $Database
    $Writes | Should -HaveCount 4
    $Writes[0].CommandText | Should -Be 'CREATE NONCLUSTERED INDEX [nclLocalizedPropertyID] ON [dbo].[tbLocalizedPropertyForRevision] ([LocalizedPropertyID] ASC)'
    $Writes[1].CommandText | Should -BeLike 'EXEC sys.sp_addextendedproperty @name = @property, @value = @value, *@level2type = N''INDEX'', @level2name = @name'
    $Writes[1].Parameters.Values['@property'] | Should -Be 'CreatedBy'
    $Writes[1].Parameters.Values['@value'] | Should -Be 'Invoke-WsusMaintenance'
    $Writes[1].Parameters.Values['@table'] | Should -Be 'tbLocalizedPropertyForRevision'
    $Writes[1].Parameters.Values['@name'] | Should -Be 'nclLocalizedPropertyID'
    $Writes[2].CommandText | Should -Be 'CREATE NONCLUSTERED INDEX [nclSupercededUpdateID] ON [dbo].[tbRevisionSupersedesUpdate] ([SupersededUpdateID] ASC)'
    $Database.Commands[0].Parameters.Values['@table'] | Should -Be 'dbo.tbLocalizedPropertyForRevision'
  }

  It 'reports indexes that already exist as present and changes nothing' {
    $Database = New-IndexDatabase -State @{ nclLocalizedPropertyID = (New-IndexState -Ours 1); nclSupercededUpdateID = (New-IndexState) }

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Success'
    $Result.Counts['Present'] | Should -Be 2
    $Result.Counts['Created'] | Should -Be 0
    $Result.Items | Should -Be @('nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision: already present', 'nclSupercededUpdateID on dbo.tbRevisionSupersedesUpdate: already present')
    Get-Writes -Database $Database | Should -HaveCount 0
  }

  It 'creates the additional indexes from the configuration, quoting every identifier and keeping the column order' {
    $Database = New-IndexDatabase -State @{ nclLocalizedPropertyID = (New-IndexState); nclSupercededUpdateID = (New-IndexState) }
    $Extra = ', "customIndexes": { "additional": [ { "name": "nclExtra]Index", "table": "tbUpdate", "columns": ["LocalUpdateID", "UpdateID"] } ] }'

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database -Extra $Extra)

    $Result.Counts['Created'] | Should -Be 1
    (Get-Writes -Database $Database)[0].CommandText | Should -Be 'CREATE NONCLUSTERED INDEX [nclExtra]]Index] ON [dbo].[tbUpdate] ([LocalUpdateID] ASC, [UpdateID] ASC)'
  }

  It 'removes only the indexes the script created when asked to' {
    $Database = New-IndexDatabase -State @{ nclLocalizedPropertyID = (New-IndexState -Ours 1); nclSupercededUpdateID = (New-IndexState) }

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database -RemoveCustomIndexes $True)

    $Result.Status | Should -Be 'Success'
    $Result.Counts['Removed'] | Should -Be 1
    $Result.Counts['Kept'] | Should -Be 1
    $Result.Items | Should -Be @('nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision: removed', 'nclSupercededUpdateID on dbo.tbRevisionSupersedesUpdate: kept, not created by this script')
    @((Get-Writes -Database $Database).CommandText) | Should -Be @('DROP INDEX [nclLocalizedPropertyID] ON [dbo].[tbLocalizedPropertyForRevision]')
  }

  It 'reports an absent index during removal without touching anything' {
    $Database = New-IndexDatabase

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database -RemoveCustomIndexes $True)

    $Result.Items[0] | Should -Be 'nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision: absent'
    Get-Writes -Database $Database | Should -HaveCount 0
  }

  It 'warns about an index it cannot process and still handles the others' {
    $Database = New-IndexDatabase -State @{ nclLocalizedPropertyID = (New-IndexState -Table 0 -Index 0) } -FailOn 'nclSupercededUpdateID'

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Warning'
    $Result.Counts['Failed'] | Should -Be 2
    $Result.Items[0] | Should -Be 'nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision: failed: the table dbo.tbLocalizedPropertyForRevision does not exist'
    $Result.Items[1] | Should -BeLike 'nclSupercededUpdateID on dbo.tbRevisionSupersedesUpdate: failed: *Lock request time out period exceeded.'
    $Result.Notices | Should -HaveCount 2
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Stage | Should -Be 'CustomIndexes'
    $Result.Notices[0].Message | Should -Be 'Custom index nclLocalizedPropertyID on dbo.tbLocalizedPropertyForRevision could not be processed: the table dbo.tbLocalizedPropertyForRevision does not exist'
  }

  It 'changes nothing in a dry run and says what it would do' -ForEach @(
    @{ Remove = $False; Message = 'Would create 2 and remove 0 index(es); 0 already present.' }
    @{ Remove = $True; Message = 'Would create 0 and remove 2 index(es); 0 already present.' }
  ) {
    $Database = New-IndexDatabase -State $(If ($Remove) { @{ nclLocalizedPropertyID = (New-IndexState -Ours 1); nclSupercededUpdateID = (New-IndexState -Ours 1) } } Else { @{} })

    $Result = Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Database -DryRun $True -RemoveCustomIndexes $Remove)

    $Result.Message | Should -Be $Message
    Get-Writes -Database $Database | Should -HaveCount 0
  }

  It 'needs the SUSDB connection discovery opens' {
    { Set-SusdbCustomIndex -Context (New-FakeStageContext -Database $Null) } | Should -Throw -ExpectedMessage 'No SUSDB connection is open; the stage needs the discovery steps to have run.'
  }
}
