#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Enter-MaintenanceLock' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'returns the lock when it is free' {
    $Fake = [PSCustomObject]@{ Name = 'lock' }
    Mock -CommandName New-MaintenanceLock -MockWith { $Fake }

    Enter-MaintenanceLock -Name 'Global\Test' | Should -Be $Fake
    Should -Invoke -CommandName New-MaintenanceLock -Times 1 -Exactly -ParameterFilter { $Name -eq 'Global\Test' }
  }

  It 'stops with LockHeld when another run holds the lock' {
    Mock -CommandName New-MaintenanceLock -MockWith { $Null }

    { Enter-MaintenanceLock -Name 'Global\Test' } |
      Should -Throw -ErrorId 'LockHeld,New-ErrorRecord' -ExpectedMessage '*Another maintenance run holds the lock*without touching WSUS or the database*'
  }

  It 'stops with PreconditionFailed when the lock cannot be created' {
    Mock -CommandName New-MaintenanceLock -MockWith { Throw 'Access to the named mutex is denied.' }

    { Enter-MaintenanceLock -Name 'Global\Test' } |
      Should -Throw -ErrorId 'PreconditionFailed,New-ErrorRecord' -ExpectedMessage '*could not be created*denied*'
  }
}
