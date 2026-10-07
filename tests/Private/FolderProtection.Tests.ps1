#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
  . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

  # Access rights as FileSystemRights values: full control, read and execute, the write rights
  #   standard users hold on a folder that inherits from ProgramData, and two generic rights.
  $script:FullControl = 0x1F01FF
  $script:ReadExecute = 0x1200A9
  $script:UsersWrite = 0x116
  $script:GenericWrite = 0x40000000
  $script:GenericReadExecute = [System.Int32]-1610612736
  $script:RunSid = 'S-1-5-21-1000-2000-3000-1001'
  $script:Names = @{
    'S-1-5-18'                                                       = 'NT AUTHORITY\SYSTEM'
    'S-1-5-32-544'                                                   = 'BUILTIN\Administrators'
    'S-1-5-32-545'                                                   = 'BUILTIN\Users'
    'S-1-5-11'                                                       = 'NT AUTHORITY\Authenticated Users'
    'S-1-3-0'                                                        = 'CREATOR OWNER'
    'S-1-3-4'                                                        = 'OWNER RIGHTS'
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' = 'NT SERVICE\TrustedInstaller'
    'S-1-5-21-1000-2000-3000-1001'                                   = 'EXAMPLE\maint'
    'S-1-5-21-1000-2000-3000-1002'                                   = 'EXAMPLE\someone'
  }

  Function script:New-Rule {
    Param ([System.String]$Sid, [System.Int32]$Rights, [System.Boolean]$Allow = $True)
    [PSCustomObject]@{ Sid = $Sid; Name = $script:Names[$Sid]; Rights = $Rights; Allow = $Allow }
  }

  Function script:New-Access {
    Param ([System.String]$Owner = 'S-1-5-32-544', [System.Object[]]$Rules = @())
    [PSCustomObject]@{ OwnerSid = $Owner; OwnerName = $script:Names[$Owner]; Rules = [PSCustomObject[]]@($Rules) }
  }

  # The access control lists of the stand-in file system, by path. A folder created through the
  #   protection seam is protected: full control for exactly the identities it was given.
  Function script:Use-FakeAcl {
    $script:Acl = @{}
    $script:Created = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Test-MaintenanceAclSupport -MockWith { $True }
    Mock -CommandName Get-MaintenanceIdentitySid -MockWith { $script:RunSid }
    Mock -CommandName Get-MaintenancePathAccess -MockWith { $script:Acl[$Path] }
    Mock -CommandName New-MaintenanceProtectedFolder -MockWith {
      $Null = [System.IO.Directory]::CreateDirectory($Path)
      $script:Created.Add([PSCustomObject]@{ Path = $Path; Identity = [System.String[]]$Identity })
      $script:Acl[$Path] = New-Access -Owner 'S-1-5-32-544' -Rules @($Identity | Where-Object -FilterScript { $PSItem -like 'S-1-*' } | ForEach-Object -Process { New-Rule -Sid $PSItem -Rights $script:FullControl })
    }
  }

  # A folder as an inherited ProgramData folder leaves it: standard users may add files to it.
  Function script:New-PermissiveFolder {
    Param ([System.String]$Path)
    $Null = New-Item -ItemType Directory -Path $Path -Force
    $script:Acl[$Path] = New-Access -Rules @(
      New-Rule -Sid 'S-1-5-18' -Rights $script:FullControl
      New-Rule -Sid 'S-1-5-32-544' -Rights $script:FullControl
      New-Rule -Sid 'S-1-5-32-545' -Rights $script:ReadExecute
      New-Rule -Sid 'S-1-5-32-545' -Rights $script:UsersWrite
      New-Rule -Sid 'S-1-3-0' -Rights $script:FullControl
    )
  }

  Function script:New-ProtectedFolder {
    Param ([System.String]$Path)
    $Null = New-Item -ItemType Directory -Path $Path -Force
    $script:Acl[$Path] = New-Access -Owner 'S-1-5-18' -Rules @(
      New-Rule -Sid 'S-1-5-18' -Rights $script:FullControl
      New-Rule -Sid 'S-1-5-32-544' -Rights $script:FullControl
    )
  }
}

Describe 'Test-MaintenancePathProtection' {
  BeforeEach {
    Use-FakeAcl
    $script:Trusted = [System.String[]]@('S-1-5-18', 'S-1-5-32-544', $script:RunSid)
  }

  It 'trusts SYSTEM, Administrators, the run identity, service identities, CREATOR OWNER and OWNER RIGHTS' {
    $script:Acl['F'] = New-Access -Owner $script:RunSid -Rules @(
      New-Rule -Sid 'S-1-5-18' -Rights $script:FullControl
      New-Rule -Sid 'S-1-5-32-544' -Rights $script:GenericWrite
      New-Rule -Sid $script:RunSid -Rights $script:FullControl
      New-Rule -Sid 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' -Rights $script:FullControl
      New-Rule -Sid 'S-1-3-0' -Rights $script:FullControl
      New-Rule -Sid 'S-1-3-4' -Rights $script:FullControl
    )

    $Check = Test-MaintenancePathProtection -Path 'F' -TrustedSid $script:Trusted

    $Check.Exists | Should -BeTrue
    $Check.Permissive | Should -BeFalse
    $Check.Writers | Should -HaveCount 0
  }

  It 'ignores rules that only read, generic read included, and rules that deny' {
    $script:Acl['F'] = New-Access -Rules @(
      New-Rule -Sid 'S-1-5-32-545' -Rights $script:ReadExecute
      New-Rule -Sid 'S-1-5-11' -Rights $script:GenericReadExecute
      New-Rule -Sid 'S-1-5-32-545' -Rights $script:FullControl -Allow $False
    )

    (Test-MaintenancePathProtection -Path 'F' -TrustedSid $script:Trusted).Permissive | Should -BeFalse
  }

  It 'names each principal outside the trusted set that can change the folder once, and an untrusted owner' {
    $script:Acl['F'] = New-Access -Owner 'S-1-5-21-1000-2000-3000-1002' -Rules @(
      New-Rule -Sid 'S-1-5-32-545' -Rights 0x2
      New-Rule -Sid 'S-1-5-32-545' -Rights 0x4
      New-Rule -Sid 'S-1-5-11' -Rights $script:GenericWrite
    )

    $Check = Test-MaintenancePathProtection -Path 'F' -TrustedSid $script:Trusted

    $Check.Permissive | Should -BeTrue
    $Check.Writers | Should -Be @('EXAMPLE\someone (owner)', 'BUILTIN\Users', 'NT AUTHORITY\Authenticated Users')
  }

  It 'counts every right that changes the folder or its contents: <Right>' -ForEach @(
    @{ Right = 'append data'; Value = 0x4 }
    @{ Right = 'write extended attributes'; Value = 0x10 }
    @{ Right = 'delete child items'; Value = 0x40 }
    @{ Right = 'write attributes'; Value = 0x100 }
    @{ Right = 'delete'; Value = 0x10000 }
    @{ Right = 'change permissions'; Value = 0x40000 }
    @{ Right = 'take ownership'; Value = 0x80000 }
    @{ Right = 'generic all'; Value = 0x10000000 }
  ) {
    $script:Acl['F'] = New-Access -Rules @(New-Rule -Sid 'S-1-5-32-545' -Rights $Value)

    (Test-MaintenancePathProtection -Path 'F' -TrustedSid $script:Trusted).Writers | Should -Be @('BUILTIN\Users')
  }

  It 'finds no writers for a path that does not exist' {
    $Check = Test-MaintenancePathProtection -Path 'missing' -TrustedSid $script:Trusted

    $Check.Exists | Should -BeFalse
    $Check.Permissive | Should -BeFalse
  }
}

Describe 'Get-MaintenanceTrustedSid' {
  It 'lists SYSTEM, Administrators and the run identity, once each' {
    Mock -CommandName Get-MaintenanceIdentitySid -MockWith { 'S-1-5-21-1000-2000-3000-1001' }
    Get-MaintenanceTrustedSid | Should -Be @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-21-1000-2000-3000-1001')

    Mock -CommandName Get-MaintenanceIdentitySid -MockWith { 'S-1-5-18' }
    Get-MaintenanceTrustedSid | Should -Be @('S-1-5-18', 'S-1-5-32-544')
  }
}

Describe 'Initialize-MaintenanceFolder with -Protect' {
  BeforeEach {
    Use-FakeAcl
    $script:Base = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path $script:Base
  }

  It 'creates every missing level protected for SYSTEM, Administrators, the run identity and the granted identities' {
    $Path = Join-Path -Path $script:Base -ChildPath 'one/two'

    $Ready = Initialize-MaintenanceFolder -Path $Path -Protect -Grant @('NT SERVICE\MSSQLSERVER')

    $Ready.Error | Should -BeNullOrEmpty
    $Ready.Warning | Should -BeNullOrEmpty
    $script:Created.Path | Should -Be @((Join-Path -Path $script:Base -ChildPath 'one'), $Path)
    $script:Created[0].Identity | Should -Be @('S-1-5-18', 'S-1-5-32-544', $script:RunSid, 'NT SERVICE\MSSQLSERVER')
    @(Get-ChildItem -LiteralPath $Path -Force) | Should -HaveCount 0
  }

  It 'uses an existing protected folder without changing it' {
    $Path = Join-Path -Path $script:Base -ChildPath 'protected'
    New-ProtectedFolder -Path $Path

    $Ready = Initialize-MaintenanceFolder -Path $Path -Protect

    $Ready.Error | Should -BeNullOrEmpty
    $script:Created | Should -HaveCount 0
  }

  It 'refuses an existing folder that standard users can change, without writing to it or changing it' {
    $Path = Join-Path -Path $script:Base -ChildPath 'open'
    New-PermissiveFolder -Path $Path
    # Writing and deleting a probe file would change the folder's last write time.
    $Stamp = [System.DateTime]::new(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    [System.IO.Directory]::SetLastWriteTimeUtc($Path, $Stamp)

    $Ready = Initialize-MaintenanceFolder -Path $Path -Protect

    $Ready.Permissive | Should -BeTrue
    $Ready.Error | Should -Be 'it can be changed by BUILTIN\Users, not only by SYSTEM, Administrators and the run identity, so the run does not use it'
    $script:Created | Should -HaveCount 0
    [System.IO.Directory]::GetLastWriteTimeUtc($Path) | Should -Be $Stamp
    $script:Acl[$Path].Rules | Should -HaveCount 5
  }

  It 'uses such a folder with a warning when the override allows it' {
    $Path = Join-Path -Path $script:Base -ChildPath 'open'
    New-PermissiveFolder -Path $Path

    $Ready = Initialize-MaintenanceFolder -Path $Path -Protect -AllowPermissive

    $Ready.Error | Should -BeNullOrEmpty
    $Ready.Permissive | Should -BeFalse
    $Ready.Warning | Should -Be ("The folder '{0}' can be changed by BUILTIN\Users, not only by SYSTEM, Administrators and the run identity; it is used because run.permissiveFolderOverride is set." -f $Path)
  }

  It 'reports a folder it created whose access control list does not verify' {
    Mock -CommandName New-MaintenanceProtectedFolder -MockWith {
      $Null = [System.IO.Directory]::CreateDirectory($Path)
      $script:Acl[$Path] = New-Access -Rules @(New-Rule -Sid 'S-1-5-32-545' -Rights $script:FullControl)
    }

    $Ready = Initialize-MaintenanceFolder -Path (Join-Path -Path $script:Base -ChildPath 'new') -Protect -AllowPermissive

    $Ready.Error | Should -Be 'the folder was created, but its access control list does not match the protected form: BUILTIN\Users can change it'
    $Ready.Permissive | Should -BeFalse
  }

  It 'reports a folder it cannot create protected' {
    Mock -CommandName New-MaintenanceProtectedFolder -MockWith { Throw 'Some or all identity references could not be translated.' }

    $Ready = Initialize-MaintenanceFolder -Path (Join-Path -Path $script:Base -ChildPath 'new') -Protect -Grant @('NT SERVICE\MSSQL$MISSING')

    $Ready.Error | Should -Be 'Some or all identity references could not be translated.'
  }

  It 'does not look at access control without -Protect or where the host has none' {
    $Path = Join-Path -Path $script:Base -ChildPath 'open'
    New-PermissiveFolder -Path $Path

    (Initialize-MaintenanceFolder -Path $Path).Error | Should -BeNullOrEmpty
    Mock -CommandName Test-MaintenanceAclSupport -MockWith { $False }
    (Initialize-MaintenanceFolder -Path $Path -Protect).Error | Should -BeNullOrEmpty

    Should -Invoke -CommandName Get-MaintenancePathAccess -Times 0 -Exactly
  }
}

Describe 'Output folders under protection' {
  BeforeEach {
    Use-FakeAcl
    $script:Base = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $Null = New-Item -ItemType Directory -Path $script:Base
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 2, 0, 0) }
    Mock -CommandName Test-MaintenanceEventSource -MockWith { $True }
    Mock -CommandName Write-MaintenanceEventEntry -MockWith { }

    Function script:New-Setting {
      Param ([System.Boolean]$Override = $False)
      $Setting = Get-MaintenanceOutputSetting
      $Setting.ReportFolder = Join-Path -Path $script:Base -ChildPath 'Reports'
      $Setting.DefaultReportFolder = Join-Path -Path $script:Base -ChildPath 'DefaultReports'
      $Setting.LogFolder = Join-Path -Path $script:Base -ChildPath 'Logs'
      $Setting.SummaryFolder = Join-Path -Path $script:Base -ChildPath 'Summaries'
      $Setting.DefaultSummaryFolder = Join-Path -Path $script:Base -ChildPath 'DefaultSummaries'
      $Setting.PermissiveFolderOverride = $Override
      $Setting
    }
  }

  It 'reads the override with the other output settings, also from an invalid document' {
    (Get-MaintenanceOutputSetting).PermissiveFolderOverride | Should -BeFalse
    $Document = '{ "schemaVersion": 1, "run": { "permissiveFolderOverride": true }, "backup": { "minimumKept": -1 } }' | ConvertFrom-Json
    (Get-MaintenanceOutputSetting -Document $Document).PermissiveFolderOverride | Should -BeTrue
  }

  It 'creates the log, report and summary folders protected' {
    $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting)

    $Output.Log.Error | Should -BeNullOrEmpty
    $Output.Refused | Should -HaveCount 0
    $Output.Notices | Should -HaveCount 0
    @($script:Created.Path | ForEach-Object -Process { Split-Path -Path $PSItem -Leaf }) | Should -Be @('Logs', 'Reports', 'Summaries')
  }

  It 'refuses a report folder that standard users can change, saving to the default and naming it in Refused' {
    New-PermissiveFolder -Path (Join-Path -Path $script:Base -ChildPath 'Reports')

    $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting)

    $Output.ReportFolder | Should -Be (Join-Path -Path $script:Base -ChildPath 'DefaultReports')
    $Output.Refused | Should -Be @("the report folder '{0}': it can be changed by BUILTIN\Users, not only by SYSTEM, Administrators and the run identity, so the run does not use it" -f (Join-Path -Path $script:Base -ChildPath 'Reports'))
    $Output.Notices[0].Message | Should -BeLike "The report folder '*Reports' cannot be used (it can be changed by BUILTIN\Users*); the report is saved to the default folder '*DefaultReports' instead."
  }

  It 'refuses a log folder that standard users can change, so the run cannot start' {
    New-PermissiveFolder -Path (Join-Path -Path $script:Base -ChildPath 'Logs')

    $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting)

    $Output.Log.Path | Should -BeNullOrEmpty
    $Output.Log.Error | Should -BeLike "The log folder '*Logs' cannot be used: it can be changed by BUILTIN\Users*"
  }

  It 'uses permissive folders with one warning each when the override is set' {
    ForEach ($Name In @('Logs', 'Reports', 'Summaries')) {
      New-PermissiveFolder -Path (Join-Path -Path $script:Base -ChildPath $Name)
    }

    $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Override $True)

    $Output.Log.Error | Should -BeNullOrEmpty
    $Output.Refused | Should -HaveCount 0
    $Output.ReportFolder | Should -Be (Join-Path -Path $script:Base -ChildPath 'Reports')
    $Output.Notices | Should -HaveCount 3
    @($Output.Notices.Severity | Select-Object -Unique) | Should -Be @('Warning')
    $Output.Notices[0].Message | Should -BeLike "The folder '*Logs' can be changed by BUILTIN\Users*; it is used because run.permissiveFolderOverride is set."
  }
}

Describe 'Test-MaintenanceInstallation' {
  BeforeEach {
    Use-FakeAcl
    $script:Folder = Join-Path -Path $TestDrive -ChildPath 'bin'
    $script:Script = Join-Path -Path $script:Folder -ChildPath 'Invoke-WsusMaintenance.ps1'
    Mock -CommandName Get-MaintenanceScriptPath -MockWith { $script:Script }
    New-ProtectedFolder -Path $script:Folder
    $script:Acl[$script:Script] = New-Access -Owner 'S-1-5-32-544' -Rules @(New-Rule -Sid 'S-1-5-18' -Rights $script:FullControl)
  }

  It 'passes a script that only trusted principals can change' {
    $Check = Test-MaintenanceInstallation

    $Check.Safe | Should -BeTrue
    $Check.Path | Should -Be $script:Script
    Should -Invoke -CommandName Get-MaintenancePathAccess -Times 2 -Exactly
  }

  It 'names who can change the folder or the script itself' {
    $script:Acl[$script:Folder] = New-Access -Rules @(New-Rule -Sid 'S-1-5-11' -Rights 0x2)
    $script:Acl[$script:Script] = New-Access -Rules @(New-Rule -Sid 'S-1-5-32-545' -Rights $script:FullControl)

    $Check = Test-MaintenanceInstallation

    $Check.Safe | Should -BeFalse
    $Check.Writers | Should -Be @('NT AUTHORITY\Authenticated Users', 'BUILTIN\Users')
  }

  It 'is not safe when the access control list cannot be read' {
    Mock -CommandName Get-MaintenancePathAccess -MockWith { Throw 'Attempted to perform an unauthorized operation.' }

    $Check = Test-MaintenanceInstallation

    $Check.Safe | Should -BeFalse
    $Check.Error | Should -Be 'Attempted to perform an unauthorized operation.'
  }
}

Describe 'ConvertTo-SqlServiceAccount' {
  It 'names the per-service account of <Name>' -ForEach @(
    @{ Name = 'WSUS01'; Account = 'NT SERVICE\MSSQLSERVER' }
    @{ Name = 'WSUS01\MSSQLSERVER'; Account = 'NT SERVICE\MSSQLSERVER' }
    @{ Name = 'WSUS01\SqlExpress'; Account = 'NT SERVICE\MSSQL$SQLEXPRESS' }
    @{ Name = 'WSUS01\WSUS,1433'; Account = 'NT SERVICE\MSSQL$WSUS' }
    @{ Name = ''; Account = 'NT SERVICE\MSSQLSERVER' }
  ) {
    ConvertTo-SqlServiceAccount -SqlServerName $Name | Should -Be $Account
  }
}

Describe 'Access-control seams' {
  It 'knows whether the host has access control lists' {
    Test-MaintenanceAclSupport | Should -Be ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
  }

  It 'returns the path of the file that defines the functions' {
    Get-MaintenanceScriptPath | Should -BeLike '*Invoke-WsusMaintenance.Functions.ps1'
  }

  It 'creates a protected folder that reads back with exactly the granted identities' -Skip:(-not $script:OnWindows) {
    $Sid = Get-MaintenanceIdentitySid
    $Path = Join-Path -Path $TestDrive -ChildPath 'protected'

    New-MaintenanceProtectedFolder -Path $Path -Identity @(Get-MaintenanceTrustedSid)

    (Get-Acl -LiteralPath $Path).AreAccessRulesProtected | Should -BeTrue
    $Access = Get-MaintenancePathAccess -Path $Path
    @($Access.Rules.Sid | Sort-Object -Unique) | Should -Be @(@('S-1-5-18', 'S-1-5-32-544', $Sid) | Sort-Object -Unique)
    @($Access.Rules | Where-Object -FilterScript { $PSItem.Allow -eq $False }) | Should -HaveCount 0
    (Test-MaintenancePathProtection -Path $Path -TrustedSid (Get-MaintenanceTrustedSid)).Permissive | Should -BeFalse
    [System.IO.File]::WriteAllText((Join-Path -Path $Path -ChildPath 'probe.txt'), 'x')
  }

  It 'reads nothing for a path that does not exist' -Skip:(-not $script:OnWindows) {
    Get-MaintenancePathAccess -Path (Join-Path -Path $TestDrive -ChildPath 'no-such-folder') | Should -BeNullOrEmpty
  }

  It 'names an account, or gives the identifier when it cannot be named' -Skip:(-not $script:OnWindows) {
    ConvertTo-MaintenanceAccountName -Sid ([System.Security.Principal.SecurityIdentifier]'S-1-5-18') | Should -Not -Be 'S-1-5-18'
    ConvertTo-MaintenanceAccountName -Sid ([System.Security.Principal.SecurityIdentifier]'S-1-5-21-1-2-3-999999') | Should -Be 'S-1-5-21-1-2-3-999999'
  }
}
