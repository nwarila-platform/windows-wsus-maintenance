#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-ErrorRecord' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'returns an error record with a known short id' {
    $Result = New-ErrorRecord `
      -Message 'The configuration document is missing.' `
      -ErrorId ([MaintenanceExitCode]::ConfigurationInvalid)

    $Result | Should -BeOfType ([System.Management.Automation.ErrorRecord])
    $Result.FullyQualifiedErrorId | Should -Be 'ConfigurationInvalid'
  }

  It 'preserves a supplied inner exception' {
    [System.Exception]$InnerException = [System.FormatException]::new('Bad JSON.')

    $Result = New-ErrorRecord `
      -Message 'The configuration document could not be parsed.' `
      -ErrorId ([MaintenanceExitCode]::ConfigurationInvalid) `
      -Exception $InnerException

    $Result.Exception.Message | Should -Be 'The configuration document could not be parsed.'
    $Result.Exception.InnerException | Should -Be $InnerException
  }

  It 'records the category and target object' {
    $Result = New-ErrorRecord `
      -Message 'Another run holds the lock.' `
      -ErrorId ([MaintenanceExitCode]::LockHeld) `
      -Category ([System.Management.Automation.ErrorCategory]::ResourceBusy) `
      -TargetObject 'Global\WsusMaintenance'

    $Result.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceBusy)
    $Result.TargetObject | Should -Be 'Global\WsusMaintenance'
  }

  It 'rejects unknown error ids' {
    {
      New-ErrorRecord `
        -Message 'Unknown failure.' `
        -ErrorId UnknownFailure
    } | Should -Throw
  }

  It 'can throw the error record as a terminating error' {
    {
      New-ErrorRecord `
        -Message 'Elevation is required.' `
        -ErrorId ([MaintenanceExitCode]::PreconditionFailed) `
        -IsFatal
    } | Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord'
  }
}
