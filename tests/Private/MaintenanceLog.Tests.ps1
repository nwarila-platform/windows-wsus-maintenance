#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Run log' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:Get-LogLine {
      Param ($Log)
      @(Get-Content -LiteralPath $Log.Path)
    }
  }

  BeforeEach {
    $Script:MaintenanceSecret.Clear()
    $script:Clock = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Clock }
    $script:Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
  }

  Context 'New-MaintenanceLog' {
    It 'creates an empty log file named after the run identifier' {
      $Log = New-MaintenanceLog -Folder $script:Folder -RunId '20261101-020000-0a1b2c3d' -Verbosity 'Information'

      $Log.Error | Should -BeNullOrEmpty
      $Log.Path | Should -Be (Join-Path -Path $script:Folder -ChildPath 'WsusMaintenance-20261101-020000-0a1b2c3d.log')
      (Get-Item -LiteralPath $Log.Path).Length | Should -Be 0
      $Log.Threshold | Should -Be 3
      $Log.WriteErrors | Should -Be 0
    }

    It 'reports a log folder that cannot be written' {
      $File = Join-Path -Path $TestDrive -ChildPath 'not-a-folder'
      Set-Content -LiteralPath $File -Value 'x'

      $Log = New-MaintenanceLog -Folder (Join-Path -Path $File -ChildPath 'logs') -RunId 'r' -Verbosity 'Information'

      $Log.Path | Should -BeNullOrEmpty
      $Log.Error | Should -BeLike "The log folder '*logs' cannot be written: *"
    }

    It 'reports a log file that cannot be created' {
      $Log = New-MaintenanceLog -Folder $script:Folder -RunId 'missing-folder/run' -Verbosity 'Information'

      $Log.Path | Should -BeNullOrEmpty
      $Log.Error | Should -BeLike "The log folder '*' cannot be written: *"
    }
  }

  Context 'Write-MaintenanceLog' {
    It 'writes one line with time, level, run identifier, stage and message' {
      $Log = New-MaintenanceLog -Folder $script:Folder -RunId 'RUN1' -Verbosity 'Information'

      Write-MaintenanceLog -Log $Log -Level 'Warning' -Stage 'Reindex' -Message "two`r`nlines"
      Write-MaintenanceLog -Log $Log -Level 'Information' -Message 'run level'

      $Lines = Get-LogLine -Log $Log
      $Lines | Should -HaveCount 2
      $Lines[0] | Should -Match '^2026-11-01T02:00:00\.000[+-]\d{2}:\d{2} Warning     \[RUN1\] Reindex: two / lines$'
      $Lines[1] | Should -Match '\[RUN1\] run level$'
    }

    It 'skips entries below the verbosity' {
      $Log = New-MaintenanceLog -Folder $script:Folder -RunId 'RUN2' -Verbosity 'Warning'

      Write-MaintenanceLog -Log $Log -Level 'Information' -Message 'skipped'
      Write-MaintenanceLog -Log $Log -Level 'Error' -Message 'kept'

      Get-LogLine -Log $Log | Should -HaveCount 1
    }

    It 'removes registered secrets from every line' {
      Register-MaintenanceSecret -Value 'hunter2'
      $Log = New-MaintenanceLog -Folder $script:Folder -RunId 'RUN3' -Verbosity 'Debug'

      Write-MaintenanceLog -Log $Log -Level 'Debug' -Message 'secret is hunter2'

      (Get-Content -LiteralPath $Log.Path -Raw) | Should -Not -Match 'hunter2'
    }

    It 'does nothing without a usable log' {
      { Write-MaintenanceLog -Log $Null -Level 'Error' -Message 'x' } | Should -Not -Throw
      { Write-MaintenanceLog -Log ([PSCustomObject]@{ Path = ''; RunId = 'r'; Threshold = 5; WriteErrors = 0 }) -Level 'Error' -Message 'x' } | Should -Not -Throw
    }

    It 'counts an entry that cannot be written and carries on' {
      $Log = [PSCustomObject]@{ Path = (Join-Path -Path $TestDrive -ChildPath 'gone/x.log'); RunId = 'r'; Threshold = 5; WriteErrors = 0 }

      Write-MaintenanceLog -Log $Log -Level 'Error' -Message 'x'

      $Log.WriteErrors | Should -Be 1
    }
  }

  Context 'Write-MaintenanceProgress' {
    It 'logs once per batch and always for the last item, with the elapsed time' {
      $Log = New-MaintenanceLog -Folder $script:Folder -RunId 'RUN4' -Verbosity 'Information'
      $Start = $script:Clock

      For ($Position = 1; $Position -le 5; $Position++) {
        $script:Clock = $Start.AddSeconds($Position * 1.5)
        Write-MaintenanceProgress -Log $Log -Stage 'ObsoleteUpdates' -Position $Position -Total 5 -Item ('U{0}' -f $Position) -StartedAt $Start -BatchSize 2
      }

      $Lines = Get-LogLine -Log $Log
      $Lines | Should -HaveCount 3
      $Lines[0] | Should -BeLike '*ObsoleteUpdates: Progress 2 of 5: U2 (3.0 s elapsed).'
      $Lines[1] | Should -BeLike '*Progress 4 of 5: U4 (6.0 s elapsed).'
      $Lines[2] | Should -BeLike '*Progress 5 of 5: U5 (7.5 s elapsed).'
    }
  }
}
