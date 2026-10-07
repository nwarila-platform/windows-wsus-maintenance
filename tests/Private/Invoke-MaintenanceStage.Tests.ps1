#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-MaintenanceStage' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Entry = [PSCustomObject]@{ Name = 'Reindex'; Order = 13; AltersDatabase = $False; Mode = 'Run'; Reason = 'enabled' }

    Function script:New-Context {
      Param ($Deadline = $Null)
      [PSCustomObject]@{ StageName = 'Reindex'; DryRun = $False; Configuration = $Null; Deadline = $Deadline; RunStart = [System.DateTime]::new(2026, 10, 6, 2, 0, 0) }
    }
  }

  BeforeEach {
    $script:Clock = [System.DateTime]::new(2026, 10, 6, 2, 0, 0)
    Mock -CommandName Get-MaintenanceTime -MockWith {
      $script:Clock = $script:Clock.AddSeconds(10)
      $script:Clock
    }
  }

  It 'records NotRun when the budget is used up before the stage starts' {
    $script:Ran = $False
    $Outcome = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context -Deadline ([System.DateTime]::new(2026, 10, 6, 2, 0, 0))) -Handler { $script:Ran = $True }

    $Outcome.Status | Should -Be 'NotRun'
    $Outcome.Reason | Should -Be 'time budget reached before the stage could start'
    $script:Ran | Should -BeFalse
  }

  It 'records Skipped when this build has no handler for the stage' {
    $Outcome = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler $Null

    $Outcome.Status | Should -Be 'Skipped'
    $Outcome.Reason | Should -Be 'not available in this release'
  }

  It 'passes the context and records a successful outcome' {
    $Outcome = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context -Deadline ([System.DateTime]::new(2026, 10, 6, 5, 0, 0))) -Handler {
      Param ($Context)
      [PSCustomObject]@{
        Counts  = @{ Indexes = 4; Stage = $Context.StageName }
        Message = 'Rebuilt 4 indexes.'
        Notices = @([PSCustomObject]@{ Severity = 'Information'; Message = 'Statistics updated.' }, $Null)
      }
    }

    $Outcome.Status | Should -Be 'Success'
    $Outcome.Reason | Should -Be 'enabled'
    $Outcome.Counts.Indexes | Should -Be 4
    $Outcome.Counts.Stage | Should -Be 'Reindex'
    $Outcome.Message | Should -Be 'Rebuilt 4 indexes.'
    $Outcome.Notices | Should -HaveCount 1
    $Outcome.StartedAt | Should -Be ([System.DateTime]::new(2026, 10, 6, 2, 0, 20))
    $Outcome.DurationSeconds | Should -Be 10
  }

  It 'takes the status the handler reports' {
    (Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler { [PSCustomObject]@{ Status = 'Warning' } }).Status | Should -Be 'Warning'
    (Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler { [PSCustomObject]@{ Status = 'Error' } }).Status | Should -Be 'Error'
  }

  It 'treats an unknown status, or no output at all, as success' {
    (Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler { [PSCustomObject]@{ Status = 'Great' } }).Status | Should -Be 'Success'
    (Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler { }).Status | Should -Be 'Success'
  }

  It 'catches a stage error and records the text and the time' {
    $Outcome = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler { Throw 'The SUSDB connection was lost.' }

    $Outcome.Status | Should -Be 'Error'
    $Outcome.Reason | Should -Be 'stage error'
    $Outcome.ErrorMessage | Should -Be 'The SUSDB connection was lost.'
    $Outcome.ErrorTime | Should -BeOfType ([System.DateTime])
  }

  It 'keeps the items the handler reports, without empty entries' {
    $Outcome = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Handler { [PSCustomObject]@{ Items = @('KB1', $Null, 'KB2') } }

    $Outcome.Items | Should -Be @('KB1', 'KB2')
  }

  Context 'run log' {
    BeforeEach {
      $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
    }

    It 'logs the start, the result, every item and the end with status and duration' {
      $Null = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Log $script:Log -Handler { [PSCustomObject]@{ Status = 'Warning'; Message = 'Rebuilt 2.'; Items = @('idx1', 'idx2') } }

      $Lines = @(Get-Content -LiteralPath $script:Log.Path)
      $Lines | Should -HaveCount 5
      $Lines[0] | Should -BeLike '*Information [[]RUN] Reindex: Stage started.'
      $Lines[1] | Should -BeLike '*Reindex: Result: Rebuilt 2.'
      $Lines[2] | Should -BeLike '*Reindex: Item: idx1'
      $Lines[3] | Should -BeLike '*Reindex: Item: idx2'
      $Lines[4] | Should -BeLike '*Warning     [[]RUN] Reindex: Stage finished: Warning in *.0 s.'
    }

    It 'logs a stage error with its time' {
      $Null = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Log $script:Log -Handler { Throw 'Lost.' }

      $Lines = @(Get-Content -LiteralPath $script:Log.Path)
      $Lines[1] | Should -BeLike '*Error       [[]RUN] Reindex: Stage error at 2026-10-06 02:0?:??: Lost.'
      $Lines[2] | Should -BeLike '*Reindex: Stage finished: Error in *'
    }

    It 'logs a stage that did not run or has no handler' {
      $Null = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context -Deadline ([System.DateTime]::new(2026, 10, 6, 2, 0, 0))) -Log $script:Log -Handler { }
      $Null = Invoke-MaintenanceStage -Stage $script:Entry -Context (New-Context) -Log $script:Log -Handler $Null

      $Lines = @(Get-Content -LiteralPath $script:Log.Path)
      $Lines[0] | Should -BeLike '*Warning     [[]RUN] Reindex: Stage not run: time budget reached before the stage could start.'
      $Lines[1] | Should -BeLike '*Reindex: Stage skipped: not available in this release.'
    }
  }
}
