#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceRunResult' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'maps <Status> to exit code <ExitCode>' -ForEach @(
    @{ Status = 'Success'; ExitCode = 0 }
    @{ Status = 'Warning'; ExitCode = 2 }
    @{ Status = 'Error'; ExitCode = 1 }
  ) {
    $Result = New-MaintenanceRunResult -Status $Status

    $Result.Status | Should -Be $Status
    $Result.ExitCode | Should -Be $ExitCode
  }

  It 'carries the typed contract name and empty collections by default' {
    $Result = New-MaintenanceRunResult -Status 'Success'

    $Result.PSTypeNames[0] | Should -Be 'WsusMaintenance.RunResult'
    $Result.Stages | Should -HaveCount 0
    $Result.Notices | Should -HaveCount 0
    $Result.Validation | Should -BeNullOrEmpty
    $Result.GeneratedAtUtc.Kind | Should -Be ([System.DateTimeKind]::Utc)
  }

  It 'keeps supplied stages, notices and validation' {
    $Stage = [PSCustomObject]@{ Name = 'Reindex' }
    $Notice = [PSCustomObject]@{ Severity = 'Warning' }
    $Validation = [PSCustomObject]@{ IsValid = $True }

    $Result = New-MaintenanceRunResult -Status 'Warning' -Stage @($Stage) -Notice @($Notice) -Validation $Validation

    $Result.Stages[0].Name | Should -Be 'Reindex'
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Validation.IsValid | Should -BeTrue
  }

  It 'rejects an unknown status' {
    { New-MaintenanceRunResult -Status 'Unknown' } | Should -Throw
  }
}
