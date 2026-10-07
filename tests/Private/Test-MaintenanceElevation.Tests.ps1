#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:IsWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

Describe 'Test-MaintenanceElevation' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'reports a boolean on Windows' -Skip:(-not $script:IsWindowsHost) {
    Test-MaintenanceElevation | Should -BeOfType ([System.Boolean])
  }

  It 'throws where no Windows identity exists' -Skip:$script:IsWindowsHost {
    { Test-MaintenanceElevation } | Should -Throw
  }
}
