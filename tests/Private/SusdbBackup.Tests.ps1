#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
  . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

  $script:Now = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)

  Function script:New-BackupFolder {
    Param ([System.String[]]$Name = @())
    $Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path $Folder
    ForEach ($Each In $Name) {
      [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath $Each), ('x' * 10))
    }
    $Folder
  }

  Function script:Get-FileName {
    Param ([System.String]$Folder)
    $Names = [System.String[]]@([System.IO.Directory]::GetFiles($Folder) | ForEach-Object -Process { [System.IO.Path]::GetFileName($PSItem) })
    [System.Array]::Sort($Names, [System.StringComparer]::Ordinal)
    $Names
  }
}

Describe 'Remove-BackupFile' {
  It 'deletes a file only when it is outside the most recent set and old enough, with <Case>' -ForEach @(
    @{ Case = 'both limits'; Kept = 2; Age = 7; Deleted = @('SUSDB_20261026.bak', 'SUSDB_20261020.bak') }
    @{ Case = 'a minimum only'; Kept = 3; Age = 0; Deleted = @('SUSDB_20261026.bak', 'SUSDB_20261020.bak') }
    @{ Case = 'an age limit only'; Kept = 0; Age = 2; Deleted = @('SUSDB_20261031.bak', 'SUSDB_20261026.bak', 'SUSDB_20261020.bak') }
    @{ Case = 'a large minimum'; Kept = 10; Age = 1; Deleted = @() }
  ) {
    $Folder = New-BackupFolder -Name @('SUSDB_20261102.bak', 'SUSDB_20261101.bak', 'SUSDB_20261031.bak', 'SUSDB_20261026.bak', 'SUSDB_20261020.bak')

    $Result = Remove-BackupFile -Database 'SUSDB' -Folder $Folder -MaximumAgeDays $Age -MinimumKept $Kept -Now $script:Now

    $Result.Deleted | Should -Be $Deleted
    $Result.FreedBytes | Should -Be (10 * @($Deleted).Count)
    $Result.Kept | Should -Be (5 - @($Deleted).Count)
    $Result.NoPolicy | Should -BeFalse
    ForEach ($Name In $Deleted) {
      Test-Path -LiteralPath (Join-Path -Path $Folder -ChildPath $Name) | Should -BeFalse
    }
  }

  It 'keeps every file when both limits are zero' {
    $Folder = New-BackupFolder -Name @('SUSDB_20200101.bak')

    $Result = Remove-BackupFile -Database 'SUSDB' -Folder $Folder -MaximumAgeDays 0 -MinimumKept 0 -Now $script:Now

    $Result.NoPolicy | Should -BeTrue
    $Result.Deleted | Should -HaveCount 0
    $Result.Kept | Should -Be 1
  }

  It 'touches only the files it names, at the top of the folder' {
    $Folder = New-BackupFolder -Name @('susdb_20200101.BAK', 'SUSDB_20200101.bak.old', 'OTHER_20200101.bak', 'SUSDB_2020010.bak', 'SUSDB_20201340.bak', 'SUSDB-manual.bak')
    $Nested = Join-Path -Path $Folder -ChildPath 'archive'
    $Null = New-Item -ItemType Directory -Path $Nested
    [System.IO.File]::WriteAllText((Join-Path -Path $Nested -ChildPath 'SUSDB_20200101.bak'), 'x')

    $Result = Remove-BackupFile -Database 'SUSDB' -Folder $Folder -MaximumAgeDays 1 -MinimumKept 0 -Now $script:Now

    $Result.Deleted | Should -Be @('susdb_20200101.BAK')
    Get-FileName -Folder $Folder | Should -Be @('OTHER_20200101.bak', 'SUSDB-manual.bak', 'SUSDB_2020010.bak', 'SUSDB_20200101.bak.old', 'SUSDB_20201340.bak')
    Test-Path -LiteralPath (Join-Path -Path $Nested -ChildPath 'SUSDB_20200101.bak') | Should -BeTrue
  }

  It 'finds nothing in a folder that does not exist' {
    $Result = Remove-BackupFile -Database 'SUSDB' -Folder (Join-Path -Path $TestDrive -ChildPath 'missing') -MaximumAgeDays 1 -MinimumKept 1 -Now $script:Now

    $Result.Deleted | Should -HaveCount 0
    $Result.Kept | Should -Be 0
  }

  It 'reports without deleting in a dry run' {
    $Folder = New-BackupFolder -Name @('SUSDB_20261102.bak', 'SUSDB_20200101.bak')

    $Result = Remove-BackupFile -Database 'SUSDB' -DryRun $True -Folder $Folder -MaximumAgeDays 7 -MinimumKept 1 -Now $script:Now

    $Result.Deleted | Should -Be @('SUSDB_20200101.bak')
    Get-FileName -Folder $Folder | Should -HaveCount 2
  }

  It 'reports a file it cannot delete and carries on' -Skip:(-not $script:OnWindows) {
    $Folder = New-BackupFolder -Name @('SUSDB_20200101.bak', 'SUSDB_20200102.bak')
    $Stream = [System.IO.File]::Open((Join-Path -Path $Folder -ChildPath 'SUSDB_20200101.bak'), 'Open', 'Read', 'None')

    Try {
      $Result = Remove-BackupFile -Database 'SUSDB' -Folder $Folder -MaximumAgeDays 1 -MinimumKept 0 -Now $script:Now
    } Finally {
      $Stream.Dispose()
    }

    $Result.Deleted | Should -Be @('SUSDB_20200102.bak')
    $Result.Errors | Should -HaveCount 1
    $Result.Errors[0] | Should -BeLike 'SUSDB_20200101.bak could not be deleted: *'
  }
}

Describe 'Backup-Susdb' {
  BeforeAll {
    # A SUSDB on an engine of -Edition whose backup command writes a ten-byte file, unless it
    #   matches -FailOn or -NoFile is set.
    Function script:New-BackupDatabase {
      Param ([System.String]$Edition = 'Standard Edition (64-bit)', [System.String]$FailOn = '', [System.Boolean]$NoFile = $False)
      $Responder = {
        Param ($Text, $Parameters, $NonQuery)
        If (($FailOn -ne '') -and ($Text -match $FailOn)) { Throw 'Cannot open backup device. Operating system error 5(Access is denied.).' }
        If ($NonQuery) {
          If (-not $NoFile) { [System.IO.File]::WriteAllText($Parameters['@path'], ('b' * 10)) }
          -1
        } Else {
          [PSCustomObject]@{ Edition = $Edition; ReservedBytes = [System.Int64]1048576 }
        }
      }.GetNewClosure()
      New-FakeSqlConnection -Responder $Responder
    }

    Function script:New-BackupContext {
      Param ($Database, [System.String]$Folder, [System.Boolean]$DryRun = $False, [System.Collections.Hashtable]$Backup = @{})
      $Context = New-FakeStageContext -Database $Database -DryRun $DryRun -Log $script:Log
      $Context.Configuration.backup.destination = $Folder
      ForEach ($Key In $Backup.Keys) {
        $Context.Configuration.backup.$Key = $Backup[$Key]
      }
      $Context
    }

    Function script:Get-BackupCommand {
      Param ($Database)
      @($Database.Commands | Where-Object -FilterScript { $PSItem.CommandText -like 'BACKUP*' })
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Now }
    Mock -CommandName Get-BackupDestinationSpace -MockWith { [System.Int64]100GB }
    # Folder protection is exercised by the tests that turn it on.
    Mock -CommandName Test-MaintenanceAclSupport -MockWith { $False }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'writes a dated full backup with checksums and then applies the retention' {
    $Folder = New-BackupFolder -Name @('SUSDB_20261101.bak', 'SUSDB_20261026.bak', 'SUSDB_20261020.bak', 'notes.txt')
    $Database = New-BackupDatabase

    $Result = Backup-Susdb -Context (New-BackupContext -Database $Database -Folder $Folder -Backup @{ minimumKept = 2 })

    $Path = [System.IO.Path]::Combine($Folder, 'SUSDB_20261102.bak')
    $Result.Status | Should -Be 'Success'
    $Command = Get-BackupCommand -Database $Database
    $Command | Should -HaveCount 1
    $Command[0].CommandText | Should -Be 'BACKUP DATABASE [SUSDB] TO DISK = @path WITH CHECKSUM, INIT, COMPRESSION, NAME = @name, STATS = 10'
    $Command[0].Parameters.Values['@path'] | Should -Be $Path
    $Command[0].Parameters.Values['@name'] | Should -Be 'SUSDB full backup 2026-11-02 01:00'
    $Command[0].CommandTimeout | Should -Be 0
    $Result.Counts['Created'] | Should -Be 1
    $Result.Counts['EstimatedBytes'] | Should -Be 1048576
    $Result.Counts['FreeBytes'] | Should -Be 100GB
    $Result.Counts['SizeBytes'] | Should -Be 10
    $Result.Counts['Compressed'] | Should -Be 1
    $Result.Counts['Deleted'] | Should -Be 2
    $Result.Counts['FreedBytes'] | Should -Be 20
    $Result.Items | Should -Be @('SUSDB_20261026.bak', 'SUSDB_20261020.bak')
    $Result.Message | Should -Be ('Backup set "SUSDB full backup 2026-11-02 01:00" written to {0} (10 bytes, compressed, with checksum); 2 old backup file(s) deleted.' -f $Path)
    $Result.Notices | Should -HaveCount 0
    Get-FileName -Folder $Folder | Should -Be @('SUSDB_20261101.bak', 'SUSDB_20261102.bak', 'notes.txt')
  }

  It 'creates the backup folder when it does not exist yet' {
    $Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))

    $Result = Backup-Susdb -Context (New-BackupContext -Database (New-BackupDatabase) -Folder $Folder)

    $Result.Counts['Created'] | Should -Be 1
    Get-FileName -Folder $Folder | Should -Be @('SUSDB_20261102.bak')
  }

  Context 'folder protection' {
    BeforeEach {
      Mock -CommandName Test-MaintenanceAclSupport -MockWith { $True }
      Mock -CommandName Get-MaintenanceIdentitySid -MockWith { 'S-1-5-18' }
      Mock -CommandName Get-MaintenancePathAccess -MockWith { $Null }
      Mock -CommandName New-MaintenanceProtectedFolder -MockWith { $Null = [System.IO.Directory]::CreateDirectory($Path) }
      # The folder of the stand-in file system that standard users may add files to.
      $script:OpenAccess = [PSCustomObject]@{
        OwnerSid  = 'S-1-5-32-544'
        OwnerName = 'BUILTIN\Administrators'
        Rules     = @([PSCustomObject]@{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Rights = 6; Allow = $True })
      }
    }

    It 'creates a missing backup folder protected, with full control for the SQL Server service that writes the file' {
      $Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
      $Context = New-BackupContext -Database (New-BackupDatabase) -Folder $Folder
      $Context.Server.Environment | Add-Member -NotePropertyName SqlServerName -NotePropertyValue 'WSUS01\SQLEXPRESS'

      $Result = Backup-Susdb -Context $Context

      $Result.Status | Should -Be 'Success'
      Should -Invoke -CommandName New-MaintenanceProtectedFolder -Times 1 -Exactly -ParameterFilter { ($Path -eq $Folder) -and (($Identity -join ',') -eq 'S-1-5-18,S-1-5-32-544,NT SERVICE\MSSQL$SQLEXPRESS') }
      Get-FileName -Folder $Folder | Should -Be @('SUSDB_20261102.bak')
    }

    It 'makes no backup in an existing folder that standard users can change, and ends in error' {
      Mock -CommandName Get-MaintenancePathAccess -MockWith { $script:OpenAccess }
      $Database = New-BackupDatabase

      $Result = Backup-Susdb -Context (New-BackupContext -Database $Database -Folder (New-BackupFolder))

      $Result.Status | Should -Be 'Error'
      $Result.Notices | Should -HaveCount 1
      $Result.Notices[0].Severity | Should -Be 'High'
      $Result.Notices[0].Message | Should -BeLike 'The SUSDB backup to *SUSDB_20261102.bak failed: the backup folder cannot be used: it can be changed by BUILTIN\Users, not only by SYSTEM, Administrators and the run identity, so the run does not use it'
      Get-BackupCommand -Database $Database | Should -HaveCount 0
      Should -Invoke -CommandName New-MaintenanceProtectedFolder -Times 0 -Exactly
    }

    It 'backs up into such a folder, with a warning, when the override allows it' {
      Mock -CommandName Get-MaintenancePathAccess -MockWith { $script:OpenAccess }
      $Database = New-BackupDatabase
      $Context = New-BackupContext -Database $Database -Folder (New-BackupFolder)
      $Context.Configuration.run.permissiveFolderOverride = $True

      $Result = Backup-Susdb -Context $Context

      $Result.Status | Should -Be 'Success'
      Get-BackupCommand -Database $Database | Should -HaveCount 1
      $Result.Notices | Should -HaveCount 1
      $Result.Notices[0].Severity | Should -Be 'Warning'
      $Result.Notices[0].Message | Should -BeLike "The folder '*' can be changed by BUILTIN\Users*; it is used because run.permissiveFolderOverride is set."
    }
  }

  It 'uses <Options> for compression <Compression> on <Edition> with same-day <SameDay>' -ForEach @(
    @{ Compression = 'Auto'; Edition = 'Enterprise Edition: Core-based Licensing (64-bit)'; SameDay = 'Replace'; Options = 'INIT, COMPRESSION' }
    @{ Compression = 'Auto'; Edition = 'Developer Edition (64-bit)'; SameDay = 'Append'; Options = 'NOINIT, COMPRESSION' }
    @{ Compression = 'Auto'; Edition = 'Express Edition (64-bit)'; SameDay = 'Replace'; Options = 'INIT, NO_COMPRESSION' }
    @{ Compression = 'Auto'; Edition = 'Web Edition (64-bit)'; SameDay = 'Replace'; Options = 'INIT, NO_COMPRESSION' }
    @{ Compression = 'Always'; Edition = 'Express Edition (64-bit)'; SameDay = 'Replace'; Options = 'INIT, COMPRESSION' }
    @{ Compression = 'Never'; Edition = 'Enterprise Edition (64-bit)'; SameDay = 'Append'; Options = 'NOINIT, NO_COMPRESSION' }
  ) {
    $Database = New-BackupDatabase -Edition $Edition

    $Result = Backup-Susdb -Context (New-BackupContext -Database $Database -Folder (New-BackupFolder) -Backup @{ compression = $Compression; sameDay = $SameDay })

    (Get-BackupCommand -Database $Database)[0].CommandText | Should -Be ('BACKUP DATABASE [SUSDB] TO DISK = @path WITH CHECKSUM, {0}, NAME = @name, STATS = 10' -f $Options)
    $Result.Counts['Compressed'] | Should -Be ([System.Int32]($Options -notmatch 'NO_COMPRESSION'))
  }

  It 'skips the backup with a High notice when the destination lacks the space it needs' {
    Mock -CommandName Get-BackupDestinationSpace -MockWith { [System.Int64]1000 }
    $Folder = New-BackupFolder -Name @('SUSDB_20200101.bak')
    $Database = New-BackupDatabase

    $Result = Backup-Susdb -Context (New-BackupContext -Database $Database -Folder $Folder)

    $Result.Status | Should -Be 'Warning'
    $Result.Message | Should -Be 'skipped: not enough free space'
    $Result.Counts['Created'] | Should -Be 0
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'High'
    $Result.Notices[0].Message | Should -Be ('The SUSDB backup was skipped: {0} has 1000 bytes free, and the estimated backup needs 1258292 bytes including the 20% margin.' -f $Folder)
    Get-BackupCommand -Database $Database | Should -HaveCount 0
    Get-FileName -Folder $Folder | Should -Be @('SUSDB_20200101.bak')
  }

  It 'attempts the backup with a note when the free space cannot be read' {
    Mock -CommandName Get-BackupDestinationSpace -MockWith { Throw 'The UNC path is not a drive.' }
    $Database = New-BackupDatabase

    $Result = Backup-Susdb -Context (New-BackupContext -Database $Database -Folder (New-BackupFolder))

    $Result.Status | Should -Be 'Success'
    Get-BackupCommand -Database $Database | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Information'
    $Result.Notices[0].Message | Should -BeLike '*could not be read (The UNC path is not a drive.); the backup was attempted without the free-space check.'
  }

  It 'ends in error with a High notice and keeps every old file when the backup fails' {
    $Folder = New-BackupFolder -Name @('SUSDB_20200101.bak')

    $Result = Backup-Susdb -Context (New-BackupContext -Database (New-BackupDatabase -FailOn '^BACKUP') -Folder $Folder)

    $Result.Status | Should -Be 'Error'
    $Result.Message | Should -Be 'backup failed'
    $Result.Counts['Created'] | Should -Be 0
    $Result.Notices[0].Severity | Should -Be 'High'
    $Result.Notices[0].Message | Should -BeLike 'The SUSDB backup to *SUSDB_20261102.bak failed: *Operating system error 5*'
    Get-FileName -Folder $Folder | Should -Be @('SUSDB_20200101.bak')
  }

  It 'logs a warning when the size of the new file cannot be read' {
    $Result = Backup-Susdb -Context (New-BackupContext -Database (New-BackupDatabase -NoFile $True) -Folder (New-BackupFolder))

    $Result.Counts['Created'] | Should -Be 1
    $Result.Counts['SizeBytes'] | Should -Be 0
    (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'Warning\s+\[RUN\] Backup: The size of .+SUSDB_20261102\.bak could not be read: the file is not there'
  }

  It 'raises <Severity> notices for <Case>' -ForEach @(
    @{ Case = 'a retention that keeps everything'; Retention = @{ NoPolicy = $True; Errors = @() }; Severity = 'Information'; Status = 'Success'; Message = 'Backup retention is off (backup.minimumKept and backup.maximumAgeDays are both 0), so every backup file is kept.' }
    @{ Case = 'a file retention could not delete'; Retention = @{ NoPolicy = $False; Errors = @('SUSDB_20200101.bak could not be deleted: in use') }; Severity = 'Warning'; Status = 'Warning'; Message = 'Backup retention: SUSDB_20200101.bak could not be deleted: in use' }
  ) {
    $script:Retention = [PSCustomObject]@{ Deleted = [System.String[]]@(); FreedBytes = [System.Int64]0; Kept = 1; Errors = [System.String[]]$Retention.Errors; NoPolicy = $Retention.NoPolicy }
    Mock -CommandName Remove-BackupFile -MockWith { $script:Retention }

    $Result = Backup-Susdb -Context (New-BackupContext -Database (New-BackupDatabase) -Folder (New-BackupFolder))

    $Result.Status | Should -Be $Status
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be $Severity
    $Result.Notices[0].Message | Should -Be $Message
  }

  It 'writes nothing in a dry run and previews the retention' {
    $Folder = New-BackupFolder -Name @('SUSDB_20261101.bak', 'SUSDB_20200101.bak')
    $Database = New-BackupDatabase

    $Result = Backup-Susdb -Context (New-BackupContext -Database $Database -Folder $Folder -DryRun $True -Backup @{ minimumKept = 1 })

    Get-BackupCommand -Database $Database | Should -HaveCount 0
    $Result.Status | Should -Be 'Success'
    $Result.Counts['WouldCreate'] | Should -Be 1
    $Result.Counts['Created'] | Should -Be 0
    $Result.Items | Should -Be @('SUSDB_20200101.bak')
    $Result.Message | Should -Be ('Would back up SUSDB to {0} and delete 1 old backup file(s).' -f [System.IO.Path]::Combine($Folder, 'SUSDB_20261102.bak'))
    Get-FileName -Folder $Folder | Should -Be @('SUSDB_20200101.bak', 'SUSDB_20261101.bak')
  }
}

Describe 'Test-BackupGate' {
  BeforeAll {
    Function script:New-GateConfiguration {
      Param ([System.String]$Gate = 'Required')
      Get-FakeConfiguration -Json ('{ "schemaVersion": 1, "backup": { "destination": "H:\\B", "gate": "' + $Gate + '" } }')
    }

    Function script:New-GateServer {
      Param ($Database)
      [PSCustomObject]@{ Database = $Database; CommandTimeoutSeconds = 0; Environment = [PSCustomObject]@{ DatabaseName = 'SUSDB' } }
    }

    Function script:New-BackupOutcome {
      Param ($Counts)
      [PSCustomObject]@{ Name = 'Backup'; Counts = $Counts }
    }
  }

  It 'is satisfied without a query when it is off' {
    $Database = New-FakeSqlConnection

    $Gate = Test-BackupGate -Configuration (New-GateConfiguration -Gate 'Off') -Server (New-GateServer -Database $Database)

    $Gate.Satisfied | Should -BeTrue
    $Gate.Mode | Should -Be 'Off'
    $Gate.Detail | Should -Be 'gate off'
    $Database.Commands | Should -HaveCount 0
  }

  It 'is satisfied by a backup <Case>' -ForEach @(
    @{ Case = 'this run made'; Counts = [ordered]@{ Created = 1; WouldCreate = 0 } }
    @{ Case = 'a dry run would make'; Counts = [ordered]@{ Created = 0; WouldCreate = 1 } }
    @{ Case = 'reported with plain counts'; Counts = [PSCustomObject]@{ Created = 1 } }
  ) {
    $Database = New-FakeSqlConnection

    $Gate = Test-BackupGate -Configuration (New-GateConfiguration) -Outcome @(New-BackupOutcome -Counts $Counts) -Server (New-GateServer -Database $Database)

    $Gate.Satisfied | Should -BeTrue
    $Gate.Detail | Should -Be 'backup made by this run'
    $Database.Commands | Should -HaveCount 0
  }

  It 'is satisfied by a full backup recorded within the freshness window' {
    $Database = New-FakeSqlConnection -Rows @([PSCustomObject]@{ Fresh = 1; LastFinish = [System.DateTime]::new(2026, 11, 1, 23, 45, 0) })

    $Gate = Test-BackupGate -Configuration (New-GateConfiguration) -Outcome @(New-BackupOutcome -Counts ([ordered]@{ Created = 0; WouldCreate = 0 })) -Server (New-GateServer -Database $Database)

    $Gate.Satisfied | Should -BeTrue
    $Gate.Detail | Should -Be 'last full backup finished 2026-11-01 23:45'
    $Database.Commands[0].CommandText | Should -Match "FROM msdb\.dbo\.backupset WHERE database_name = @database AND type = 'D'"
    $Database.Commands[0].CommandText | Should -Match 'DATEADD\(HOUR, -@hours, GETDATE\(\)\)'
    $Database.Commands[0].Parameters.Values['@database'] | Should -Be 'SUSDB'
    $Database.Commands[0].Parameters.Values['@hours'] | Should -Be 24
  }

  It 'is not satisfied when <Case>' -ForEach @(
    @{ Case = 'the last backup is too old'; Connection = { New-FakeSqlConnection -Rows @([PSCustomObject]@{ Fresh = 0; LastFinish = [System.DateTime]::new(2026, 10, 1) }) }; Detail = 'no backup in this run and none recorded in the last 24 hour(s)' }
    @{ Case = 'no backup was ever recorded'; Connection = { New-FakeSqlConnection -Rows @([PSCustomObject]@{ Fresh = 0; LastFinish = $Null }) }; Detail = 'no backup in this run and none recorded in the last 24 hour(s)' }
    @{ Case = 'the history cannot be read'; Connection = { New-FakeSqlConnection -Failure 'The SELECT permission was denied on the object backupset.' }; Detail = 'no backup in this run, and the backup history could not be read: *permission was denied*' }
    @{ Case = 'there is no connection'; Connection = { $Null }; Detail = 'no backup in this run and none recorded in the last 24 hour(s)' }
  ) {
    $Gate = Test-BackupGate -Configuration (New-GateConfiguration -Gate 'Advisory') -Server (New-GateServer -Database (& $Connection))

    $Gate.Satisfied | Should -BeFalse
    $Gate.Mode | Should -Be 'Advisory'
    $Gate.Detail | Should -BeLike $Detail
  }
}

Describe 'SUSDB stage helpers' {
  It 'quotes identifiers for T-SQL' {
    ConvertTo-SqlIdentifier -Name 'SUSDB' | Should -Be '[SUSDB]'
    ConvertTo-SqlIdentifier -Name 'odd]name' | Should -Be '[odd]]name]'
  }

  It 'builds a stage result with empty defaults' {
    $Result = New-MaintenanceStageResult

    $Result.Status | Should -Be 'Success'
    $Result.Counts | Should -BeNullOrEmpty
    $Result.Items | Should -HaveCount 0
    $Result.Message | Should -Be ''
    $Result.Notices | Should -HaveCount 0
  }

  It 'reads the free space of the volume holding a folder' {
    Get-BackupDestinationSpace -Path $TestDrive | Should -BeGreaterThan 0
  }
}
