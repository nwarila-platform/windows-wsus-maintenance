#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Health checks' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    $script:Now = [System.DateTime]::new(2026, 11, 2, 6, 0, 0, [System.DateTimeKind]::Utc)
    $script:Expected = (ConvertTo-MaintenanceEffectiveConfiguration -Document ('{ "schemaVersion": 1, "backup": { "destination": "H:\\B" } }' | ConvertFrom-Json)).health

    Function script:New-HealthContext {
      Param ([System.String]$Extra = '', $Server = (New-FakeUpdateServer), [System.Int64]$Superseded = 0)
      $script:SupersededCount = $Superseded
      $Database = New-FakeSqlConnection -Responder { Param ($Text, $Parameters, $NonQuery) [PSCustomObject]@{ Total = $script:SupersededCount } }
      $Context = New-FakeStageContext -Database $Database -UpdateServer $Server -Extra $Extra
      $Context.StageName = 'HealthChecks'
      $Context
    }

    Function script:Get-Messages {
      Param ($Result)
      @($Result.Notices | ForEach-Object -Process { $PSItem.Message })
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 2, 1, 0, 0) }
    $script:Registry = New-FakeRegistry
    Mock -CommandName Get-MaintenanceRegistryKey -MockWith { $script:Registry[('{0}|{1}' -f $(If ($View) { $View } Else { 'Registry64' }), $Path)] }
    $script:NotAfter = $script:Now.AddDays(365)
    Mock -CommandName Get-MaintenanceCertificate -MockWith { [PSCustomObject]@{ Subject = 'CN=wsus01.example'; NotAfter = $script:NotAfter; Thumbprint = $Thumbprint } }
    $script:Machine = [PSCustomObject]@{ Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'; LogicalProcessors = 4 }
    Mock -CommandName Get-MaintenanceMachineInfo -MockWith { $script:Machine }
    $script:Setup = [PSCustomObject]@{ TargetDir = 'C:\Program Files\Update Services\'; UsingSSL = 1 }
    Mock -CommandName Get-WsusSetupValue -MockWith { $script:Setup }
    $script:Iis = New-FakeIisConfiguration
    Mock -CommandName Get-IisConfiguration -MockWith { $script:Iis }
  }

  Context 'Invoke-HealthCheck' {
    It 'raises no notice on a healthy server and reports one line per check' {
      $Result = Invoke-HealthCheck -Context (New-HealthContext)

      $Result.Status | Should -Be 'Success'
      $Result.Notices | Should -HaveCount 0
      $Result.Items | Should -Be @(
        'TLS: in use'
        'certificate on 0.0.0.0:8531: CN=wsus01.example, expires 2027-11-02 (365 day(s))'
        'strong cryptography: set in both registry views'
        'application pool WsusPool: 0 setting(s) differ from the expected values'
        'download settings: 0 differ from this deployment''s expected values'
        'superseded updates not declined: 0 (threshold 1500)'
        'processors: 4 on a virtual machine (minimum 4)'
      )
      $Result.Message | Should -Be 'Ran 7 health check(s): 0 finding(s), 0 check(s) could not run.'
    }

    It 'raises exactly the notice of <Case>' -ForEach @(
      @{ Case = 'TLS not in use'; Arrange = { $script:Setup = [PSCustomObject]@{ TargetDir = 'C:\Program Files\Update Services\'; UsingSSL = 0 } }; Severity = 'Warning'; Message = 'WSUS does not use TLS (UsingSSL is 0). Microsoft recommends*' }
      @{ Case = 'an expired certificate'; Arrange = { $script:NotAfter = $script:Now.AddDays(-2) }; Severity = 'Error'; Message = 'The certificate CN=wsus01.example bound to 0.0.0.0:8531 expired on 2026-10-31.*' }
      @{ Case = 'a certificate within the last tier'; Arrange = { $script:NotAfter = $script:Now.AddDays(5) }; Severity = 'High'; Message = '*expires in 5 day(s), on 2026-11-07 (within the 7-day warning tier). Renew it.' }
      @{ Case = 'a certificate within an earlier tier'; Arrange = { $script:NotAfter = $script:Now.AddDays(20) }; Severity = 'Warning'; Message = '*expires in 20 day(s), on 2026-11-22 (within the 30-day warning tier). Renew it.' }
      @{ Case = 'a missing strong-cryptography value'; Arrange = { $script:Registry['Registry32|SOFTWARE\Microsoft\.NETFramework\v4.0.30319'].Values.Remove('SchUseStrongCrypto') }; Severity = 'Warning'; Message = 'The .NET Framework strong-cryptography values are not all set to 1: SchUseStrongCrypto (Registry32) is absent.' }
      @{ Case = 'a pool queue length'; Arrange = { $script:Iis = New-FakeIisConfiguration -PoolAttributes 'queueLength="1000"' }; Severity = 'Warning'; Message = 'Application pool WsusPool: queue length is 1000; expected 2000, as Microsoft recommends for WSUS.' }
      @{ Case = 'pinging left on'; Arrange = { $script:Iis = New-FakeIisConfiguration -ProcessModel 'idleTimeout="00:00:00" pingingEnabled="true"' }; Severity = 'Warning'; Message = 'Application pool WsusPool: pinging enabled is true; expected false*' }
      @{ Case = 'a recycling interval'; Arrange = { $script:Iis = New-FakeIisConfiguration -PeriodicRestart 'privateMemory="0" memory="0" time="1.05:00:00"' }; Severity = 'Warning'; Message = 'Application pool WsusPool: regular recycling interval (minutes) is 1740; expected 0*' }
      @{ Case = 'a private memory limit'; Arrange = { $script:Iis = New-FakeIisConfiguration -PeriodicRestart 'privateMemory="1843200" memory="0" time="00:00:00"' }; Severity = 'Warning'; Message = 'Application pool WsusPool: private memory limit (KB) is 1843200; expected 0*' }
      @{ Case = 'express files on'; Arrange = { $script:Server = New-FakeUpdateServer -ExpressFiles $True }; Severity = 'Warning'; Message = 'WSUS download setting DownloadExpressPackages is True; this deployment expects False (health.downloadSettings.expressFiles).*' }
      @{ Case = 'too many superseded updates'; Arrange = { $script:Superseded = 1501 }; Severity = 'Warning'; Message = '1501 superseded updates are not declined, more than 1500*' }
      @{ Case = 'too few processors on a virtual machine'; Arrange = { $script:Machine = [PSCustomObject]@{ Manufacturer = 'VMware, Inc.'; Model = 'VMware7,1'; LogicalProcessors = 2 } }; Severity = 'Warning'; Message = 'This virtual machine has 2 logical processor(s); at least 4 are expected for WSUS.' }
    ) {
      $script:Server = New-FakeUpdateServer
      $script:Superseded = 0
      . $Arrange

      $Result = Invoke-HealthCheck -Context (New-HealthContext -Server $script:Server -Superseded $script:Superseded)

      $Result.Status | Should -Be 'Warning'
      $Result.Notices | Should -HaveCount 1
      $Result.Notices[0].Severity | Should -Be $Severity
      $Result.Notices[0].Message | Should -BeLike $Message
      $Result.Notices[0].Stage | Should -Be 'HealthChecks'
    }

    It 'raises one notice per pool setting that differs, read from the pool defaults and the IIS defaults' {
      $script:Iis = New-FakeIisConfiguration -PoolAttributes '' -ProcessModel '' -PeriodicRestart '' -PoolDefaults 'queueLength="3000"'

      $Result = Invoke-HealthCheck -Context (New-HealthContext)

      Get-Messages -Result $Result | Should -Be @(
        'Application pool WsusPool: queue length is 3000; expected 2000, as Microsoft recommends for WSUS.'
        'Application pool WsusPool: idle time-out (minutes) is 20; expected 0, as Microsoft recommends for WSUS.'
        'Application pool WsusPool: pinging enabled is true; expected false, as Microsoft recommends for WSUS.'
        'Application pool WsusPool: regular recycling interval (minutes) is 1740; expected 0, as Microsoft recommends for WSUS.'
      )
    }

    It 'compares the download settings with this deployment''s expectations, which a top tier sets to download everything' {
      $TopTier = New-FakeUpdateServer -DownloadAll $True

      $Default = Invoke-HealthCheck -Context (New-HealthContext -Server $TopTier)
      $Expected = Invoke-HealthCheck -Context (New-HealthContext -Server $TopTier -Extra ', "health": { "downloadSettings": { "downloadOnlyWhenApproved": false } }')
      $Hosted = Invoke-HealthCheck -Context (New-HealthContext -Server (New-FakeUpdateServer -FilesOnMicrosoftUpdate $True))

      Get-Messages -Result $Default | Should -Be @('WSUS download setting DownloadUpdateBinariesAsNeeded is False; this deployment expects True (health.downloadSettings.downloadOnlyWhenApproved). Configuration management owns the setting; it was not changed.')
      $Expected.Notices | Should -HaveCount 0
      Get-Messages -Result $Hosted | Should -BeLike 'WSUS download setting HostBinariesOnMicrosoftUpdate is True; this deployment expects False*'
      $TopTier.Configuration.DownloadUpdateBinariesAsNeeded | Should -BeFalse
    }

    It 'skips disabled checks' {
      $Result = Invoke-HealthCheck -Context (New-HealthContext -Extra ', "health": { "tls": { "enabled": false }, "processorCount": { "enabled": false }, "appPool": { "enabled": false }, "certificateExpiry": { "enabled": false } }')

      $Result.Counts['Checks'] | Should -Be 3
      Should -Invoke -CommandName Get-IisConfiguration -Times 0 -Exactly
    }

    It 'raises a notice for a check that fails and still runs the others' {
      Mock -CommandName Get-MaintenanceMachineInfo -MockWith { Throw 'The CIM service is not available.' }

      $Result = Invoke-HealthCheck -Context (New-HealthContext)

      $Result.Counts['NotRun'] | Should -Be 1
      Get-Messages -Result $Result | Should -Be @('Health check processors could not run: The CIM service is not available.')
      $Result.Items[-1] | Should -Be 'processors: could not run'
      $Result.Items[0] | Should -Be 'TLS: in use'
    }

    It 'names in one notice the checks that need the IIS configuration when it cannot be read' {
      Mock -CommandName Get-IisConfiguration -MockWith { Throw 'Could not find file applicationHost.config.' }

      $Result = Invoke-HealthCheck -Context (New-HealthContext)

      Get-Messages -Result $Result | Should -Be @('Health checks certificate expiry, application pool could not run: the IIS configuration could not be read (Could not find file applicationHost.config.).')
      $Result.Counts['NotRun'] | Should -Be 2
      $Result.Counts['Checks'] | Should -Be 7
    }

    It 'names in one notice the checks that need the WSUS website when it cannot be found' {
      $script:Iis = New-FakeIisConfiguration -SiteName 'Other' -PhysicalPath 'D:\Elsewhere' -RemoteAdministration $False

      $Result = Invoke-HealthCheck -Context (New-HealthContext)

      Get-Messages -Result $Result | Should -Be @('Health checks certificate expiry, application pool could not run: the WSUS website was not found (by the default name WSUS Administration).')
    }
  }

  Context 'single checks' {
    It 'reports a TLS port without a bound certificate, and a bound certificate missing from its store' {
      $script:Registry.Remove('Registry64|SYSTEM\CurrentControlSet\Services\HTTP\Parameters\SslBindingInfo')
      $None = Test-CertificateHealth -Now $script:Now -Port @(8531) -WarningDays @(60, 30, 14, 7)
      $script:Registry = New-FakeRegistry
      Mock -CommandName Get-MaintenanceCertificate -MockWith { $Null }
      $Missing = Test-CertificateHealth -Now $script:Now -Port @(8531) -WarningDays @(60, 30, 14, 7)

      $None.Notices[0].Message | Should -Be 'No certificate is bound in HTTP.sys to port 8531, which the WSUS website uses for https.'
      $Missing.Notices[0].Message | Should -Be 'The certificate ABCDEF bound to 0.0.0.0:8531 is not in the local-machine store MY.'
      Should -Invoke -CommandName Get-MaintenanceCertificate -ParameterFilter { ($StoreName -eq 'MY') -and ($Thumbprint -eq 'ABCDEF') }
    }

    It 'reports a site without an https binding without a notice' {
      $Result = Test-CertificateHealth -Now $script:Now -Port @() -WarningDays @(60, 30, 14, 7)

      $Result.Item | Should -Be 'certificate: the WSUS website has no https binding'
      $Result.Notices | Should -HaveCount 0
    }

    It 'throws when the WSUS setup values are missing' {
      { Test-WsusTlsHealth -Setup $Null } | Should -Throw -ExpectedMessage 'the WSUS setup values could not be read'
      (Test-WsusTlsHealth -Setup ([PSCustomObject]@{})).Notices[0].Message | Should -BeLike 'WSUS does not use TLS (UsingSSL is not recorded).*'
    }

    It 'reports strong-cryptography values when a registry view has no key at all' {
      $script:Registry.Remove('Registry32|SOFTWARE\Microsoft\.NETFramework\v4.0.30319')

      (Test-StrongCryptoHealth).Notices[0].Message | Should -Be 'The .NET Framework strong-cryptography values are not all set to 1: SchUseStrongCrypto (Registry32) is absent; SystemDefaultTlsVersions (Registry32) is absent.'
    }

    It 'reports an application pool that is not in the configuration' {
      $Result = Test-AppPoolHealth -Expected $script:Expected.appPool -Iis (New-FakeIisConfiguration) -PoolName 'MissingPool'

      $Result.Item | Should -Be 'application pool MissingPool: not found'
      $Result.Notices[0].Message | Should -Be 'The application pool MissingPool of the WSUS website is not in the IIS configuration.'
    }

    It 'does not check the processors of a physical computer' {
      $script:Machine = [PSCustomObject]@{ Manufacturer = 'Example Hardware'; Model = 'Rack Server'; LogicalProcessors = 2 }

      $Result = Test-ProcessorHealth -Minimum 4

      $Result.Item | Should -Be 'processors: 2 on a physical computer, not checked'
      $Result.Notices | Should -HaveCount 0
    }

    It 'recognises <Manufacturer> <Model> as virtual: <Expected>' -ForEach @(
      @{ Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'; Expected = $True }
      @{ Manufacturer = 'VMware, Inc.'; Model = 'VMware20,1'; Expected = $True }
      @{ Manufacturer = 'QEMU'; Model = 'Standard PC (Q35 + ICH9, 2009)'; Expected = $True }
      @{ Manufacturer = 'innotek GmbH'; Model = 'VirtualBox'; Expected = $True }
      @{ Manufacturer = 'Amazon EC2'; Model = 'm5.large'; Expected = $True }
      @{ Manufacturer = 'Xen'; Model = 'HVM domU'; Expected = $True }
      @{ Manufacturer = 'Example Hardware'; Model = 'Rack Server'; Expected = $False }
      @{ Manufacturer = 'Microsoft Corporation'; Model = 'Surface Pro'; Expected = $False }
    ) {
      Test-VirtualMachine -Manufacturer $Manufacturer -Model $Model | Should -Be $Expected
    }
  }
}
