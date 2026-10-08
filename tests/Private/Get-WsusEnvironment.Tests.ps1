#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-WsusEnvironment' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
    $script:Machine = [System.Environment]::MachineName
    $script:Server2022 = [PSCustomObject]@{ Platform = 'Win32NT'; Major = 10; Build = 20348 }

    Function script:New-Configuration {
      Param ([System.String]$Discovery = '')
      $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }' + $(If ($Discovery) { ', "discovery": ' + $Discovery } Else { '' }) + ' }'
      Get-FakeConfiguration -Json $Json
    }

    Function script:Get-Environment {
      Param ($Setup, $Configuration = (New-Configuration), $System = $script:Server2022)
      Get-WsusEnvironment -Configuration $Configuration -OperatingSystem $System -Setup $Setup
    }
  }

  It 'classifies <Name> as local SQL Server' -ForEach @(
    @{ Name = 'the computer name'; Instance = $null }
    @{ Name = 'a named instance on this computer'; Instance = 'SQLEXPRESS' }
    @{ Name = 'the fully qualified name'; Instance = 'FQDN' }
    @{ Name = 'a dot'; Instance = 'DOT' }
    @{ Name = 'localhost'; Instance = 'LOCALHOST' }
  ) {
    $SqlServerName = Switch ($Instance) {
      'SQLEXPRESS' { '{0}\SQLEXPRESS' -f $script:Machine }
      'FQDN' { '{0}.corp.example' -f $script:Machine }
      'DOT' { '.' }
      'LOCALHOST' { 'localhost\MSSQLSERVER2' }
      Default { $script:Machine }
    }

    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = $SqlServerName; SqlDatabaseName = 'SUSDB' })

    $Environment.Problems | Should -HaveCount 0
    $Environment.DatabaseType | Should -Be 'SqlServer'
    $Environment.DatabaseLocation | Should -Be 'Local'
    $Environment.SqlServerName | Should -Be $SqlServerName
    $Environment.DatabaseName | Should -Be 'SUSDB'
    $Environment.OperatingSystem | Should -Be 'Windows Server 2022'
    $Environment.Description | Should -Be ('SQL Server on this server, instance {0}, database SUSDB (from WSUS setup)' -f $SqlServerName)
  }

  It 'refuses Windows Internal Database, naming it' -ForEach @(
    @{ Name = 'MICROSOFT##WID' }
    @{ Name = 'WSUS01\MICROSOFT##SSEE' }
  ) {
    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = $Name; SqlDatabaseName = 'SUSDB' })

    $Environment.DatabaseType | Should -Be 'WindowsInternalDatabase'
    $Environment.Problems | Should -Be @(("SUSDB is on Windows Internal Database ('{0}'); this release supports SUSDB on SQL Server on the WSUS server only." -f $Name))
    $Environment.Description | Should -Be ('Windows Internal Database ({0}), database SUSDB' -f $Name)
  }

  It 'refuses a remote SQL Server, naming it' {
    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = 'SQL01\WSUS'; SqlDatabaseName = 'SUSDB' })

    $Environment.DatabaseType | Should -Be 'SqlServer'
    $Environment.DatabaseLocation | Should -Be 'Remote'
    $Environment.Problems | Should -Be @("SUSDB is on the remote SQL Server 'SQL01\WSUS'; this release supports SUSDB on SQL Server on the WSUS server only.")
    $Environment.Description | Should -Be 'SQL Server on another server, instance SQL01\WSUS, database SUSDB (from WSUS setup)'
  }

  It 'takes overrides from the configuration' {
    $Configuration = New-Configuration -Discovery ('{{ "sqlInstance": "{0}\\INST2", "databaseName": "SUSDB2" }}' -f $script:Machine)

    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = 'SQL01'; SqlDatabaseName = 'SUSDB' }) -Configuration $Configuration

    $Environment.Problems | Should -HaveCount 0
    $Environment.SqlServerName | Should -Be ('{0}\INST2' -f $script:Machine)
    $Environment.DatabaseName | Should -Be 'SUSDB2'
    $Environment.Description | Should -BeLike '*(from configuration)'
  }

  It 'reports that WSUS is not installed' {
    $Environment = Get-Environment -Setup $Null

    $Environment.Problems | Should -Be @('WSUS is not installed on this server: the registry key HKLM\SOFTWARE\Microsoft\Update Services\Server\Setup does not exist.')
    $Environment.Description | Should -Be "not determined (instance '')"
  }

  It 'reports values that are neither recorded nor configured' {
    $Environment = Get-Environment -Setup ([PSCustomObject]@{ ContentDir = 'D:\WSUS' })

    $Environment.Problems | Should -Be @(
      'WSUS setup records no SQL Server instance (SqlServerName) and discovery.sqlInstance is not set.'
      'WSUS setup records no database name (SqlDatabaseName) and discovery.databaseName is not set.'
    )
  }

  It 'reports names it cannot connect to' {
    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = 'tcp:SQL01,1433'; SqlDatabaseName = 'SUS DB' })

    $Environment.Problems[0] | Should -Be "'tcp:SQL01,1433' is not a SQL Server instance name this release can connect to (HOST or HOST\INSTANCE)."
    $Environment.Problems[1] | Should -Be "The SUSDB database name 'SUS DB' is not a valid database name."
  }

  It 'refuses <Name>, naming the release' -ForEach @(
    @{ Name = 'Windows Server 2016'; Build = 14393; Expected = 'Windows Server 2016 (build 14393) is not supported; this release supports Windows Server 2019, 2022 and 2025.' }
    @{ Name = 'an older build'; Build = 9600; Expected = 'Windows build 9600 (build 9600) is not supported; this release supports Windows Server 2019, 2022 and 2025.' }
  ) {
    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = $script:Machine; SqlDatabaseName = 'SUSDB' }) -System ([PSCustomObject]@{ Platform = 'Win32NT'; Major = 10; Build = $Build })

    $Environment.Problems | Should -Be @($Expected)
  }

  It 'names every supported release' -ForEach @(
    @{ Build = 17763; Name = 'Windows Server 2019' }
    @{ Build = 26100; Name = 'Windows Server 2025' }
    @{ Build = 26200; Name = 'Windows build 26200' }
  ) {
    $Environment = Get-Environment -Setup ([PSCustomObject]@{ SqlServerName = $script:Machine; SqlDatabaseName = 'SUSDB' }) -System ([PSCustomObject]@{ Platform = 'Win32NT'; Major = 10; Build = $Build })

    $Environment.OperatingSystem | Should -Be $Name
    $Environment.Problems | Should -HaveCount 0
  }
}
