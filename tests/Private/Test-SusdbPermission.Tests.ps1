#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-SusdbPermission' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
  }

  It 'finds every permission for the database owner' {
    $Connection = New-FakeSqlConnection -Rows @(New-PermissionRow)

    $Permission = Test-SusdbPermission -Connection $Connection -TimeoutSeconds 0

    $Permission.Checked | Should -BeTrue
    $Permission.LoginName | Should -Be 'NT AUTHORITY\SYSTEM'
    $Permission.OwnerOrSysadmin | Should -BeTrue
    $Permission.MissingByStage.Count | Should -Be 0
    $Permission.Summary | Should -Be 'login NT AUTHORITY\SYSTEM, database owner; every stage has the permissions it needs'
    $Connection.Commands[0].CommandText | Should -Match "HAS_PERMS_BY_NAME\(DB_NAME\(\), N'DATABASE', N'BACKUP DATABASE'\)"
    $Connection.Commands[0].CommandTimeout | Should -Be 0
  }

  It 'names sysadmin standing' {
    $Permission = Test-SusdbPermission -Connection (New-FakeSqlConnection -Rows @(New-PermissionRow -IsSysadmin 1 -IsDatabaseOwner 0))

    $Permission.Summary | Should -BeLike 'login NT AUTHORITY\SYSTEM, sysadmin;*'
    $Permission.OwnerOrSysadmin | Should -BeTrue
  }

  It 'maps each missing permission to the stages that need it' {
    $Row = New-PermissionRow -IsDatabaseOwner 0 -CanBackup 0 -CanAlterSupersedenceTable 0 -CanAlterDeleteProcedure $Null -CanExecuteDeleteProcedure 0 -CanDeleteEvents 0

    $Permission = Test-SusdbPermission -Connection (New-FakeSqlConnection -Rows @($Row))

    $Permission.MissingByStage['Backup'] | Should -Be @('BACKUP DATABASE')
    $Permission.MissingByStage['CustomIndexes'] | Should -Be @('ALTER on dbo.tbLocalizedPropertyForRevision and dbo.tbRevisionSupersedesUpdate')
    $Permission.MissingByStage['DeleteUpdateFix'] | Should -Be @('ALTER on dbo.spDeleteUpdate')
    $Permission.MissingByStage['DeclinedDeletion'] | Should -Be @('EXECUTE on dbo.spDeleteUpdate')
    $Permission.MissingByStage['ObsoleteUpdates'] | Should -Be @('EXECUTE on dbo.spDeleteUpdate')
    $Permission.MissingByStage['SyncHistory'] | Should -Be @('DELETE on dbo.tbEventInstance')
    $Permission.MissingByStage.ContainsKey('Reindex') | Should -BeFalse
    $Permission.OwnerOrSysadmin | Should -BeFalse
    $Permission.Summary | Should -BeLike 'login NT AUTHORITY\SYSTEM, neither database owner nor sysadmin; missing: BACKUP DATABASE (for Backup); *'
  }

  It 'reports permissions it cannot query, without skipping any stage' -ForEach @(
    @{ Case = 'a failing query'; Connection = { New-FakeSqlConnection -Failure 'The server principal is not able to access the database.' }; Message = '*not able to access the database.' }
    @{ Case = 'no row'; Connection = { New-FakeSqlConnection }; Message = 'the permission query returned no row' }
  ) {
    $Permission = Test-SusdbPermission -Connection (& $Connection)

    $Permission.Checked | Should -BeFalse
    $Permission.OwnerOrSysadmin | Should -BeFalse
    $Permission.LoginName | Should -Be ''
    $Permission.MissingByStage.Count | Should -Be 0
    $Permission.Error | Should -BeLike $Message
    $Permission.Summary | Should -BeLike 'not checked: *'
  }
}
