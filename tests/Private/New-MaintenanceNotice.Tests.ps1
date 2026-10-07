#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceNotice' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'creates a typed notice stamped with the current time' {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 10, 6, 2, 0, 0) }

    $Notice = New-MaintenanceNotice -Severity 'High' -Message 'Guard breached.' -Stage 'StaleComputers'

    $Notice.PSTypeNames[0] | Should -Be 'WsusMaintenance.Notice'
    $Notice.Severity | Should -Be 'High'
    $Notice.Message | Should -Be 'Guard breached.'
    $Notice.Stage | Should -Be 'StaleComputers'
    $Notice.RaisedAt | Should -Be ([System.DateTime]::new(2026, 10, 6, 2, 0, 0))
    $Notice.Link | Should -BeNullOrEmpty
    $Notice.Command | Should -BeNullOrEmpty
  }

  It 'refuses an unknown severity' {
    { New-MaintenanceNotice -Severity 'Critical' -Message 'x' } | Should -Throw
  }

  It 'carries a link and a suggested command' {
    $Notice = New-MaintenanceNotice -Severity 'Warning' -Message 'Express files are on.' -Link 'https://learn.microsoft.com/x' -Command 'Get-WsusServer'

    $Notice.Link | Should -Be 'https://learn.microsoft.com/x'
    $Notice.Command | Should -Be 'Get-WsusServer'
  }
}
