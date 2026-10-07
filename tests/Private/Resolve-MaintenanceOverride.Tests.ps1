#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Resolve-MaintenanceOverride' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/Configuration'

    Function script:New-Effective {
      ConvertTo-MaintenanceEffectiveConfiguration -Document (Read-MaintenanceConfiguration -Path (Join-Path -Path $script:FixtureRoot -ChildPath 'minimal-valid.json'))
    }
  }

  It 'runs every enabled stage with no overrides by default' {
    $Result = Resolve-MaintenanceOverride -Configuration (New-Effective)

    $Result.Stages | Should -HaveCount 0
    @($Result.PSObject.Properties.Name) | Should -Be @('Configuration', 'Stages', 'RemoveCustomIndexes', 'Overrides', 'Errors')
    $Result.RemoveCustomIndexes | Should -BeFalse
    $Result.Overrides | Should -HaveCount 0
    $Result.Errors | Should -HaveCount 0
  }

  It 'applies and records every one-run override' {
    $Result = Resolve-MaintenanceOverride `
      -Configuration (New-Effective) `
      -ConfigPath 'D:\m.json' `
      -DryRun `
      -ReportFolder 'D:\Reports' `
      -ReportFormat @('Html') `
      -Stage @('reindex') `
      -Verbosity 'Debug'

    $Result.Errors | Should -HaveCount 0
    $Result.Configuration.run.dryRun | Should -BeTrue
    $Result.Configuration.report.folder | Should -Be 'D:\Reports'
    $Result.Configuration.report.formats | Should -Be @('Html')
    $Result.Configuration.log.verbosity | Should -Be 'Debug'
    $Result.Stages | Should -Be @('Reindex')
    $Result.Overrides | Should -Be @(
      'configuration path = D:\m.json (-ConfigPath)'
      'stages = Reindex (-Stage)'
      'run.dryRun = true (-DryRun)'
      'report.folder = D:\Reports (-ReportFolder)'
      'report.formats = Html (-ReportFormat)'
      'log.verbosity = Debug (-Verbosity)'
    )
  }

  It 'resolves stage names to their canonical spelling' {
    $Result = Resolve-MaintenanceOverride -Configuration (New-Effective) -Stage @('reindex', 'Backup')

    $Result.Errors | Should -HaveCount 0
    $Result.Stages | Should -Be @('Reindex', 'Backup')
  }

  It 'runs only the custom-index stage, in its removal action, for -RemoveCustomIndexes' {
    $Result = Resolve-MaintenanceOverride -Configuration (New-Effective) -RemoveCustomIndexes

    $Result.Errors | Should -HaveCount 0
    $Result.Stages | Should -Be @('CustomIndexes')
    $Result.RemoveCustomIndexes | Should -BeTrue
    $Result.Overrides | Should -Be @('custom indexes = remove the ones this script created (-RemoveCustomIndexes)')
  }

  It 'keeps the listed stages for -RemoveCustomIndexes when they include the custom-index stage' {
    $Result = Resolve-MaintenanceOverride -Configuration (New-Effective) -RemoveCustomIndexes -Stage @('customindexes', 'Reindex')

    $Result.Errors | Should -HaveCount 0
    $Result.Stages | Should -Be @('CustomIndexes', 'Reindex')
  }

  It 'refuses -RemoveCustomIndexes with a stage list that leaves out the custom-index stage' {
    $Result = Resolve-MaintenanceOverride -Configuration (New-Effective) -RemoveCustomIndexes -Stage @('Reindex')

    $Result.Errors | Should -Be @('-RemoveCustomIndexes runs the CustomIndexes stage, so -Stage must include CustomIndexes when it is given.')
  }

  It 'refuses <Case>' -ForEach @(
    @{ Case = 'an unknown stage'; Splat = @{ Stage = @('Defrag') }; Message = "-Stage: 'Defrag' is not a stage name*" }
    @{ Case = 'a repeated stage'; Splat = @{ Stage = @('Backup', 'backup') }; Message = "-Stage: 'Backup' is listed more than once." }
    @{ Case = 'a relative report folder'; Splat = @{ ReportFolder = 'reports' }; Message = '-ReportFolder: must be an absolute Windows path*' }
    @{ Case = 'repeated report formats'; Splat = @{ ReportFormat = @('Text', 'Text') }; Message = '-ReportFormat: contains the duplicate entry*' }
  ) {
    $Effective = New-Effective
    $Result = Resolve-MaintenanceOverride -Configuration $Effective @Splat

    $Result.Errors | Should -HaveCount 1
    $Result.Errors[0] | Should -BeLike $Message
    $Effective.run.dryRun | Should -BeFalse
  }

  It 'only validates the options when the configuration itself was invalid' {
    $Result = Resolve-MaintenanceOverride -DryRun -Stage @('Backup')

    $Result.Errors | Should -HaveCount 0
    $Result.Configuration | Should -BeNullOrEmpty
    $Result.Overrides | Should -Be @('stages = Backup (-Stage)')
  }

  It 'accepts an explicit catalogue' {
    $Result = Resolve-MaintenanceOverride -Configuration (New-Effective) -ReportFolder 'D:\R' -Rule @(Get-MaintenanceConfigurationRule)

    $Result.Configuration.report.folder | Should -Be 'D:\R'
  }
}
