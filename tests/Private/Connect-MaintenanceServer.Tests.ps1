#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Connect-MaintenanceServer' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
    $script:Environment = [PSCustomObject]@{ SqlServerName = 'WSUS01\SQLEXPRESS'; DatabaseName = 'SUSDB' }

    Function script:New-Configuration {
      Param ([System.String]$Discovery = '')
      $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }, "run": { "connectionTimeoutSeconds": 45 }, "declines": { "evaluationLanguage": "de" }' + $(If ($Discovery) { ', "discovery": ' + $Discovery } Else { '' }) + ' }'
      Get-FakeConfiguration -Json $Json
    }
  }

  BeforeEach {
    $script:Clock = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Clock = $script:Clock.AddSeconds(1); $script:Clock }
    $script:Server = New-FakeUpdateServer
    $script:Database = New-FakeSqlConnection
    Mock -CommandName Get-WsusUpdateServer -MockWith { $script:Server }
    Mock -CommandName New-SqlConnection -MockWith { $script:Database }
  }

  It 'connects to the local WSUS server and to SUSDB, recording when each was established' {
    $Connection = Connect-MaintenanceServer -Configuration (New-Configuration) -Environment $script:Environment

    $Connection.Error | Should -BeNullOrEmpty
    $Connection.Point | Should -BeNullOrEmpty
    $Connection.UpdateServer | Should -Be $script:Server
    $Connection.Database | Should -Be $script:Database
    $Connection.ApiConnectedAt | Should -Be ([System.DateTime]::new(2026, 11, 2, 1, 0, 1))
    $Connection.DatabaseConnectedAt | Should -Be ([System.DateTime]::new(2026, 11, 2, 1, 0, 2))
    $Connection.Endpoint | Should -Be 'wsus01.example, port 8531, TLS'
    $script:Server.PreferredCulture | Should -Be ''
    Should -Invoke -CommandName Get-WsusUpdateServer -Times 1 -Exactly -ParameterFilter { $HostName -eq '' }
    Should -Invoke -CommandName New-SqlConnection -Times 1 -Exactly -ParameterFilter {
      $ConnectionString -eq 'Data Source=WSUS01\SQLEXPRESS;Initial Catalog=SUSDB;Integrated Security=SSPI;Connect Timeout=45;Application Name=Invoke-WsusMaintenance'
    }
  }

  It 'connects to the configured endpoint, with defaults for what is not set' -ForEach @(
    @{ Discovery = '{ "wsusHostName": "wsus.corp.example" }'; ExpectedHost = 'wsus.corp.example'; ExpectedPort = 8530; ExpectedTls = $False }
    @{ Discovery = '{ "wsusUseTls": true }'; ExpectedHost = 'MACHINE'; ExpectedPort = 8531; ExpectedTls = $True }
    @{ Discovery = '{ "wsusPort": 443, "wsusUseTls": true }'; ExpectedHost = 'MACHINE'; ExpectedPort = 443; ExpectedTls = $True }
  ) {
    $script:WantHost = If ($ExpectedHost -eq 'MACHINE') { [System.Environment]::MachineName } Else { $ExpectedHost }
    $script:WantPort = $ExpectedPort
    $script:WantTls = $ExpectedTls

    $Null = Connect-MaintenanceServer -Configuration (New-Configuration -Discovery $Discovery) -Environment $script:Environment

    Should -Invoke -CommandName Get-WsusUpdateServer -Times 1 -Exactly -ParameterFilter { ($HostName -eq $script:WantHost) -and ($Port -eq $script:WantPort) -and ($UseTls -eq $script:WantTls) }
  }

  It 'reports an endpoint without TLS' {
    $script:Server.IsConnectionSecureForApiRemoting = $False
    $script:Server.PortNumber = 8530

    (Connect-MaintenanceServer -Configuration (New-Configuration) -Environment $script:Environment).Endpoint | Should -Be 'wsus01.example, port 8530, no TLS'
  }

  It 'stops at the WSUS administration interface when it cannot be reached' {
    Mock -CommandName Get-WsusUpdateServer -MockWith { Throw 'The request failed with HTTP status 503.' }

    $Connection = Connect-MaintenanceServer -Configuration (New-Configuration) -Environment $script:Environment

    $Connection.Point | Should -Be 'Api'
    $Connection.Error | Should -Be 'The WSUS administration interface could not be reached: The request failed with HTTP status 503.'
    Should -Invoke -CommandName New-SqlConnection -Times 0 -Exactly
  }

  It 'stops at SUSDB when it cannot be opened' {
    Mock -CommandName New-SqlConnection -MockWith { Throw 'Login failed.' }

    $Connection = Connect-MaintenanceServer -Configuration (New-Configuration) -Environment $script:Environment

    $Connection.Point | Should -Be 'Database'
    $Connection.Error | Should -Be "SUSDB could not be opened on 'WSUS01\SQLEXPRESS' (database SUSDB): Login failed."
    $Connection.ApiConnectedAt | Should -Not -BeNullOrEmpty
    $Connection.DatabaseConnectedAt | Should -BeNullOrEmpty
  }
}
