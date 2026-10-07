#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Resolve-MaintenanceRunStatus' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:New-Outcome {
      Param ([System.String]$Status)
      [PSCustomObject]@{ Status = $Status }
    }

    Function script:New-Note {
      Param ([System.String]$Severity)
      [PSCustomObject]@{ Severity = $Severity }
    }
  }

  It 'is Success with nothing to report' {
    Resolve-MaintenanceRunStatus | Should -Be 'Success'
    Resolve-MaintenanceRunStatus -Stage @((New-Outcome 'Success'), (New-Outcome 'Skipped')) -Notice @(New-Note 'Information') | Should -Be 'Success'
  }

  It 'is Warning for <Case>' -ForEach @(
    @{ Case = 'a stage warning'; Stages = @('Warning'); Notices = @() }
    @{ Case = 'a stage the budget stopped'; Stages = @('NotRun'); Notices = @() }
    @{ Case = 'a warning notice'; Stages = @('Success'); Notices = @('Warning') }
    @{ Case = 'a high notice'; Stages = @(); Notices = @('High') }
  ) {
    $Outcomes = @($Stages | ForEach-Object -Process { New-Outcome $PSItem })
    $Notes = @($Notices | ForEach-Object -Process { New-Note $PSItem })

    Resolve-MaintenanceRunStatus -Stage $Outcomes -Notice $Notes | Should -Be 'Warning'
  }

  It 'is Error for a stage error or an error notice, whatever else happened' {
    Resolve-MaintenanceRunStatus -Stage @((New-Outcome 'Warning'), (New-Outcome 'Error')) | Should -Be 'Error'
    Resolve-MaintenanceRunStatus -Stage @(New-Outcome 'Success') -Notice @((New-Note 'High'), (New-Note 'Error')) | Should -Be 'Error'
  }
}
