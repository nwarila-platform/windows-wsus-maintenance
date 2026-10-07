#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-WsusServerRole' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
  }

  It 'detects <Expected>' -ForEach @(
    @{ IsReplica = $False; FromMu = $True; Expected = 'TopTier'; Description = 'Top-tier server'; Upstream = 'Microsoft Update' }
    @{ IsReplica = $False; FromMu = $False; Expected = 'Autonomous'; Description = 'Autonomous downstream server'; Upstream = 'upstream.example, port 8531, TLS' }
    @{ IsReplica = $True; FromMu = $False; Expected = 'Replica'; Description = 'Replica downstream server'; Upstream = 'upstream.example, port 8531, TLS' }
  ) {
    $Role = Get-WsusServerRole -UpdateServer (New-FakeUpdateServer -IsReplica $IsReplica -SyncFromMicrosoftUpdate $FromMu)

    $Role.Tier | Should -Be $Expected
    $Role.IsReplica | Should -Be $IsReplica
    $Role.SyncFromMicrosoftUpdate | Should -Be $FromMu
    $Role.Description | Should -Be $Description
    $Role.Upstream | Should -Be $Upstream
    $Role.Version | Should -Be '10.0.20348.2700'
    $Role.Error | Should -BeNullOrEmpty
  }

  It 'describes an upstream reached without TLS' {
    (Get-WsusServerRole -UpdateServer (New-FakeUpdateServer -SyncFromMicrosoftUpdate $False -UpstreamPort 8530 -UpstreamUseSsl $False)).Upstream | Should -Be 'upstream.example, port 8530, no TLS'
  }

  It 'reports an unknown tier when the configuration cannot be read' {
    $Role = Get-WsusServerRole -UpdateServer (New-FakeUpdateServer -ConfigurationFails $True)

    $Role.Tier | Should -Be 'Unknown'
    $Role.Error | Should -Be 'The configuration could not be read.'
    $Role.Description | Should -Be 'not determined: The configuration could not be read.'
  }

  It 'never changes the replica setting' {
    $Server = New-FakeUpdateServer -IsReplica $True -SyncFromMicrosoftUpdate $False

    $Null = Get-WsusServerRole -UpdateServer $Server

    $Server.Configuration.IsReplicaServer | Should -BeTrue
    $Server.State.Saves | Should -Be 0
  }
}
