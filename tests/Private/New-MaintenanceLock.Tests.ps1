#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'New-MaintenanceLock' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'takes a free lock and lets it be released' {
    $Name = 'Global\WsusMaintenanceTest-{0}' -f [System.Guid]::NewGuid().ToString('N')
    $Lock = New-MaintenanceLock -Name $Name

    $Lock | Should -BeOfType ([System.Threading.Mutex])
    { Exit-MaintenanceLock -Lock $Lock } | Should -Not -Throw
  }

  It 'returns nothing while another holder owns the lock' {
    $Name = 'Global\WsusMaintenanceTest-{0}' -f [System.Guid]::NewGuid().ToString('N')
    $Holder = [System.Management.Automation.PowerShell]::Create()
    [void]$Holder.AddScript({
        Param ($LockName)
        $Mutex = [System.Threading.Mutex]::new($False, $LockName)
        [void]$Mutex.WaitOne()
        Start-Sleep -Seconds 5
        $Mutex.ReleaseMutex()
        $Mutex.Dispose()
      }).AddArgument($Name)
    $Handle = $Holder.BeginInvoke()

    Try {
      $Deadline = [System.DateTime]::UtcNow.AddSeconds(3)
      $Lock = $Null
      Do {
        Start-Sleep -Milliseconds 100
        $Probe = [System.Threading.Mutex]::new($False, $Name)
        $Taken = $Probe.WaitOne(0)
        If ($Taken) {
          $Probe.ReleaseMutex()
        }
        $Probe.Dispose()
      } While ($Taken -and [System.DateTime]::UtcNow -lt $Deadline)

      $Lock = New-MaintenanceLock -Name $Name
      $Lock | Should -BeNullOrEmpty
    } Finally {
      [void]$Holder.EndInvoke($Handle)
      $Holder.Dispose()
    }
  }
}
