#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceConfigurationCrossField' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Rules = @(Get-MaintenanceConfigurationRule)

    Function script:Test-CrossField {
      Param ([System.String]$Json, [System.String[]]$InvalidPath = @())
      @(Test-MaintenanceConfigurationCrossField -Document ($Json | ConvertFrom-Json) -InvalidPath $InvalidPath -Rule $script:Rules)
    }
  }

  It 'accepts a document whose related values agree' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\SUSDB" }, "syncHistory": { "retentionDays": 0 } }' | Should -HaveCount 0
  }

  It 'requires a backup destination while backup is enabled, and not otherwise' {
    Test-CrossField -Json '{ "syncHistory": { "retentionDays": 1 } }' |
      Should -Be @('backup.destination: is required when backup.enabled is true.')
    Test-CrossField -Json '{ "backup": { "enabled": false }, "syncHistory": { "retentionDays": 1 } }' | Should -HaveCount 0
  }

  It 'needs no sync-history retention in the document, because it has a default' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" } }' | Should -HaveCount 0
  }

  It 'requires classifications and an age for the accelerated policy when it is enabled' {
    $Errors = Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "declines": { "accelerated": { "enabled": true } } }'

    $Errors | Should -Be @(
      'declines.accelerated.classifications: is required when declines.accelerated.enabled is true.'
      'declines.accelerated.ageDays: is required when declines.accelerated.enabled is true.'
    )
  }

  It 'requires approval groups and a staging group while approval is enabled' {
    $Errors = Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "approval": { "enabled": true } }'

    $Errors | Should -Be @(
      'approval.groups: is required when approval.enabled is true.'
      'approval.staging.groupName: is required when approval.enabled and approval.staging.enabled are true.'
    )
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "approval": { "enabled": true, "groups": [ { "name": "Pilot", "delayDays": 7 } ], "staging": { "enabled": false } } }' | Should -HaveCount 0
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "approval": { "enabled": false } }' | Should -HaveCount 0
  }

  It 'refuses a staging group that is also an approval group' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "approval": { "enabled": true, "groups": [ { "name": "Pilot", "delayDays": 7 } ], "staging": { "groupName": "pilot" } } }' |
      Should -Be @("approval.staging.groupName: the staging group 'pilot' must not also be one of approval.groups.")
  }

  It 'requires a target group when stale computers are moved' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "staleComputers": { "action": "Move" } }' |
      Should -Be @('staleComputers.targetGroup: is required when staleComputers.action is Move.')
  }

  It 'refuses a zero-day stale threshold unless overridden' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "staleComputers": { "thresholdDays": 0 } }' |
      Should -BeLike '*zero days is refused*'
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "staleComputers": { "thresholdDays": 0, "override": true } }' |
      Should -HaveCount 0
  }

  It 'refuses classifications both included and excluded from declined-update deletion' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "declinedDeletion": { "includedClassifications": [ "Drivers", "Tools" ], "excludedClassifications": [ "Drivers" ] } }' |
      Should -Be @('declinedDeletion: classifications may not be both included and excluded: Drivers.')
  }

  It 'refuses duplicate event identifiers' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "eventLog": { "eventIds": { "stageError": 1000 } } }' |
      Should -Be @('eventLog.eventIds: each event identifier must be distinct; 1000 is used more than once.')
  }

  It 'refuses certificate warning tiers that do not descend' {
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "health": { "certificateExpiry": { "warningDays": [ 30, 30 ] } } }' |
      Should -BeLike '*strictly descending*'
  }

  It 'refuses a rule that names an undefined group, matching group names without regard to case' {
    $Json = '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "declines": { "groups": [ { "name": "Arch", "enabled": true } ], "rules": [ { "name": "A", "enabled": true, "group": "ARCH", "condition": {} }, { "name": "B", "enabled": true, "group": "Lang", "condition": {} }, { "name": "C", "enabled": true, "condition": {} } ] } }'

    Test-CrossField -Json $Json | Should -Be @("declines.rules[1].group: refers to 'Lang', which is not defined in declines.groups.")
  }

  It 'skips a rule whose inputs already failed validation' {
    Test-CrossField -Json '{ "syncHistory": { "retentionDays": 1 } }' -InvalidPath @('backup.destination') | Should -HaveCount 0
    Test-CrossField -Json '{ "backup": { "destination": "H:\\B" }, "syncHistory": { "retentionDays": 1 }, "staleComputers": { "thresholdDays": 0 } }' -InvalidPath @('staleComputers.override') | Should -HaveCount 0
  }
}
