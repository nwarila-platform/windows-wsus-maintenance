#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceRunRecord' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'records the run with completion now and a fractional duration' {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 1, 2, 0, 1).AddMilliseconds(500) }
    $Start = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)

    $Record = New-MaintenanceRunRecord -RunId 'RUN' -RunStart $Start -Stage @('Reindex') -DryRun $True -Deadline $Start.AddHours(4)

    $Record.RunId | Should -Be 'RUN'
    $Record.Stages | Should -Be @('Reindex')
    $Record.DryRun | Should -BeTrue
    $Record.StartedAt | Should -Be $Start
    $Record.CompletedAt | Should -Be ([System.DateTime]::new(2026, 11, 1, 2, 0, 1).AddMilliseconds(500))
    $Record.DurationSeconds | Should -Be 1.5
    $Record.Deadline | Should -Be $Start.AddHours(4)
    $Record.Artifacts | Should -BeNullOrEmpty
  }

  It 'never reports a negative duration' {
    Mock -CommandName Get-MaintenanceTime -MockWith { [System.DateTime]::new(2026, 11, 1, 1, 0, 0) }

    (New-MaintenanceRunRecord -RunId 'RUN' -RunStart ([System.DateTime]::new(2026, 11, 1, 2, 0, 0))).DurationSeconds | Should -Be 0
  }
}
