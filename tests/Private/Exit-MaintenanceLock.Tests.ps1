#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Exit-MaintenanceLock' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:New-FakeLock {
      Param ([System.Boolean]$FailRelease = $False)
      $Lock = [PSCustomObject]@{ Released = 0; Disposed = 0; FailRelease = $FailRelease }
      $Lock | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value {
        If ($this.FailRelease) { Throw 'Object synchronization method was called from an unsynchronized block of code.' }
        $this.Released++
      }
      $Lock | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }
      $Lock
    }
  }

  It 'releases and disposes the lock' {
    $Lock = New-FakeLock

    Exit-MaintenanceLock -Lock $Lock

    $Lock.Released | Should -Be 1
    $Lock.Disposed | Should -Be 1
  }

  It 'still disposes the lock when the release fails' {
    $Lock = New-FakeLock -FailRelease $True

    { Exit-MaintenanceLock -Lock $Lock } | Should -Not -Throw
    $Lock.Disposed | Should -Be 1
  }

  It 'ignores a null lock' {
    { Exit-MaintenanceLock -Lock $Null } | Should -Not -Throw
  }
}
