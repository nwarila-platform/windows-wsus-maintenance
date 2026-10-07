#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceStageCatalog {
  <#
    .SYNOPSIS
        Lists the maintenance stages in their mandatory execution order.

    .DESCRIPTION
        Returns one entry per stage with its name, its position in the run, and whether
        it deletes or alters SUSDB content (which places it behind the backup gate;
        declines change approval state through the WSUS API and are not gated). Every
        enabled stage runs on every run; each acts only on what is due. The order
        satisfies every ordering constraint in the specification: backup first, custom
        indexes and the deletion-procedure fix before obsolete-update deletion, declines
        before declined-update deletion and the built-in cleanup, all cleanup before
        re-indexing, and the read-only health checks last so they see the result.

    .EXAMPLE
        Get-MaintenanceStageCatalog

    .OUTPUTS
        [System.Management.Automation.PSCustomObject[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancestagecatalog',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject[]])]
  Param ()

  Write-Debug -Message:'[Get-MaintenanceStageCatalog] Entering'

  # Initialize Variable(s)
  [System.Object[]]$Private:Definitions = @()
  [System.Int32]$Private:Order = 0
  [System.Collections.Generic.List[PSCustomObject]]$Private:Stages = $Null
  [PSCustomObject[]]$Private:Result = @()

  # Name, alters SUSDB content.
  $Definitions = @(
    @('Backup', $False),
    @('CustomIndexes', $True),
    @('DeleteUpdateFix', $True),
    @('SupersededDecline', $False),
    @('AcceleratedDecline', $False),
    @('ExpiredDecline', $False),
    @('RuleDecline', $False),
    @('DeclinedDeletion', $True),
    @('ObsoleteUpdates', $True),
    @('BuiltInCleanup', $True),
    @('SyncHistory', $True),
    @('StaleComputers', $True),
    @('Reindex', $False),
    @('IisLogRetention', $False),
    @('ArtifactRetention', $False),
    @('HealthChecks', $False)
  )

  $Stages = [System.Collections.Generic.List[PSCustomObject]]::new()
  ForEach ($Definition In $Definitions) {
    $Order++
    $Stages.Add(
      [PSCustomObject]@{
        Name           = [System.String]$Definition[0]
        Order          = [System.Int32]$Order
        AltersDatabase = [System.Boolean]$Definition[1]
      }
    )
  }

  [PSCustomObject[]]$Result = $Stages.ToArray()
  $Result
  Write-Debug -Message:'[Get-MaintenanceStageCatalog] Exiting'
}
