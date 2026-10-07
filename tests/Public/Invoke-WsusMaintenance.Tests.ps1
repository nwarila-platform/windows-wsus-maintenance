#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:CanValidate = $Null -ne (Get-Command -Name 'Test-Json' -ErrorAction SilentlyContinue)
}

Describe 'Invoke-WsusMaintenance' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration'
    $script:RunId = '20261102-020000-0a1b2c3d'

    Function script:New-FakeLock {
      $Lock = [PSCustomObject]@{ Released = 0; Disposed = 0 }
      $Lock | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value { $this.Released++ }
      $Lock | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }
      $Lock
    }

    # Every configured folder maps to its own folder under the test root, named after the
    #   configured text, so a test can find what the run wrote.
    Function script:Get-OutputFolder {
      Param ([System.String]$Configured)
      Join-Path -Path $script:Root -ChildPath ($Configured -replace '[^A-Za-z0-9]+', '_')
    }

    Function script:Get-Artifact {
      Param ([System.String]$Configured, [System.String]$Extension)
      Join-Path -Path (Get-OutputFolder -Configured $Configured) -ChildPath ('WsusMaintenance-{0}.{1}' -f $script:RunId, $Extension)
    }

    Function script:New-ConfigurationFile {
      Param ([System.String]$Json)
      $Path = Join-Path -Path $TestDrive -ChildPath ('{0}.json' -f [System.Guid]::NewGuid().ToString('N'))
      Set-Content -LiteralPath $Path -Value $Json
      $Path
    }

    $script:Reports = '%ProgramData%\NWarila\WsusMaintenance\Reports'
    $script:Logs = '%ProgramData%\NWarila\WsusMaintenance\Logs'
    $script:Summaries = '%ProgramData%\NWarila\WsusMaintenance\Summaries'
  }

  BeforeEach {
    $Script:MaintenanceSecret.Clear()
    $script:Lock = New-FakeLock
    $script:Root = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $script:Events = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Test-MaintenanceElevation -MockWith { $True }
    $script:UpdateServer = New-FakeUpdateServer
    $script:Database = New-FakeSqlConnection -Responder (New-UpkeepResponder)
    Mock -CommandName Get-MaintenanceIdentity -MockWith { 'NT AUTHORITY\SYSTEM' }
    Mock -CommandName Get-MaintenanceOperatingSystem -MockWith { [PSCustomObject]@{ Platform = 'Win32NT'; Major = 10; Build = 20348 } }
    Mock -CommandName Get-WsusSetupValue -MockWith { [PSCustomObject]@{ SqlServerName = [System.Environment]::MachineName; SqlDatabaseName = 'SUSDB'; TargetDir = 'C:\Program Files\Update Services\'; UsingSSL = 1 } }
    # A healthy server for the housekeeping and health stages: the WSUS site logs into a folder
    #   of the test drive, and the registry, certificate and computer look as they should.
    $script:IisLogs = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path (Join-Path -Path $script:IisLogs -ChildPath 'W3SVC1234567') -Force
    Mock -CommandName Get-IisConfiguration -MockWith { New-FakeIisConfiguration -LogDirectory $script:IisLogs }
    $script:Registry = New-FakeRegistry
    Mock -CommandName Get-MaintenanceRegistryKey -MockWith { $script:Registry[('{0}|{1}' -f $(If ($View) { $View } Else { 'Registry64' }), $Path)] }
    Mock -CommandName Get-MaintenanceCertificate -MockWith { [PSCustomObject]@{ Subject = 'CN=wsus01.example'; NotAfter = [System.DateTime]::UtcNow.AddDays(365); Thumbprint = $Thumbprint } }
    Mock -CommandName Get-MaintenanceMachineInfo -MockWith { [PSCustomObject]@{ Manufacturer = 'Example Hardware'; Model = 'Rack Server'; LogicalProcessors = 8 } }
    Mock -CommandName Get-WsusUpdateServer -MockWith { $script:UpdateServer }
    Mock -CommandName New-SqlConnection -MockWith { $script:Database }
    Mock -CommandName Wait-MaintenanceInterval -MockWith { }
    Mock -CommandName Get-BackupDestinationSpace -MockWith { [System.Int64]100GB }
    Mock -CommandName New-WsusAdministrationObject -MockWith { New-FakeWsusObject -TypeName $TypeName }
    Mock -CommandName New-MaintenanceLock -MockWith { $script:Lock }
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 2, 0, 0) }
    Mock -CommandName New-MaintenanceRunId -MockWith { $script:RunId }
    Mock -CommandName Resolve-MaintenancePath -MockWith { Get-OutputFolder -Configured $Path }
    Mock -CommandName Test-MaintenanceEventSource -MockWith { $True }
    Mock -CommandName Write-MaintenanceEventEntry -MockWith {
      $script:Events.Add([PSCustomObject]@{ EventId = $EventId; EntryType = $EntryType; Message = $Message })
    }
  }

  It 'validates a configuration without checking elevation, taking the lock or writing anything' {
    $Result = @(Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'full-valid.json') -ValidateOnly)

    $Result | Should -HaveCount 1
    $Result[0].PSTypeNames[0] | Should -Be 'WsusMaintenance.RunResult'
    $Result[0].Status | Should -Be 'Success'
    $Result[0].ExitCode | Should -Be 0
    $Result[0].Run | Should -BeNullOrEmpty
    $Result[0].Validation.IsValid | Should -BeTrue
    $Result[0].Validation.ValidateOnly | Should -BeTrue
    $Result[0].Validation.Configuration.staleComputers.action | Should -Be 'Move'
    Should -Invoke -CommandName Test-MaintenanceElevation -Times 0 -Exactly
    Should -Invoke -CommandName New-MaintenanceLock -Times 0 -Exactly
    Test-Path -LiteralPath $script:Root | Should -BeFalse
    $script:Events | Should -HaveCount 0
  }

  It 'stops a validation of an invalid configuration with ConfigurationInvalid and writes nothing' {
    { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'three-errors.json') -ValidateOnly } |
      Should -Throw -ErrorId 'ConfigurationInvalid,New-ErrorRecord'
    Test-Path -LiteralPath $script:Root | Should -BeFalse
  }

  It 'runs every enabled stage under the lock, writes its outputs and releases the lock' {
    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json')

    $Result.Status | Should -Be 'Success'
    $Result.ExitCode | Should -Be 0
    $Result.Stages | Should -HaveCount 18
    @($Result.Stages | Where-Object -FilterScript { $PSItem.Status -eq 'Success' }).Name | Should -Be @('Backup', 'CustomIndexes', 'DeleteUpdateFix', 'SupersededDecline', 'ExpiredDecline', 'ObsoleteUpdates', 'BuiltInCleanup', 'SyncHistory', 'StaleComputers', 'Reindex', 'IisLogRetention', 'ArtifactRetention', 'HealthChecks')
    @($Result.Stages | Where-Object -FilterScript { $PSItem.Reason -eq 'not available in this release' }) | Should -HaveCount 0
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'HealthChecks' }).Message | Should -Be 'Ran 7 health check(s): 0 finding(s), 0 check(s) could not run.'
    $script:UpdateServer.State.UpdateScopes | Should -HaveCount 1
    $script:UpdateServer.State.Cultures | Should -Be @('en', '')
    $script:UpdateServer.State.CleanupScopes | Should -HaveCount 5
    Test-Path -LiteralPath (Join-Path -Path (Get-OutputFolder -Configured 'H:\SUSDB') -ChildPath 'SUSDB_20261102.bak') | Should -BeTrue
    $Result.Run.RunId | Should -Be $script:RunId
    $Result.Run.Stages | Should -HaveCount 0
    $Result.Run.StartedAt | Should -Be ([System.DateTime]::new(2026, 11, 2, 2, 0, 0))
    $Result.Run.DurationSeconds | Should -Be 0
    $Result.Run.Deadline | Should -Be ([System.DateTime]::new(2026, 11, 2, 6, 0, 0))
    $Result.Run.Artifacts.Log | Should -Be (Get-Artifact -Configured $script:Logs -Extension 'log')
    $Result.Run.Artifacts.Reports | Should -Be @((Get-Artifact -Configured $script:Reports -Extension 'txt'), (Get-Artifact -Configured $script:Reports -Extension 'html'))
    $Result.Run.Artifacts.Summary | Should -Be (Get-Artifact -Configured $script:Summaries -Extension 'json')
    ForEach ($Path In @($Result.Run.Artifacts.Log, $Result.Run.Artifacts.Summary) + $Result.Run.Artifacts.Reports) {
      Test-Path -LiteralPath $Path | Should -BeTrue
    }
    $script:Events.EventId | Should -Be @(1000, 1001)
    $script:Events[0].Message | Should -Be ('Run {0} started: every enabled stage.' -f $script:RunId)
    $script:Lock.Released | Should -Be 1
    $script:Lock.Disposed | Should -Be 1
    Should -Invoke -CommandName New-MaintenanceLock -Times 1 -Exactly -ParameterFilter { $Name -eq 'Global\Invoke-WsusMaintenance' }
  }

  It 'writes the run header, the overrides and the effective configuration to the log' {
    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') -Verbosity 'Debug'
    $Log = Get-Content -LiteralPath $Result.Run.Artifacts.Log -Raw

    $Log | Should -Match ('Information \[{0}\] Run started: every enabled stage; dry run False; configuration .+minimal-valid\.json\.' -f $script:RunId)
    $Log | Should -Match 'Overrides: configuration path = .+ \(-ConfigPath\); log\.verbosity = Debug \(-Verbosity\)\.'
    $Log | Should -Match 'Effective configuration: \{"schemaVersion":1,'
    $Log | Should -Match 'Run finished with status Success \(exit code 0\)'
  }

  It 'reads the fixed default path when no path is given' {
    Mock -CommandName Get-MaintenanceDefaultConfigurationPath -MockWith {
      Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json'
    }

    $Result = Invoke-WsusMaintenance

    $Result.Validation.ConfigurationPath | Should -BeLike '*minimal-valid.json'
    $Result.Validation.ValidateOnly | Should -BeFalse
    Should -Invoke -CommandName Get-MaintenanceDefaultConfigurationPath -Times 1 -Exactly
  }

  It 'completes with warnings when unknown keys are only warned about' {
    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'misspelt-key-warning.json')

    $Result.Status | Should -Be 'Warning'
    $Result.ExitCode | Should -Be 2
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Validation.Warnings | Should -HaveCount 1
    $script:Events.EventId | Should -Be @(1000, 1002)
  }

  It 'applies command-line overrides and records them' {
    $Result = Invoke-WsusMaintenance `
      -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') `
      -DryRun `
      -ReportFolder 'D:\Reports' `
      -ReportFormat @('Text') `
      -Stage @('reindex')

    $Result.Run.DryRun | Should -BeTrue
    $Result.Run.Stages | Should -Be @('Reindex')
    $Result.Validation.Overrides | Should -Contain 'run.dryRun = true (-DryRun)'
    $Result.Validation.Overrides | Should -Contain 'stages = Reindex (-Stage)'
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'Reindex' }).Message | Should -Be 'Would defragment 0 index(es) and then update statistics.'
    @(Get-FakeCommandText -Connection $script:Database | Where-Object -FilterScript { $PSItem -match '^(?:ALTER|EXEC|DELETE|BACKUP|CREATE|DROP)' }) | Should -HaveCount 0
    $Result.Run.Artifacts.Reports | Should -Be @(Get-Artifact -Configured 'D:\Reports' -Extension 'txt')
    (Get-Content -LiteralPath $Result.Run.Artifacts.Reports[0] -Raw) | Should -Match 'Profile\s+: stage list: Reindex'
  }

  It 'writes a summary of the upkeep stages that validates against its schema' -Skip:(-not $script:CanValidate) {
    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json')

    $Schema = Join-Path -Path $PSScriptRoot -ChildPath '../../docs/reference/summary.schema.json'
    Test-Json -Json (Get-Content -LiteralPath $Result.Run.Artifacts.Summary -Raw) -SchemaFile $Schema | Should -BeTrue
  }

  It 'stages and approves needed updates, lists every action in the report and the summary, and repeats nothing' {
    $Updates = @(
      New-FakeUpdate -Title 'Needed update' -Kb @('5000101') -Needed 3 -Created ([System.DateTime]::new(2026, 10, 1)) -Local $True
      New-FakeUpdate -Title 'Young update' -Kb @('5000102') -Needed 2 -Created ([System.DateTime]::new(2026, 11, 1))
    )
    $script:UpdateServer = New-FakeUpdateServer -Updates $Updates -Groups @('Pilot', 'Content Staging')
    $Path = New-ConfigurationFile -Json '{ "schemaVersion": 1, "backup": { "destination": "H:\\SUSDB" }, "approval": { "enabled": true, "groups": [ { "name": "Pilot", "delayDays": 7, "deadlineDays": 2 } ], "staging": { "groupName": "Content Staging" } } }'

    $Result = Invoke-WsusMaintenance -ConfigPath $Path
    $Summary = Get-Content -LiteralPath $Result.Run.Artifacts.Summary -Raw | ConvertFrom-Json
    $Report = Get-Content -LiteralPath ($Result.Run.Artifacts.Reports | Where-Object -FilterScript { $PSItem -like '*.txt' }) -Raw
    $Again = Invoke-WsusMaintenance -ConfigPath $Path

    $Result.Status | Should -Be 'Success'
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'ContentStaging' }).Counts['Staged'] | Should -Be 2
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'DeferredApproval' }).Counts['Approved'] | Should -Be 1
    $Approval = @(($Summary.stages | Where-Object -FilterScript { $PSItem.name -eq 'DeferredApproval' }).items)
    $Approval | Should -HaveCount 1
    $Approval[0] | Should -BeLike 'approved for Pilot after 7 day(s), deadline * UTC, content local: Needed update (KB5000101, *)'
    @(($Summary.stages | Where-Object -FilterScript { $PSItem.name -eq 'ContentStaging' }).items) | Should -HaveCount 2
    $Report | Should -Match 'approved for Pilot after 7 day\(s\)'
    ($Again.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'DeferredApproval' }).Counts['Approved'] | Should -Be 0
    ($Again.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'ContentStaging' }).Counts['Staged'] | Should -Be 0
    $script:UpdateServer.State.Approvals | Should -HaveCount 2
  }

  It 'sends SUSDB and WSUS nothing but reads in a dry run of every stage' {
    $Fleet = @(For ($Index = 1; $Index -le 20; $Index++) { New-FakeComputer -Name ('pc{0:D2}.example' -f $Index) -LastSync ([System.DateTime]::UtcNow) })
    $Updates = @(
      New-FakeUpdate -Title 'Old superseded' -Superseded $True -Created ([System.DateTime]::UtcNow.AddDays(-400))
      New-FakeUpdate -Title 'Expired' -Expired $True
    )
    $script:UpdateServer = New-FakeUpdateServer -Computers @($Fleet + @(New-FakeComputer -Name 'old.example' -LastSync ([System.DateTime]::MinValue))) -Updates $Updates

    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') -DryRun

    $Result.Status | Should -Be 'Success'
    $Commands = @(Get-FakeCommandText -Connection $script:Database)
    $Commands | Should -Not -HaveCount 0
    ForEach ($Text In $Commands) {
      $Text | Should -Match '^(?:SELECT\b|WITH Fragmented AS \(|EXEC dbo\.spGetObsoleteUpdatesToCleanup$)' -Because 'a dry run only reads'
      $Text | Should -Not -Match '(?im)^\s*(?:DELETE|INSERT|UPDATE|MERGE|ALTER|CREATE|DROP|BACKUP|TRUNCATE)\b' -Because 'a dry run only reads'
    }
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'Backup' }).Counts.WouldCreate | Should -Be 1
    $script:UpdateServer.State.CleanupScopes | Should -HaveCount 0
    $script:UpdateServer.State.Deleted | Should -HaveCount 0
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'StaleComputers' }).Message | Should -BeLike 'Simulation: would delete 1 computer(s)*'
    $script:UpdateServer.State.DeclinedUpdates | Should -HaveCount 0
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'SupersededDecline' }).Message | Should -BeLike 'pending: 1 superseded update(s)*'
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'ExpiredDecline' }).Message | Should -BeLike 'pending: 1 expired update(s)*'
    Test-Path -LiteralPath (Get-OutputFolder -Configured 'H:\SUSDB') | Should -BeFalse
  }

  It 'runs only the custom-index stage and drops the indexes it created for -RemoveCustomIndexes' {
    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') -RemoveCustomIndexes

    $Result.Status | Should -Be 'Success'
    $Result.Run.Stages | Should -Be @('CustomIndexes')
    $Result.Validation.Overrides | Should -Contain 'custom indexes = remove the ones this script created (-RemoveCustomIndexes)'
    ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'CustomIndexes' }).Message | Should -Be 'Created 0 and removed 2 index(es); 0 already present; 0 failed.'
    @(Get-FakeCommandText -Connection $script:Database | Where-Object -FilterScript { $PSItem -like 'DROP INDEX*' }) | Should -Be @(
      'DROP INDEX [nclLocalizedPropertyID] ON [dbo].[tbLocalizedPropertyForRevision]'
      'DROP INDEX [nclSupercededUpdateID] ON [dbo].[tbRevisionSupersedesUpdate]'
    )
  }

  It 'saves a report to the default folder, with a warning, when the report folder cannot be used' {
    $Blocked = Get-OutputFolder -Configured 'R:\Blocked'
    $Null = New-Item -ItemType Directory -Path $script:Root -Force
    Set-Content -LiteralPath $Blocked -Value 'a file, not a folder'

    $Result = Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') -ReportFolder 'R:\Blocked'

    $Result.Status | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -BeLike "The report folder '*' cannot be used (*); the report is saved to the default folder '*' instead."
    $Result.Run.Artifacts.Reports[0] | Should -Be (Get-Artifact -Configured $script:Reports -Extension 'txt')
  }

  Context 'discovery and preconditions' {
    BeforeAll {
      Function script:Invoke-Minimal {
        Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json')
      }

      Function script:Get-ReportText {
        Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw
      }
    }

    It 'fills the report header with what discovery found and closes the database connection' {
      $Result = Invoke-Minimal

      $Report = Get-ReportText
      $Report | Should -Match 'WSUS version\s+: 10\.0\.20348\.2700'
      $Report | Should -Match 'Server role\s+: Top-tier server'
      $Report | Should -Match 'Upstream source\s+: Microsoft Update'
      $Report | Should -Match ('Database\s+: SQL Server on this server, instance {0}, database SUSDB \(from WSUS setup\)' -f [System.Text.RegularExpressions.Regex]::Escape([System.Environment]::MachineName))
      $Report | Should -Match 'WSUS endpoint\s+: wsus01\.example, port 8531, TLS'
      $Report | Should -Match 'Run identity\s+: NT AUTHORITY\\SYSTEM'
      $Report | Should -Match 'Database permissions\s+: login NT AUTHORITY\\SYSTEM, database owner; every stage has the permissions it needs'
      $Report | Should -Match 'Synchronization\s+: not running'
      $Report | Should -Match 'WSUS connection: WSUS administration interface at 02:00:00; SUSDB at 02:00:00'
      $Result.Status | Should -Be 'Success'
      $script:Database.Disposed | Should -Be 1
      $script:Lock.Disposed | Should -Be 1
    }

    It 'skips every decline stage on a replica with the replica reason' {
      $script:UpdateServer = New-FakeUpdateServer -IsReplica $True -SyncFromMicrosoftUpdate $False

      $Result = Invoke-Minimal

      @($Result.Stages | Where-Object -FilterScript { $PSItem.Reason -eq 'skipped: replica' }).Name | Should -Be @('SupersededDecline', 'ExpiredDecline')
      Get-ReportText | Should -Match 'Server role\s+: Replica downstream server'
    }

    It 'warns and skips the decline stages when the server role cannot be determined' {
      $script:UpdateServer = New-FakeUpdateServer -ConfigurationFails $True

      $Result = Invoke-Minimal

      $Result.Status | Should -Be 'Warning'
      $Result.Notices[0].Message | Should -Be 'The server role could not be determined (The configuration could not be read.); every action that declines updates or changes approvals or computer groups is skipped.'
      @($Result.Stages | Where-Object -FilterScript { $PSItem.Reason -eq 'skipped: server role unknown' }) | Should -HaveCount 2
    }

    It 'skips the backup with a notice before any other work when the backup right is missing' {
      $script:Database = New-FakeSqlConnection -Responder (New-UpkeepResponder -Permission (New-PermissionRow -CanBackup 0))

      $Result = Invoke-Minimal

      ($Result.Stages | Where-Object -FilterScript { $PSItem.Name -eq 'Backup' }).Reason | Should -Be 'skipped: missing permission: BACKUP DATABASE'
      $Result.Notices[0].Message | Should -Be 'Stage Backup is skipped because the run identity lacks BACKUP DATABASE in SUSDB.'
      $Lines = @(Get-Content -LiteralPath $Result.Run.Artifacts.Log)
      $Warning = [System.Array]::IndexOf($Lines, @($Lines | Where-Object -FilterScript { $PSItem -like '*Stage Backup is skipped because*' })[0])
      $FirstStage = [System.Array]::IndexOf($Lines, @($Lines | Where-Object -FilterScript { $PSItem -like '*Backup: Stage skipped*' })[0])
      $Warning | Should -BeLessThan $FirstStage
    }

    It 'warns when the database permissions cannot be checked' {
      $script:Database = New-FakeSqlConnection -Responder (New-UpkeepResponder -PermissionFailure 'VIEW SERVER STATE permission was denied.')

      $Result = Invoke-Minimal

      $Result.Notices[0].Message | Should -Be 'Database permissions could not be checked (The database command failed after 0.0 s: VIEW SERVER STATE permission was denied.); each stage reports its own failure.'
      $Result.ExitCode | Should -Be 2
    }

    It 'stops with PreconditionFailed and a failure report for <Case>' -ForEach @(
      @{ Case = 'Windows Internal Database'; Setup = @{ SqlServerName = 'MICROSOFT##WID'; SqlDatabaseName = 'SUSDB' }; Build = 20348; Text = 'Windows Internal Database' }
      @{ Case = 'a remote SQL Server'; Setup = @{ SqlServerName = 'SQL01\WSUS'; SqlDatabaseName = 'SUSDB' }; Build = 20348; Text = "remote SQL Server 'SQL01\\WSUS'" }
      @{ Case = 'Windows Server 2016'; Setup = @{ SqlServerName = 'LOCAL'; SqlDatabaseName = 'SUSDB' }; Build = 14393; Text = 'Windows Server 2016 \(build 14393\) is not supported' }
      @{ Case = 'a server without WSUS'; Setup = $Null; Build = 20348; Text = 'WSUS is not installed on this server' }
    ) {
      $script:CaseSetup = $Setup
      $script:CaseBuild = $Build
      Mock -CommandName Get-WsusSetupValue -MockWith {
        If ($Null -eq $script:CaseSetup) { $Null } Else {
          $Values = $script:CaseSetup.Clone()
          If ($Values.SqlServerName -eq 'LOCAL') { $Values.SqlServerName = [System.Environment]::MachineName }
          [PSCustomObject]$Values
        }
      }
      Mock -CommandName Get-MaintenanceOperatingSystem -MockWith { [PSCustomObject]@{ Platform = 'Win32NT'; Major = 10; Build = $script:CaseBuild } }

      { Invoke-Minimal } | Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage 'This server is not a combination this release supports:*'

      Should -Invoke -CommandName Get-WsusUpdateServer -Times 0 -Exactly
      $Report = Get-ReportText
      $Report | Should -Match 'Point reached : environment discovery'
      $Report | Should -Match $Text
      $Report | Should -Match 'Run status: Error \(exit code 3\)'
      $script:Events.EventId | Should -Be @(1200)
      $script:Lock.Disposed | Should -Be 1
    }

    It 'stops with PreconditionFailed and a failure report when the WSUS administration interface cannot be reached' {
      Mock -CommandName Get-WsusUpdateServer -MockWith { Throw 'Unable to connect to the remote server.' }

      { Invoke-Minimal } | Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage 'The WSUS administration interface could not be reached: Unable to connect to the remote server.'

      Get-ReportText | Should -Match 'Point reached : connection to the WSUS administration interface'
      Should -Invoke -CommandName New-SqlConnection -Times 0 -Exactly
    }

    It 'stops with PreconditionFailed and a failure report when SUSDB cannot be opened' {
      Mock -CommandName New-SqlConnection -MockWith { Throw 'A network-related error occurred.' }

      { Invoke-Minimal } | Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage "SUSDB could not be opened on '*' (database SUSDB): A network-related error occurred."

      $Report = Get-ReportText
      $Report | Should -Match 'Point reached : connection to SUSDB'
      $Report | Should -Match 'WSUS connection: WSUS administration interface at 02:00:00; SUSDB not connected'
    }

    It 'stops a running synchronization before the first stage and restarts it after the last (REQ-044 a)' {
      $script:UpdateServer = New-FakeUpdateServer -Statuses @('Running', 'NotProcessing')

      $Result = Invoke-Minimal

      $Result.Status | Should -Be 'Success'
      $script:UpdateServer.State.StopCalls | Should -Be 1
      $script:UpdateServer.State.StartCalls | Should -Be 1
      Get-ReportText | Should -Match 'Synchronization\s+: running at start; stopped by the run \(attempt 1\); restarted after the run'
      $Log = Get-Content -LiteralPath $Result.Run.Artifacts.Log -Raw
      $Log.IndexOf('stop requested') | Should -BeLessThan $Log.IndexOf('Backup: Stage')
      $Log.IndexOf('Synchronization restarted.') | Should -BeGreaterThan $Log.IndexOf('HealthChecks: Stage')
    }

    It 'runs no stage and stops with PreconditionFailed when the synchronization never stops (REQ-044 b)' {
      $script:UpdateServer = New-FakeUpdateServer -Statuses @('Running')
      Mock -CommandName Invoke-MaintenanceRun -MockWith { Throw 'Must not run.' }

      { Invoke-Minimal } | Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage 'The synchronization guard could not make sure that no synchronization runs: Running at start; still Running after 3 attempt(s).'

      Should -Invoke -CommandName Invoke-MaintenanceRun -Times 0 -Exactly
      $Report = Get-ReportText
      $Report | Should -Match 'Point reached : synchronization guard'
      $Report | Should -Match 'Synchronization\s+: Running at start; still Running after 3 attempt\(s\); not restarted: status Running'
      $script:Database.Disposed | Should -Be 1
      $script:Lock.Disposed | Should -Be 1
    }

    It 'restarts the synchronization it stopped even when the run fails unexpectedly' {
      $script:UpdateServer = New-FakeUpdateServer -Statuses @('Running', 'NotProcessing')
      Mock -CommandName Invoke-MaintenanceRun -MockWith { Throw 'Unexpected failure.' }

      { Invoke-Minimal } | Should -Throw -ExpectedMessage 'Unexpected failure.'

      $script:UpdateServer.State.StartCalls | Should -Be 1
      $script:Database.Disposed | Should -Be 1
    }
  }

  Context 'preconditions' {
    It 'stops with PreconditionFailed and a failure report when the run is not elevated' {
      Mock -CommandName Test-MaintenanceElevation -MockWith { $False }

      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') } |
        Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage 'The run must be elevated or run as LocalSystem; nothing was changed.'

      Should -Invoke -CommandName New-MaintenanceLock -Times 0 -Exactly
      $Report = Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw
      $Report | Should -Match 'Point reached : elevation check'
      $Report | Should -Match 'What to do    : Run the scheduled task as SYSTEM'
      $Report | Should -Match 'Run status: Error \(exit code 3\)'
      (Get-Content -LiteralPath (Get-Artifact -Configured $script:Summaries -Extension 'json') -Raw | ConvertFrom-Json).failure.kind | Should -Be 'PreconditionFailed'
      $script:Events.EventId | Should -Be @(1200)
    }

    It 'stops with PreconditionFailed when elevation cannot be determined' {
      Mock -CommandName Test-MaintenanceElevation -MockWith { Throw 'Windows identities are not available on this platform.' }

      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') } |
        Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage '*nothing was changed. Windows identities are not available*'
      Test-Path -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') | Should -BeTrue
    }

    It 'stops with LockHeld, logs it and runs nothing while another run holds the lock' {
      Mock -CommandName New-MaintenanceLock -MockWith { $Null }
      Mock -CommandName Invoke-MaintenanceRun -MockWith { Throw 'Must not run.' }

      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') } |
        Should -Throw -ErrorId 'LockHeld,New-ErrorRecord'

      Should -Invoke -CommandName Invoke-MaintenanceRun -Times 0 -Exactly
      (Get-Content -LiteralPath (Get-Artifact -Configured $script:Logs -Extension 'log') -Raw) | Should -Match 'Another run holds the lock; this run stops without changing anything\.'
      Test-Path -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') | Should -BeFalse
      $script:Events | Should -HaveCount 0
    }

    It 'stops with PreconditionFailed and a failure report when the lock cannot be created' {
      Mock -CommandName New-MaintenanceLock -MockWith { Throw 'Access to the named object is denied.' }

      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') } |
        Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord'

      (Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw) | Should -Match 'Point reached : taking of the run lock'
      $script:Events.EventId | Should -Be @(1200)
    }

    It 'aborts with PreconditionFailed, an event and a failure report when the log folder cannot be written' {
      $Null = New-Item -ItemType Directory -Path $script:Root -Force
      Set-Content -LiteralPath (Get-OutputFolder -Configured 'L:\Logs') -Value 'a file, not a folder'
      $Path = New-ConfigurationFile -Json '{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }, "log": { "folder": "L:\\Logs" } }'

      { Invoke-WsusMaintenance -ConfigPath $Path } | Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage "The log folder '*' cannot be written: *"

      Should -Invoke -CommandName Test-MaintenanceElevation -Times 0 -Exactly
      $script:Events.EventId | Should -Be @(1200)
      $script:Events[0].Message | Should -BeLike '*stopped at opening of the run log with exit code 3*'
      $Report = Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw
      $Report | Should -Match 'Run log\s+: not written'
      $Report | Should -Match 'What to do    : Point log\.folder at a folder'
    }

    It 'stops with ConfigurationInvalid, lists every problem and saves a failure report' {
      $Caught = $Null

      Try {
        Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'three-errors.json') -Stage 'NoSuchStage'
      } Catch {
        $Caught = $PSItem
      }

      $Caught | Should -Not -BeNullOrEmpty
      $Caught.FullyQualifiedErrorId | Should -Be 'ConfigurationInvalid,New-ErrorRecord'
      $Caught.Exception.Message | Should -BeLike '*is invalid (4 problem(s))*'
      $Caught.TargetObject.IsValid | Should -BeFalse
      $Caught.TargetObject.Errors | Should -HaveCount 4
      $Caught.TargetObject.Errors[-1] | Should -BeLike "-Stage: 'NoSuchStage' is not a stage name*"
      Should -Invoke -CommandName New-MaintenanceLock -Times 0 -Exactly
      Should -Invoke -CommandName Test-MaintenanceElevation -Times 0 -Exactly
      $Report = Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw
      $Report | Should -Match 'NOTICES \(4; HIGHEST: ERROR\)'
      $Report | Should -Match 'run\.connectionTimeoutSeconds: must be from 1 to 600 \(got 601\)\.'
      $Report | Should -Match 'Point reached : configuration validation'
      $Report | Should -Match 'Run status: Error \(exit code 4\)'
      $script:Events.EventId | Should -Be @(1300)
    }

    It 'stops with ConfigurationInvalid when the document is missing, reporting to the built-in default folder' {
      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'absent.json') } |
        Should -Throw -ErrorId 'ConfigurationInvalid,New-ErrorRecord' -ExpectedMessage "*Configuration document '*absent.json' does not exist.*"
      (Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw) | Should -Match 'does not exist'
    }

    It 'writes the failure report of a broken document to the built-in default folder' {
      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'not-json.json') } |
        Should -Throw -ErrorId 'ConfigurationInvalid,New-ErrorRecord'

      (Get-Content -LiteralPath (Get-Artifact -Configured $script:Reports -Extension 'txt') -Raw) | Should -Match 'is not valid JSON'
      Test-Path -LiteralPath (Get-Artifact -Configured $script:Summaries -Extension 'json') | Should -BeTrue
      Test-Path -LiteralPath (Get-Artifact -Configured $script:Logs -Extension 'log') | Should -BeTrue
    }

    It 'still uses a valid report folder of an invalid document' {
      $Path = New-ConfigurationFile -Json '{ "schemaVersion": 1, "report": { "folder": "E:\\Reports" }, "backup": { "minimumKept": -1 } }'

      { Invoke-WsusMaintenance -ConfigPath $Path } | Should -Throw -ErrorId 'ConfigurationInvalid,New-ErrorRecord'

      Test-Path -LiteralPath (Get-Artifact -Configured 'E:\Reports' -Extension 'txt') | Should -BeTrue
    }

    It 'rethrows a failure to read the document that is not a configuration error' {
      Mock -CommandName Read-MaintenanceConfiguration -MockWith { Throw 'Unexpected reader failure.' }

      { Invoke-WsusMaintenance -ConfigPath 'C:\m.json' } | Should -Throw -ExpectedMessage 'Unexpected reader failure.'
    }

    It 'releases the lock when the run fails unexpectedly' {
      Mock -CommandName Invoke-MaintenanceRun -MockWith { Throw 'Unexpected failure.' }

      { Invoke-WsusMaintenance -ConfigPath (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json') } |
        Should -Throw -ExpectedMessage 'Unexpected failure.'
      $script:Lock.Disposed | Should -Be 1
    }
  }
}
