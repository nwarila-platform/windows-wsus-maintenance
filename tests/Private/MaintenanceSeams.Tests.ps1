#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
  $script:HasWsus = $script:OnWindows -and (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup')
  $script:HasIis = $script:OnWindows -and (Test-Path -LiteralPath ([System.Environment]::ExpandEnvironmentVariables('%windir%\System32\inetsrv\config\applicationHost.config')))
}

Describe 'Server seams' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'finds no WSUS setup values on a computer without WSUS' -Skip:$script:HasWsus {
    Get-WsusSetupValue | Should -BeNullOrEmpty
  }

  It 'refuses to connect when the WSUS administration API is not installed' -Skip:$script:HasWsus {
    { Get-WsusUpdateServer } | Should -Throw -ExpectedMessage 'The WSUS administration API (Microsoft.UpdateServices.Administration) is not installed on this computer.'
  }

  It 'refuses to create an administration API object when the API is not installed' -Skip:$script:HasWsus {
    { New-WsusAdministrationObject -TypeName 'CleanupScope' } | Should -Throw -ExpectedMessage 'The WSUS administration API type Microsoft.UpdateServices.Administration.CleanupScope is not available; it is loaded when the run connects to WSUS.'
  }

  It 'refuses to read the IIS configuration where IIS is not installed' -Skip:$script:HasIis {
    { Get-IisConfiguration } | Should -Throw
  }

  It 'reads a registry key in both views and returns null for a missing one' -Skip:(-not $script:OnWindows) {
    (Get-MaintenanceRegistryKey -Path 'SOFTWARE\Microsoft\Windows NT\CurrentVersion').Values['CurrentBuild'] | Should -Not -BeNullOrEmpty
    (Get-MaintenanceRegistryKey -Path 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -View 'Registry32') | Should -Not -BeNullOrEmpty
    Get-MaintenanceRegistryKey -Path 'SOFTWARE\NoSuchVendor\NoSuchKey' | Should -BeNullOrEmpty
  }

  It 'refuses registry reads off Windows' -Skip:$script:OnWindows {
    { Get-MaintenanceRegistryKey -Path 'SOFTWARE' } | Should -Throw
  }

  It 'finds no certificate for a thumbprint that is not in the store' -Skip:(-not $script:OnWindows) {
    Get-MaintenanceCertificate -StoreName 'My' -Thumbprint '0000000000000000000000000000000000000000' | Should -BeNullOrEmpty
  }

  It 'reports the computer model and its processors' -Skip:(-not $script:OnWindows) {
    $Machine = Get-MaintenanceMachineInfo

    $Machine.LogicalProcessors | Should -BeGreaterThan 0
    $Machine.Model | Should -Not -BeNullOrEmpty
  }

  It 'throws when SQL Server cannot be reached' {
    { New-SqlConnection -ConnectionString 'Data Source=127.0.0.1,1;Initial Catalog=SUSDB;Connect Timeout=1;Integrated Security=False;User ID=probe;Password=probe' } | Should -Throw
  }

  It 'reports the operating system build' {
    $System = Get-MaintenanceOperatingSystem

    $System.Build | Should -BeOfType ([System.Int32])
    $System.Platform | Should -Not -BeNullOrEmpty
  }

  It 'names the run identity' {
    Get-MaintenanceIdentity | Should -Match '\\'
  }

  It 'waits the given number of seconds, and not at all for zero' {
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    Wait-MaintenanceInterval -Seconds 0
    $Watch.Elapsed.TotalSeconds | Should -BeLessThan 1
    Wait-MaintenanceInterval -Seconds 1
    $Watch.Elapsed.TotalSeconds | Should -BeGreaterOrEqual 0.9
  }

  Context 'Disconnect-MaintenanceServer' {
    It 'closes the database connection' {
      $Database = [PSCustomObject]@{ Disposed = 0 }
      $Database | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }

      Disconnect-MaintenanceServer -Connection ([PSCustomObject]@{ Database = $Database })

      $Database.Disposed | Should -Be 1
    }

    It 'tolerates no connection and a close that fails' {
      $Database = [PSCustomObject]@{}
      $Database | Add-Member -MemberType ScriptMethod -Name Dispose -Value { Throw 'Already closed.' }

      { Disconnect-MaintenanceServer -Connection $Null } | Should -Not -Throw
      { Disconnect-MaintenanceServer -Connection ([PSCustomObject]@{ Database = $Database }) } | Should -Not -Throw
    }
  }
}
