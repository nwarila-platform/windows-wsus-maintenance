#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeAll {
  . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
}

Describe 'Test-MaintenanceTimeout' {
  It 'recognises <Case> as a time-out' -ForEach @(
    @{ Case = 'a TimeoutException'; Exception = { [System.TimeoutException]::new('Gone.') } }
    @{ Case = 'a web request that timed out'; Exception = { [System.Net.WebException]::new('Request failed.', [System.Net.WebExceptionStatus]::Timeout) } }
    @{ Case = 'a time-out inside another exception'; Exception = { [System.InvalidOperationException]::new('Cleanup failed.', [System.TimeoutException]::new('Gone.')) } }
    @{ Case = 'a SQL Server command time-out message'; Exception = { [System.Exception]::new('Execution Timeout Expired. The timeout period elapsed prior to completion of the operation.') } }
    @{ Case = 'an operation that timed out'; Exception = { [System.Exception]::new('The operation has timed out') } }
  ) {
    Test-MaintenanceTimeout -Exception (& $Exception) | Should -BeTrue
  }

  It 'does not take <Case> for a time-out' -ForEach @(
    @{ Case = 'a refused connection'; Exception = { [System.Net.WebException]::new('Unable to connect to the remote server.', [System.Net.WebExceptionStatus]::ConnectFailure) } }
    @{ Case = 'an access error'; Exception = { [System.UnauthorizedAccessException]::new('Access is denied.') } }
    @{ Case = 'a word that only contains the letters'; Exception = { [System.Exception]::new('Lifetime output stopped.') } }
  ) {
    Test-MaintenanceTimeout -Exception (& $Exception) | Should -BeFalse
  }
}

Describe 'ConvertTo-MaintenanceByteText' {
  It 'writes <Bytes> bytes as <Text>' -ForEach @(
    @{ Bytes = 0; Text = '0 bytes' }
    @{ Bytes = 1023; Text = '1023 bytes' }
    @{ Bytes = 1024; Text = '1.0 KB' }
    @{ Bytes = 1610612736; Text = '1.5 GB' }
    @{ Bytes = 1099511627776; Text = '1.0 TB' }
    @{ Bytes = 4611686018427387904; Text = '4096.0 PB' }
  ) {
    ConvertTo-MaintenanceByteText -Bytes $Bytes | Should -Be $Text
  }
}

Describe 'ConvertTo-StaleComputerText' {
  It 'describes a computer with its last synchronization in UTC, or never' -ForEach @(
    @{ LastSync = [System.DateTime]::new(2026, 7, 1, 13, 5, 0); Expected = 'pc1.example (last synchronized 2026-07-01 13:05 UTC, Windows 11 Enterprise, client 10.0.26100.1)' }
    @{ LastSync = [System.DateTime]::MinValue; Expected = 'pc1.example (last synchronized never, Windows 11 Enterprise, client 10.0.26100.1)' }
    @{ LastSync = $Null; Expected = 'pc1.example (last synchronized never, Windows 11 Enterprise, client 10.0.26100.1)' }
  ) {
    $Computer = [PSCustomObject]@{ FullDomainName = 'pc1.example'; LastSyncTime = $LastSync; OSDescription = 'Windows 11 Enterprise'; ClientVersion = '10.0.26100.1' }

    ConvertTo-StaleComputerText -Computer $Computer | Should -Be $Expected
  }
}
