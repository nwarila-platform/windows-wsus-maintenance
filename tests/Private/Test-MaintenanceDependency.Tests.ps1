#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
  $script:HasWsus = $script:OnWindows -and (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup')
  $script:HasIis = $script:OnWindows -and (Test-Path -LiteralPath ([System.Environment]::ExpandEnvironmentVariables('%windir%\System32\inetsrv\config\applicationHost.config')))
}

BeforeAll {
  . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

  Function script:New-Configuration {
    Param ([System.String]$Extra = '')
    ConvertTo-MaintenanceEffectiveConfiguration -Document (('{ "schemaVersion": 1, "backup": { "destination": "H:\\Backups" }' + $Extra + ' }') | ConvertFrom-Json)
  }
}

Describe 'Test-MaintenanceDependency' {
  BeforeEach {
    $script:Missing = @()
    Mock -CommandName Test-MaintenanceDependencyPresent -MockWith { $script:Missing -notcontains $Name }
  }

  It 'reports every component present and makes nothing unavailable' {
    $Check = Test-MaintenanceDependency -Configuration (New-Configuration)

    $Check.Summary | Should -Be 'the WSUS administration API (Microsoft.UpdateServices.Administration) present; the SQL Server client (System.Data.SqlClient) present; the IIS configuration (applicationHost.config) present'
    $Check.Blocking | Should -HaveCount 0
    $Check.Unavailable.Count | Should -Be 0
    Should -Invoke -CommandName Test-MaintenanceDependencyPresent -Times 3 -Exactly
  }

  It 'makes IIS log retention unavailable when the IIS configuration is missing' {
    $script:Missing = @('IisConfiguration')

    $Check = Test-MaintenanceDependency -Configuration (New-Configuration)

    $Check.Summary | Should -BeLike '*the IIS configuration (applicationHost.config) missing'
    $Check.Blocking | Should -HaveCount 0
    @($Check.Unavailable.Keys) | Should -Be @('IisLogRetention')
    $Check.Unavailable['IisLogRetention'] | Should -Be 'the IIS configuration (applicationHost.config)'
  }

  It 'needs no IIS configuration when iisLogs.folder names the folder' {
    $script:Missing = @('IisConfiguration')

    (Test-MaintenanceDependency -Configuration (New-Configuration -Extra ', "iisLogs": { "folder": "L:\\IisLogs" }')).Unavailable.Count | Should -Be 0
  }

  It 'returns a missing component the whole run needs as blocking: <Name>' -ForEach @(
    @{ Name = 'WsusApi'; Label = 'the WSUS administration API (Microsoft.UpdateServices.Administration)' }
    @{ Name = 'SqlClient'; Label = 'the SQL Server client (System.Data.SqlClient)' }
  ) {
    $script:Missing = @($Name)

    $Check = Test-MaintenanceDependency -Configuration (New-Configuration)

    $Check.Blocking | Should -Be @($Label)
    $Check.Summary | Should -BeLike ('*{0} missing*' -f [System.Management.Automation.WildcardPattern]::Escape($Label))
  }

  It 'counts a component it cannot check as missing, with the reason' {
    Mock -CommandName Test-MaintenanceDependencyPresent -ParameterFilter { $Name -eq 'IisConfiguration' } -MockWith { Throw 'Access is denied.' }

    $Check = Test-MaintenanceDependency -Configuration (New-Configuration)

    $Check.Summary | Should -BeLike '*the IIS configuration (applicationHost.config) not checked (Access is denied.)'
    $Check.Unavailable['IisLogRetention'] | Should -Be 'the IIS configuration (applicationHost.config)'
  }
}

Describe 'Test-MaintenanceDependencyPresent' {
  It 'finds the SQL Server client of Windows PowerShell' -Skip:(-not $script:OnWindows -or ($PSVersionTable.PSEdition -ne 'Desktop')) {
    Test-MaintenanceDependencyPresent -Name 'SqlClient' | Should -BeTrue
  }

  It 'finds no WSUS administration API where WSUS is not installed' -Skip:$script:HasWsus {
    Test-MaintenanceDependencyPresent -Name 'WsusApi' | Should -BeFalse
  }

  It 'finds no IIS configuration where IIS is not installed' -Skip:$script:HasIis {
    Test-MaintenanceDependencyPresent -Name 'IisConfiguration' | Should -BeFalse
  }
}

Describe 'Runtime integrity' {
  BeforeAll {
    $script:Sources = @(Get-ChildItem -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../src') -Filter '*.ps1' -Recurse)
  }

  # The script never fetches or installs code, changes file trust or its own files, or loads code
  #   from another location (REQ-093). Each pattern is a command or API that would.
  It 'contains no call that <Purpose>' -ForEach @(
    @{ Purpose = 'installs a module or package'; Pattern = '(?i)\b(Install-Module|Install-Package|Save-Module|Install-Script|Update-Module|Register-PSRepository|Install-PackageProvider)\b' }
    @{ Purpose = 'downloads'; Pattern = '(?i)\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|DownloadString|DownloadFile|DownloadData|Net\.WebClient|Net\.Http\.HttpClient)\b' }
    @{ Purpose = 'changes file trust or the execution policy'; Pattern = '(?i)\b(Unblock-File|Set-ExecutionPolicy|Set-AuthenticodeSignature)\b|Zone\.Identifier' }
    @{ Purpose = 'loads code from a file or runs text as code'; Pattern = '(?i)\b(Import-Module|Invoke-Expression|LoadFrom|LoadFile|UnsafeLoadFrom)\b|Add-Type\s+-Path|\biex\b' }
  ) {
    $Found = @(ForEach ($File In $script:Sources) {
        Select-String -LiteralPath $File.FullName -Pattern $Pattern | ForEach-Object -Process { '{0}:{1}: {2}' -f $File.Name, $PSItem.LineNumber, $PSItem.Line.Trim() }
      })

    $Found | Should -HaveCount 0
  }

  It 'never writes to the file it runs from' {
    $Found = @(ForEach ($File In $script:Sources) {
        Select-String -LiteralPath $File.FullName -Pattern '(?i)(Set-Content|Add-Content|Out-File|WriteAll\w+|Remove-Item|Move-Item|Rename-Item)[^\r\n]*(PSCommandPath|Get-MaintenanceScriptPath|MyInvocation)' | ForEach-Object -Process { '{0}:{1}' -f $File.Name, $PSItem.LineNumber }
      })

    $Found | Should -HaveCount 0
  }
}
