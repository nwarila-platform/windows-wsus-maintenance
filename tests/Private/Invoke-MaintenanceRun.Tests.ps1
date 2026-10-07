#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-MaintenanceRun' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    # The backup gate is off unless a test sets it, so that stand-in stages run unconditionally.
    Function script:New-Configuration {
      Param ([System.String]$Extra = '', [System.String]$Gate = 'Off')
      $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\B", "gate": "' + $Gate + '" }' + $Extra + ' }'
      Get-FakeConfiguration -Json $Json
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

    $Run.Outcomes | Should -HaveCount 18
    $Run.Outcomes.Name | Should -Be @(Get-MaintenanceStageCatalog).Name
    $script:Invoked | Should -HaveCount 13
    $script:Invoked[0] | Should -Be 'Backup:False'
    $script:Invoked | Should -Contain 'SupersededDecline:False'
    $script:Invoked[-1] | Should -Be 'HealthChecks:False'
    @($Run.Outcomes | Where-Object -FilterScript { $PSItem.Status -eq 'Skipped' }).Name | Should -Be @('AcceleratedDecline', 'RuleDecline', 'ContentStaging', 'DeferredApproval', 'DeclinedDeletion')
    $Run.Notices | Should -HaveCount 0
    $Run.Plan | Should -HaveCount 18
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

    @($script:Contexts[0].PSObject.Properties.Name) | Should -Be @('StageName', 'DryRun', 'Configuration', 'Deadline', 'RunStart', 'Log', 'Server', 'RemoveCustomIndexes', 'Events')
    $script:Contexts[0].RemoveCustomIndexes | Should -BeFalse
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
    $Run.Outcomes | Should -HaveCount 18
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

  It 'passes the removal action for the custom indexes to the stages' {
    $script:Contexts = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Get-MaintenanceStageHandler -MockWith {
      {
        Param ($Context)
        $script:Contexts.Add($Context)
        [PSCustomObject]@{ Status = 'Success' }
      }
    }

    $Null = Invoke-Run -Configuration (New-Configuration) -Extra @{ Stage = @('CustomIndexes'); RemoveCustomIndexes = $True }

    $script:Contexts | Should -HaveCount 1
    $script:Contexts[0].RemoveCustomIndexes | Should -BeTrue
  }

  Context 'backup gate' {
    BeforeAll {
      $script:Altering = @(Get-MaintenanceStageCatalog | Where-Object -FilterScript { $PSItem.AltersDatabase }).Name
    }

    It 'skips every stage that alters SUSDB, with a High notice, when the gate is required and no backup is recent' {
      Mock -CommandName Test-BackupGate -MockWith { [PSCustomObject]@{ Satisfied = $False; Mode = 'Required'; Detail = 'no backup in this run and none recorded in the last 24 hour(s)' } }
      $Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath 'gate-closed') -RunId 'RUN' -Verbosity 'Information'

      $Run = Invoke-Run -Configuration (New-Configuration -Gate 'Required') -Extra @{ Log = $Log }

      ForEach ($Name In @('CustomIndexes', 'DeleteUpdateFix', 'ObsoleteUpdates', 'BuiltInCleanup', 'SyncHistory', 'StaleComputers')) {
        $Outcome = $Run.Outcomes | Where-Object -FilterScript { $PSItem.Name -eq $Name }
        $Outcome.Status | Should -Be 'Skipped' -Because $Name
        $Outcome.Reason | Should -Be 'skipped: no recent backup' -Because $Name
      }
      $script:Invoked | Should -Not -Contain 'ObsoleteUpdates:False'
      $script:Invoked | Should -Contain 'Backup:False'
      $script:Invoked | Should -Contain 'Reindex:False'
      $Run.Notices | Should -HaveCount 1
      $Run.Notices[0].Severity | Should -Be 'High'
      $Run.Notices[0].Message | Should -Be 'No recent SUSDB backup (no backup in this run and none recorded in the last 24 hour(s)); the stages that delete or alter SUSDB content are skipped (backup.gate is Required).'
      Should -Invoke -CommandName Test-BackupGate -Times 1 -Exactly
      (Get-Content -LiteralPath $Log.Path -Raw) | Should -Match 'Backup gate closed: no backup in this run'
      (Get-Content -LiteralPath $Log.Path -Raw) | Should -Match 'SyncHistory: Stage skipped: skipped: no recent backup'
    }

    It 'evaluates the gate after the backup stage, with what that stage reported' {
      $script:SeenOutcome = $Null
      Mock -CommandName Get-MaintenanceStageHandler -ParameterFilter { $Name -eq 'Backup' } -MockWith {
        { [PSCustomObject]@{ Status = 'Success'; Counts = [ordered]@{ Created = 1; WouldCreate = 0 } } }
      }
      Mock -CommandName Test-BackupGate -MockWith {
        $script:SeenOutcome = $Outcome
        [PSCustomObject]@{ Satisfied = $True; Mode = 'Required'; Detail = 'backup made by this run' }
      }
      $Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath 'gate-open') -RunId 'RUN' -Verbosity 'Information'

      $Run = Invoke-Run -Configuration (New-Configuration -Gate 'Required') -Extra @{ Log = $Log }

      @($script:SeenOutcome).Name | Should -Be @('Backup')
      $script:Invoked | Should -Contain 'ObsoleteUpdates:False'
      $Run.Notices | Should -HaveCount 0
      (Get-Content -LiteralPath $Log.Path -Raw) | Should -Match 'Backup gate open: backup made by this run\.'
    }

    It 'runs the altering stages with a Warning notice when the gate is advisory' {
      Mock -CommandName Test-BackupGate -MockWith { [PSCustomObject]@{ Satisfied = $False; Mode = 'Advisory'; Detail = 'no backup' } }

      $Run = Invoke-Run -Configuration (New-Configuration -Gate 'Advisory')

      $script:Invoked | Should -HaveCount 13
      $Run.Notices | Should -HaveCount 1
      $Run.Notices[0].Severity | Should -Be 'Warning'
      $Run.Notices[0].Message | Should -BeLike 'No recent SUSDB backup (no backup); the stages that delete or alter SUSDB content run anyway*'
    }

    It 'is not evaluated when it is off or when no altering stage runs' {
      Mock -CommandName Test-BackupGate -MockWith { [PSCustomObject]@{ Satisfied = $False; Mode = 'Required'; Detail = 'no backup' } }

      $Null = Invoke-Run -Configuration (New-Configuration)
      $Null = Invoke-Run -Configuration (New-Configuration -Gate 'Required') -Extra @{ Stage = @('Reindex') }

      Should -Invoke -CommandName Test-BackupGate -Times 0 -Exactly
    }

    It 'keeps declined-update deletion behind the gate when it is enabled' {
      Mock -CommandName Test-BackupGate -MockWith { [PSCustomObject]@{ Satisfied = $False; Mode = 'Required'; Detail = 'no backup' } }

      $Run = Invoke-Run -Configuration (New-Configuration -Gate 'Required' -Extra ', "declinedDeletion": { "enabled": true }')

      ($Run.Outcomes | Where-Object -FilterScript { $PSItem.Name -eq 'DeclinedDeletion' }).Reason | Should -Be 'skipped: no recent backup'
      $script:Invoked | Should -Contain 'SupersededDecline:False'
      $script:Invoked | Should -Not -Contain 'DeclinedDeletion:False'
    }

    It 'lists the stages it guards in the catalogue' {
      $script:Altering | Should -Be @('CustomIndexes', 'DeleteUpdateFix', 'DeclinedDeletion', 'ObsoleteUpdates', 'BuiltInCleanup', 'SyncHistory', 'StaleComputers')
    }
  }
}
