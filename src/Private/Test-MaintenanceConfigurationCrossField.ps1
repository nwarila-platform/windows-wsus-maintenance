#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceConfigurationCrossField.Descending'   = '{0}: tiers must be strictly descending (got {1}).'
  'Test-MaintenanceConfigurationCrossField.DuplicateId'  = 'eventLog.eventIds: each event identifier must be distinct; {0} is used more than once.'
  'Test-MaintenanceConfigurationCrossField.Overlap'      = 'declinedDeletion: classifications may not be both included and excluded: {0}.'
  'Test-MaintenanceConfigurationCrossField.RequiredWhen' = '{0}: is required when {1}.'
  'Test-MaintenanceConfigurationCrossField.StagingGroup' = "approval.staging.groupName: the staging group '{0}' must not also be one of approval.groups."
  'Test-MaintenanceConfigurationCrossField.UnknownGroup' = "declines.rules[{0}].group: refers to '{1}', which is not defined in declines.groups."
  'Test-MaintenanceConfigurationCrossField.ZeroDays'     = 'staleComputers.thresholdDays: zero days is refused unless staleComputers.override is true.'
}

Function Test-MaintenanceConfigurationCrossField {
  <#
    .SYNOPSIS
        Applies the rules that relate one configuration value to another.

    .DESCRIPTION
        Checks the conditions no single value can express: a value that becomes
        required when a feature is enabled, a zero-day stale-computer threshold without
        the override, classifications both included and excluded from declined-update
        deletion, duplicate event identifiers, certificate warning tiers that do not
        descend, decline rules that name an undefined group, approval enabled without a
        group or without a staging group, and a staging group that is also an approval
        group. Missing values take
        their catalogue default. A rule is skipped when one of its inputs already failed
        validation, so a single mistake is reported once.

    .PARAMETER Document
        Parsed configuration document.

    .PARAMETER InvalidPath
        Paths whose values already failed validation.

    .PARAMETER Rule
        The configuration catalogue.

    .EXAMPLE
        Test-MaintenanceConfigurationCrossField -Document $Document -Rule $Rules -InvalidPath @()

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceconfigurationcrossfield',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Document,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $InvalidPath = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject[]]
    $Rule
  )

  Write-Debug -Message:'[Test-MaintenanceConfigurationCrossField] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.Collections.Hashtable]$Private:Effective = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:GroupNames = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:Invalid = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:Seen = $Null
  [PSCustomObject]$Private:Lookup = $Null
  [System.Collections.Generic.List[System.String]]$Private:Overlap = $Null
  [System.Object[]]$Private:Rules = @()
  [System.Int32]$Private:Index = 0
  [System.Object[]]$Private:Tiers = @()
  [System.String[]]$Private:Result = @()
  [System.String]$Private:StagingName = [System.String]::Empty

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $Invalid = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
  ForEach ($Path In $InvalidPath) {
    [void]$Invalid.Add($Path)
  }

  # Effective value of every catalogue path: the document's value, or the default.
  $Effective = @{}
  ForEach ($Entry In $Rule) {
    $Lookup = Get-MaintenanceDocumentValue -Document:$Document -Path:$Entry.Path
    If ($Lookup.Found -eq $True) {
      $Effective[$Entry.Path] = $Lookup.Value
    } Else {
      $Effective[$Entry.Path] = $Entry.Default
    }
  }

  If (($Invalid.Contains('backup.enabled') -eq $False) -and ($Effective['backup.enabled'] -eq $True) -and ($Null -eq $Effective['backup.destination']) -and ($Invalid.Contains('backup.destination') -eq $False)) {
    $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.RequiredWhen'] -f 'backup.destination', 'backup.enabled is true'))
  }

  If (($Invalid.Contains('declines.accelerated.enabled') -eq $False) -and ($Effective['declines.accelerated.enabled'] -eq $True)) {
    If (($Invalid.Contains('declines.accelerated.classifications') -eq $False) -and (@($Effective['declines.accelerated.classifications']).Count -eq 0)) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.RequiredWhen'] -f 'declines.accelerated.classifications', 'declines.accelerated.enabled is true'))
    }

    If (($Invalid.Contains('declines.accelerated.ageDays') -eq $False) -and ($Null -eq $Effective['declines.accelerated.ageDays'])) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.RequiredWhen'] -f 'declines.accelerated.ageDays', 'declines.accelerated.enabled is true'))
    }
  }

  If (($Invalid.Contains('staleComputers.action') -eq $False) -and ($Effective['staleComputers.action'] -ceq 'Move') -and ($Null -eq $Effective['staleComputers.targetGroup']) -and ($Invalid.Contains('staleComputers.targetGroup') -eq $False)) {
    $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.RequiredWhen'] -f 'staleComputers.targetGroup', 'staleComputers.action is Move'))
  }

  If (($Invalid.Contains('staleComputers.thresholdDays') -eq $False) -and ($Invalid.Contains('staleComputers.override') -eq $False) -and ($Effective['staleComputers.thresholdDays'] -eq 0) -and ($Effective['staleComputers.override'] -ne $True)) {
    $Errors.Add($Script:Message['Test-MaintenanceConfigurationCrossField.ZeroDays'])
  }

  If (($Invalid.Contains('declinedDeletion.includedClassifications') -eq $False) -and ($Invalid.Contains('declinedDeletion.excludedClassifications') -eq $False)) {
    $Overlap = [System.Collections.Generic.List[System.String]]::new()
    ForEach ($Classification In @($Effective['declinedDeletion.includedClassifications'] | Where-Object -FilterScript { $Null -ne $PSItem })) {
      If (@($Effective['declinedDeletion.excludedClassifications']) -contains $Classification) {
        $Overlap.Add([System.String]$Classification)
      }
    }

    If ($Overlap.Count -gt 0) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.Overlap'] -f ($Overlap -join ', ')))
    }
  }

  $Seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
  ForEach ($Entry In @($Rule | Where-Object -FilterScript { $PSItem.Path.StartsWith('eventLog.eventIds.', [System.StringComparison]::Ordinal) })) {
    If (($Invalid.Contains($Entry.Path) -eq $False) -and ($Seen.Add([System.String]$Effective[$Entry.Path]) -eq $False)) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.DuplicateId'] -f $Effective[$Entry.Path]))
    }
  }

  If ($Invalid.Contains('health.certificateExpiry.warningDays') -eq $False) {
    $Tiers = @($Effective['health.certificateExpiry.warningDays'] | Where-Object -FilterScript { $Null -ne $PSItem })
    For ($Index = 1; $Index -lt $Tiers.Count; $Index++) {
      If ($Tiers[$Index] -ge $Tiers[$Index - 1]) {
        $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.Descending'] -f 'health.certificateExpiry.warningDays', (ConvertTo-MaintenanceDisplayValue -Value:$Tiers)))
        Break
      }
    }
  }

  If (($Invalid.Contains('approval.enabled') -eq $False) -and ($Effective['approval.enabled'] -eq $True)) {
    If (($Invalid.Contains('approval.groups') -eq $False) -and (@($Effective['approval.groups'] | Where-Object -FilterScript { $Null -ne $PSItem }).Count -eq 0)) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.RequiredWhen'] -f 'approval.groups', 'approval.enabled is true'))
    }

    If (($Invalid.Contains('approval.staging.enabled') -eq $False) -and ($Effective['approval.staging.enabled'] -eq $True) -and ($Invalid.Contains('approval.staging.groupName') -eq $False) -and ($Null -eq $Effective['approval.staging.groupName'])) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.RequiredWhen'] -f 'approval.staging.groupName', 'approval.enabled and approval.staging.enabled are true'))
    }
  }

  If (($Invalid.Contains('approval.groups') -eq $False) -and ($Invalid.Contains('approval.staging.groupName') -eq $False) -and ($Null -ne $Effective['approval.staging.groupName'])) {
    $StagingName = [System.String]$Effective['approval.staging.groupName']
    ForEach ($Group In @($Effective['approval.groups'] | Where-Object -FilterScript { $Null -ne $PSItem })) {
      If ([System.String]::Equals([System.String]$Group.name, $StagingName, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
        $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.StagingGroup'] -f $StagingName))
      }
    }
  }

  If (($Invalid.Contains('declines.rules') -eq $False) -and ($Invalid.Contains('declines.groups') -eq $False)) {
    $GroupNames = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    ForEach ($Group In @($Effective['declines.groups'] | Where-Object -FilterScript { $Null -ne $PSItem })) {
      [void]$GroupNames.Add([System.String]$Group.name)
    }

    $Rules = @($Effective['declines.rules'] | Where-Object -FilterScript { $Null -ne $PSItem })
    For ($Index = 0; $Index -lt $Rules.Count; $Index++) {
      If (($Null -ne $Rules[$Index].PSObject.Properties['group']) -and ($GroupNames.Contains([System.String]$Rules[$Index].group) -eq $False)) {
        $Errors.Add(($Script:Message['Test-MaintenanceConfigurationCrossField.UnknownGroup'] -f $Index, $Rules[$Index].group))
      }
    }
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceConfigurationCrossField] Exiting'
}
