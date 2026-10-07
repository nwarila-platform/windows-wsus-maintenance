#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Get-MaintenanceConfigurationRule' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Rules = @(Get-MaintenanceConfigurationRule)

    Function script:Get-Rule {
      Param ([System.String]$Path)
      $script:Rules | Where-Object -FilterScript { $PSItem.Path -ceq $Path }
    }
  }

  It 'defines each path once, with a known type and a description' {
    @($script:Rules.Path | Sort-Object -Unique) | Should -HaveCount $script:Rules.Count
    ForEach ($Rule In $script:Rules) {
      $Rule.Type | Should -BeIn @('Boolean', 'Integer', 'String', 'Path', 'StringArray', 'IntegerArray', 'IndexArray', 'GroupArray', 'RuleArray', 'ApprovalGroupArray')
      $Rule.Description | Should -Not -BeNullOrEmpty
    }
  }

  It 'requires only the schema version' {
    @($script:Rules | Where-Object -FilterScript { $PSItem.Required }).Path | Should -Be @('schemaVersion')
  }

  It 'gives every non-required key a default that passes its own rule' {
    ForEach ($Rule In @($script:Rules | Where-Object -FilterScript { -not $PSItem.Required })) {
      $Rule.HasDefault | Should -BeTrue -Because $Rule.Path
      @(Test-MaintenanceConfigurationValue -Path $Rule.Path -Rule $Rule -Value $Rule.Default) | Should -HaveCount 0 -Because $Rule.Path
    }
  }

  It 'gives every path rule the shared path pattern' {
    ForEach ($Rule In @($script:Rules | Where-Object -FilterScript { $PSItem.Type -eq 'Path' })) {
      $Rule.Pattern | Should -Not -BeNullOrEmpty
    }
  }

  It 'carries the decided default <Path> = <Expected>' -ForEach @(
    @{ Path = 'backup.minimumKept'; Expected = 7 }
    @{ Path = 'backup.maximumAgeDays'; Expected = 7 }
    @{ Path = 'backup.freeSpaceMarginPercent'; Expected = 20 }
    @{ Path = 'backup.gate'; Expected = 'Required' }
    @{ Path = 'backup.freshnessHours'; Expected = 24 }
    @{ Path = 'backup.sameDay'; Expected = 'Replace' }
    @{ Path = 'run.maxDurationMinutes'; Expected = 240 }
    @{ Path = 'run.connectionTimeoutSeconds'; Expected = 30 }
    @{ Path = 'syncGuard.maxAttempts'; Expected = 3 }
    @{ Path = 'builtInCleanup.obsoleteComputers'; Expected = $False }
    @{ Path = 'builtInCleanup.timeoutRetries'; Expected = 2 }
    @{ Path = 'declines.superseded.ageDays'; Expected = 90 }
    @{ Path = 'declines.superseded.includeApproved'; Expected = $True }
    @{ Path = 'declines.accelerated.enabled'; Expected = $False }
    @{ Path = 'declinedDeletion.enabled'; Expected = $False }
    @{ Path = 'staleComputers.thresholdDays'; Expected = 90 }
    @{ Path = 'staleComputers.guardPercent'; Expected = 10 }
    @{ Path = 'staleComputers.guardCount'; Expected = 50 }
    @{ Path = 'iisLogs.maxAgeDays'; Expected = 90 }
    @{ Path = 'syncHistory.retentionDays'; Expected = 90 }
    @{ Path = 'health.supersededCount.threshold'; Expected = 1500 }
    @{ Path = 'health.processorCount.minimum'; Expected = 4 }
    @{ Path = 'configuration.unknownKeyPolicy'; Expected = 'Error' }
    @{ Path = 'eventLog.source'; Expected = 'Invoke-WsusMaintenance' }
    @{ Path = 'eventLog.eventIds.configurationInvalid'; Expected = 1300 }
  ) {
    (Get-Rule -Path $Path).Default | Should -Be $Expected
  }

  It 'leaves deployment-specific values without a default' {
    (Get-Rule -Path 'backup.destination').Default | Should -BeNullOrEmpty
    (Get-Rule -Path 'discovery.sqlInstance').Default | Should -BeNullOrEmpty
  }

  It 'has no calendar, cadence or run-state keys' {
    @($script:Rules | Where-Object -FilterScript { $PSItem.Path -like 'schedule.*' -or $PSItem.Path -like 'state.*' }) | Should -HaveCount 0
  }

  It 'keeps the certificate warning tiers descending' {
    (Get-Rule -Path 'health.certificateExpiry.warningDays').Default | Should -Be @(60, 30, 14, 7)
  }
}
