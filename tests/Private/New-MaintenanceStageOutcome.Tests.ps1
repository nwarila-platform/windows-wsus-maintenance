#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceStageOutcome' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Entry = [PSCustomObject]@{ Name = 'Reindex'; Order = 13; AltersDatabase = $False; Mode = 'Run'; Reason = 'enabled' }
  }

  It 'records a skipped stage with empty details' {
    $Outcome = New-MaintenanceStageOutcome -Stage $script:Entry -Status 'Skipped' -Reason 'disabled by configuration'

    $Outcome.PSTypeNames[0] | Should -Be 'WsusMaintenance.StageOutcome'
    $Outcome.Name | Should -Be 'Reindex'
    $Outcome.Order | Should -Be 13
    $Outcome.Status | Should -Be 'Skipped'
    $Outcome.Reason | Should -Be 'disabled by configuration'
    $Outcome.StartedAt | Should -BeNullOrEmpty
    $Outcome.DurationSeconds | Should -Be 0
    $Outcome.Notices | Should -HaveCount 0
    $Outcome.Items | Should -HaveCount 0
    $Outcome.ErrorMessage | Should -BeNullOrEmpty
  }

  It 'records every detail of a stage that ran' {
    $Started = [System.DateTime]::new(2026, 10, 6, 2, 0, 0)
    $Notice = [PSCustomObject]@{ Severity = 'Warning'; Message = 'm' }

    $Outcome = New-MaintenanceStageOutcome -Stage $script:Entry -Status 'Error' -Reason 'stage error' -StartedAt $Started -DurationSeconds 2.5 -Counts @{ Indexes = 3 } -Item @('idx1', 'idx2') -Message 'done' -Notice @($Notice) -ErrorMessage 'boom' -ErrorTime $Started

    $Outcome.StartedAt | Should -Be $Started
    $Outcome.DurationSeconds | Should -Be 2.5
    $Outcome.Counts.Indexes | Should -Be 3
    $Outcome.Message | Should -Be 'done'
    $Outcome.Items | Should -Be @('idx1', 'idx2')
    $Outcome.Notices[0].Message | Should -Be 'm'
    $Outcome.ErrorMessage | Should -Be 'boom'
    $Outcome.ErrorTime | Should -Be $Started
  }

  It 'refuses an unknown status' {
    { New-MaintenanceStageOutcome -Stage $script:Entry -Status 'Done' -Reason '' } | Should -Throw
  }
}
