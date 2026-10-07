#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:IsWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

Describe 'Windows Event Log' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:New-Channel {
      Param ([System.Boolean]$Enabled = $True)
      $Setting = (Get-MaintenanceOutputSetting).EventLog
      $Setting.Enabled = $Enabled
      $Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
      New-MaintenanceEventChannel -Setting $Setting -Log $Log
    }
  }

  BeforeEach {
    $Script:MaintenanceSecret.Clear()
    $script:Written = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Test-MaintenanceEventSource -MockWith { $True }
    Mock -CommandName Write-MaintenanceEventEntry -MockWith {
      $script:Written.Add([PSCustomObject]@{ EntryType = $EntryType; EventId = $EventId; Message = $Message; Source = $Source })
    }
  }

  It 'prepares a channel from the settings with the source not yet checked' {
    $Channel = New-Channel

    $Channel.Enabled | Should -BeTrue
    $Channel.LogName | Should -Be 'Application'
    $Channel.Source | Should -Be 'Invoke-WsusMaintenance'
    $Channel.Available | Should -BeNullOrEmpty
    $Channel.Written | Should -Be 0
  }

  It 'writes <Kind> as event <Id> of type <Type>' -ForEach @(
    @{ Kind = 'runStarted'; Id = 1000; Type = 'Information' }
    @{ Kind = 'runSucceeded'; Id = 1001; Type = 'Information' }
    @{ Kind = 'runWarning'; Id = 1002; Type = 'Warning' }
    @{ Kind = 'runFailed'; Id = 1003; Type = 'Error' }
    @{ Kind = 'stageError'; Id = 1100; Type = 'Error' }
    @{ Kind = 'preconditionFailure'; Id = 1200; Type = 'Error' }
    @{ Kind = 'configurationInvalid'; Id = 1300; Type = 'Error' }
  ) {
    $Channel = New-Channel

    Write-MaintenanceEvent -Channel $Channel -Kind $Kind -Message 'text'

    $script:Written | Should -HaveCount 1
    $script:Written[0].EventId | Should -Be $Id
    $script:Written[0].EntryType | Should -Be $Type
    $script:Written[0].Source | Should -Be 'Invoke-WsusMaintenance'
    $Channel.Written | Should -Be 1
  }

  It 'checks the source once and removes secrets and excess length from the message' {
    Register-MaintenanceSecret -Value 'hunter2'
    $Channel = New-Channel

    Write-MaintenanceEvent -Channel $Channel -Kind 'stageError' -Message ('hunter2 ' + ('x' * 40000))
    Write-MaintenanceEvent -Channel $Channel -Kind 'runFailed' -Message 'done'

    Should -Invoke -CommandName Test-MaintenanceEventSource -Times 1 -Exactly
    $script:Written[0].Message | Should -Not -Match 'hunter2'
    $script:Written[0].Message.Length | Should -Be 30000
  }

  It 'logs a single warning and writes nothing when the source is not registered' {
    Mock -CommandName Test-MaintenanceEventSource -MockWith { $False }
    $Channel = New-Channel

    Write-MaintenanceEvent -Channel $Channel -Kind 'runStarted' -Message 'a'
    Write-MaintenanceEvent -Channel $Channel -Kind 'runSucceeded' -Message 'b'

    $script:Written | Should -HaveCount 0
    $Lines = @(Get-Content -LiteralPath $Channel.Log.Path)
    $Lines | Should -HaveCount 1
    $Lines[0] | Should -BeLike "*Warning*Event source 'Invoke-WsusMaintenance' cannot be used in the 'Application' event log (the source is not registered in that log); this run writes no events."
  }

  It 'treats a source that cannot be checked as unavailable' {
    Mock -CommandName Test-MaintenanceEventSource -MockWith { Throw 'Requested registry access is not allowed.' }
    $Channel = New-Channel

    Write-MaintenanceEvent -Channel $Channel -Kind 'runStarted' -Message 'a'

    $Channel.Available | Should -BeFalse
    (Get-Content -LiteralPath $Channel.Log.Path -Raw) | Should -Match 'Requested registry access is not allowed'
  }

  It 'logs an entry that cannot be written and carries on' {
    Mock -CommandName Write-MaintenanceEventEntry -MockWith { Throw 'The event log is full.' }
    $Channel = New-Channel

    { Write-MaintenanceEvent -Channel $Channel -Kind 'runStarted' -Message 'a' } | Should -Not -Throw

    (Get-Content -LiteralPath $Channel.Log.Path -Raw) | Should -Match 'Event 1000 could not be written: The event log is full.'
  }

  It 'writes nothing while the event log is disabled' {
    $Channel = New-Channel -Enabled $False

    Write-MaintenanceEvent -Channel $Channel -Kind 'runStarted' -Message 'a'

    Should -Invoke -CommandName Test-MaintenanceEventSource -Times 0 -Exactly
    $script:Written | Should -HaveCount 0
  }
}

Describe 'Windows Event Log seams' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'cannot check or write events where the event log is not available' -Skip:$script:IsWindowsHost {
    { Test-MaintenanceEventSource -LogName 'Application' -Source 'Invoke-WsusMaintenance' } | Should -Throw
    { Write-MaintenanceEventEntry -Source 'Invoke-WsusMaintenance' -EventId 1000 -EntryType 'Information' -Message 'm' } | Should -Throw
  }

  It 'reports a source that does not exist as not registered' -Skip:(-not $script:IsWindowsHost) {
    Test-MaintenanceEventSource -LogName 'Application' -Source ('NoSuchSource{0}' -f [System.Guid]::NewGuid().ToString('N')) | Should -BeFalse
  }
}
