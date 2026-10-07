#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-MaintenanceRun' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:New-Configuration {
      Param ([System.String]$Extra = '')
      $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\B" }' + $Extra + ' }'
      ConvertTo-MaintenanceEffectiveConfiguration -Document ($Json | ConvertFrom-Json)
    }

    Function script:Invoke-Run {
      Param ($Configuration, [System.Collections.Hashtable]$Extra = @{})
      $Splat = @{
        Configuration = $Configuration
        RunStart      = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
      }
      ForEach ($Key In $Extra.Keys) {
        $Splat[$Key] = $Extra[$Key]
      }
      Invoke-MaintenanceRun @Splat
    }
  }

  BeforeEach {
    $script:Invoked = [System.Collections.Generic.List[System.String]]::new()
    $script:Clock = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Clock }
    Mock -CommandName Get-MaintenanceStageHandler -MockWith {
      {
        Param ($Context)
        $script:Invoked.Add(('{0}:{1}' -f $Context.StageName, $Context.DryRun))
        [PSCustomObject]@{ Status = 'Success' }
      }
    }
  }

  It 'runs every enabled stage in catalogue order' {
    $Run = Invoke-Run -Configuration (New-Configuration)

    $Run.Outcomes | Should -HaveCount 16
    $Run.Outcomes.Name | Should -Be @(Get-MaintenanceStageCatalog).Name
    $script:Invoked | Should -HaveCount 13
    $script:Invoked[0] | Should -Be 'Backup:False'
    $script:Invoked | Should -Contain 'SupersededDecline:False'
    $script:Invoked[-1] | Should -Be 'HealthChecks:False'
    @($Run.Outcomes | Where-Object -FilterScript { $PSItem.Status -eq 'Skipped' }).Name | Should -Be @('AcceleratedDecline', 'RuleDecline', 'DeclinedDeletion')
    $Run.Notices | Should -HaveCount 0
    $Run.Plan | Should -HaveCount 16
  }

  It 'runs the same stages on any day' {
    $Run = Invoke-Run -Configuration (New-Configuration) -Extra @{ RunStart = [System.DateTime]::new(2026, 11, 17, 2, 0, 0) }

    $script:Invoked | Should -HaveCount 13
    $Run.Deadline | Should -Be ([System.DateTime]::new(2026, 11, 17, 6, 0, 0))
  }

  It 'passes a context without cadence to each handler' {
    $script:Contexts = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Get-MaintenanceStageHandler -MockWith {
      {
        Param ($Context)
        $script:Contexts.Add($Context)
        [PSCustomObject]@{ Status = 'Success' }
      }
    }

    $Null = Invoke-Run -Configuration (New-Configuration)

    @($script:Contexts[0].PSObject.Properties.Name) | Should -Be @('StageName', 'DryRun', 'Configuration', 'Deadline', 'RunStart', 'Log', 'Server')
  }

  It 'collects the notices stages raise into the run notices' {
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'HealthChecks' } -MockWith {
      { [PSCustomObject]@{ Status = 'Warning'; Notices = @([PSCustomObject]@{ Severity = 'High'; Message = 'Certificate expires in 14 days.'; Stage = 'HealthChecks' }) } }
    }

    $Run = Invoke-Run -Configuration (New-Configuration)

    $Run.Notices | Should -HaveCount 1
    $Run.Notices[0].Message | Should -Be 'Certificate expires in 14 days.'
    Resolve-MaintenanceRunStatus -Stage $Run.Outcomes -Notice $Run.Notices | Should -Be 'Warning'
  }

  It 'keeps running the other stages after a stage error' {
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'ObsoleteUpdates' } -MockWith { { Throw 'Injected failure.' } }

    $Run = Invoke-Run -Configuration (New-Configuration)
    $Failed = $Run.Outcomes | Where-Object -FilterScript { $PSItem.Name -eq 'ObsoleteUpdates' }

    $Failed.Status | Should -Be 'Error'
    $Failed.ErrorMessage | Should -Be 'Injected failure.'
    $script:Invoked | Should -Contain 'BuiltInCleanup:False'
    $script:Invoked | Should -Contain 'HealthChecks:False'
    Resolve-MaintenanceRunStatus -Stage $Run.Outcomes -Notice $Run.Notices | Should -Be 'Error'
  }

  It 'starts no stage after the budget runs out and says the rest will run next time' {
    $Configuration = New-Configuration -Extra ', "run": { "maxDurationMinutes": 1 }'
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'Backup' } -MockWith {
      {
        $script:Clock = $script:Clock.AddMinutes(5)
        [PSCustomObject]@{ Status = 'Success' }
      }
    }

    $Run = Invoke-Run -Configuration $Configuration

    ($Run.Outcomes | Where-Object -FilterScript { $PSItem.Name -eq 'Backup' }).Status | Should -Be 'Success'
    @($Run.Outcomes | Where-Object -FilterScript { $PSItem.Status -eq 'NotRun' }) | Should -HaveCount 12
    $Run.Notices | Should -HaveCount 1
    $Run.Notices[0].Severity | Should -Be 'Warning'
    $Run.Notices[0].Message | Should -BeLike 'Time budget of 1 minute(s) reached; 12 stage(s) did not run and will run next time: CustomIndexes, *HealthChecks.'
    $Run.Deadline | Should -Be ([System.DateTime]::new(2026, 11, 1, 2, 1, 0))
  }

  It 'has no deadline when the budget is unlimited' {
    $Run = Invoke-Run -Configuration (New-Configuration -Extra ', "run": { "maxDurationMinutes": 0 }')

    $Run.Deadline | Should -BeNullOrEmpty
    $script:Invoked | Should -HaveCount 13
  }

  It 'passes the dry-run flag to stages' {
    $Run = Invoke-Run -Configuration (New-Configuration -Extra ', "run": { "dryRun": true }')

    $script:Invoked | Should -Contain 'Reindex:True'
    $Run.DryRun | Should -BeTrue
  }

  It 'runs only the stages listed with -Stage' {
    $Run = Invoke-Run -Configuration (New-Configuration) -Extra @{ Stage = @('Reindex') }

    $script:Invoked | Should -Be @('Reindex:False')
    $Run.Outcomes | Should -HaveCount 16
  }

  It 'logs skipped stages and passes the log to the stages' {
    $Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath 'run-log') -RunId 'RUN' -Verbosity 'Information'
    $script:SeenLog = $Null
    Mock -CommandName Get-MaintenanceStageHandler -MockWith {
      {
        Param ($Context)
        $script:SeenLog = $Context.Log
        [PSCustomObject]@{ Status = 'Success' }
      }
    }

    $Null = Invoke-Run -Configuration (New-Configuration) -Extra @{ Log = $Log; Stage = @('Reindex') }

    $script:SeenLog | Should -Be $Log
    $Lines = @(Get-Content -LiteralPath $Log.Path)
    @($Lines | Where-Object -FilterScript { $PSItem -like '*Backup: Stage skipped: not listed with -Stage.' }) | Should -HaveCount 1
    @($Lines | Where-Object -FilterScript { $PSItem -like '*Reindex: Stage started.' }) | Should -HaveCount 1
  }

  It 'gates the plan with the server facts and warns about missing permissions before the first stage' {
    $Server = [PSCustomObject]@{ Tier = 'Replica'; Permission = [PSCustomObject]@{ MissingByStage = @{ Backup = @('BACKUP DATABASE') } } }
    $script:SeenServer = $Null
    Mock -CommandName Get-MaintenanceStageHandler -MockWith {
      {
        Param ($Context)
        $script:SeenServer = $Context.Server
        [PSCustomObject]@{ Status = 'Success' }
      }
    }

    $Run = Invoke-Run -Configuration (New-Configuration) -Extra @{ Server = $Server }

    ($Run.Outcomes | Where-Object -FilterScript { $PSItem.Name -eq 'Backup' }).Reason | Should -Be 'skipped: missing permission: BACKUP DATABASE'
    ($Run.Outcomes | Where-Object -FilterScript { $PSItem.Name -eq 'SupersededDecline' }).Reason | Should -Be 'skipped: replica'
    $Run.Notices | Should -HaveCount 1
    $Run.Notices[0].Severity | Should -Be 'Warning'
    $Run.Notices[0].Stage | Should -Be 'Backup'
    $Run.Notices[0].Message | Should -Be 'Stage Backup is skipped because the run identity lacks BACKUP DATABASE in SUSDB.'
    $Run.Notices[0].RaisedAt | Should -Be ([System.DateTime]::new(2026, 11, 1, 2, 0, 0))
    $script:SeenServer | Should -Be $Server
  }

  It 'returns the outcomes gathered so far and an error notice after an unexpected failure' {
    # The handler lookup runs outside the stage's error boundary, so a failure there is unexpected.
    Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'SyncHistory' } -MockWith { Throw 'Unexpected engine failure.' }

    $Run = Invoke-Run -Configuration (New-Configuration)

    $Run.Outcomes[-1].Name | Should -Be 'BuiltInCleanup'
    $Run.Notices[-1].Severity | Should -Be 'Error'
    $Run.Notices[-1].Message | Should -Be 'The run stopped early because of an unexpected error: Unexpected engine failure.'
  }
}
