#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceStageEnabled {
  <#
    .SYNOPSIS
        Reports whether configuration enables a stage.

    .DESCRIPTION
        Maps each stage to the configuration that enables it. A stage driven by several
        switches is enabled when any of them is on: the built-in cleanup when any of its
        options is on, the health checks when any check is on, and the rule declines when
        at least one enabled rule belongs to no group or to an enabled group. Artifact
        retention always runs; its limits decide what it removes.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER Name
        Stage name from the stage catalogue.

    .EXAMPLE
        Test-MaintenanceStageEnabled -Configuration $Effective -Name 'Reindex'

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancestageenabled',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
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
    $Configuration,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Name
  )

  Write-Debug -Message:'[Test-MaintenanceStageEnabled] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Enabled = $False
  [System.Collections.Generic.HashSet[System.String]]$Private:DisabledGroups = $Null
  [System.Boolean]$Private:Result = $False

  Switch ($Name) {
    'Backup' { $Enabled = $Configuration.backup.enabled }
    'CustomIndexes' { $Enabled = $Configuration.customIndexes.enabled }
    'DeleteUpdateFix' { $Enabled = $Configuration.deleteUpdateFix.enabled }
    'SupersededDecline' { $Enabled = $Configuration.declines.superseded.enabled }
    'AcceleratedDecline' { $Enabled = $Configuration.declines.accelerated.enabled }
    'ExpiredDecline' { $Enabled = $Configuration.declines.expired.enabled }
    'RuleDecline' {
      $DisabledGroups = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
      ForEach ($Group In @($Configuration.declines.groups)) {
        If (($Null -ne $Group) -and ($Group.enabled -eq $False)) {
          [void]$DisabledGroups.Add([System.String]$Group.name)
        }
      }

      ForEach ($Rule In @($Configuration.declines.rules)) {
        If (($Null -ne $Rule) -and ($Rule.enabled -eq $True)) {
          If (($Null -eq $Rule.PSObject.Properties['group']) -or ($DisabledGroups.Contains([System.String]$Rule.group) -eq $False)) {
            $Enabled = $True
          }
        }
      }
    }
    'ContentStaging' { $Enabled = ($Configuration.approval.enabled -eq $True) -and ($Configuration.approval.staging.enabled -eq $True) }
    'DeferredApproval' { $Enabled = $Configuration.approval.enabled }
    'DeclinedDeletion' { $Enabled = $Configuration.declinedDeletion.enabled }
    'ObsoleteUpdates' { $Enabled = $Configuration.obsoleteUpdates.enabled }
    'BuiltInCleanup' {
      ForEach ($Property In $Configuration.builtInCleanup.PSObject.Properties) {
        If ($Property.Value -is [System.Boolean] -and $Property.Value -eq $True) {
          $Enabled = $True
        }
      }
    }
    'SyncHistory' { $Enabled = $Configuration.syncHistory.enabled }
    'StaleComputers' { $Enabled = $Configuration.staleComputers.enabled }
    'Reindex' { $Enabled = $Configuration.reindex.enabled }
    'IisLogRetention' { $Enabled = $Configuration.iisLogs.enabled }
    'ArtifactRetention' { $Enabled = $True }
    'HealthChecks' {
      ForEach ($Check In $Configuration.health.PSObject.Properties) {
        If ($Check.Value.enabled -eq $True) {
          $Enabled = $True
        }
      }
    }
    Default { $Enabled = $False }
  }

  [System.Boolean]$Result = $Enabled
  $Result
  Write-Debug -Message:'[Test-MaintenanceStageEnabled] Exiting'
}
