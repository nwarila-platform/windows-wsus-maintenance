#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-MaintenanceStagePlan.Disabled'     = 'disabled by configuration'
  'Get-MaintenanceStagePlan.Enabled'      = 'enabled'
  'Get-MaintenanceStagePlan.Listed'       = 'listed with -Stage'
  'Get-MaintenanceStagePlan.NoPermission' = 'skipped: missing permission: {0}'
  'Get-MaintenanceStagePlan.NotListed'    = 'not listed with -Stage'
  'Get-MaintenanceStagePlan.Replica'      = 'skipped: replica'
  'Get-MaintenanceStagePlan.RoleUnknown'  = 'skipped: server role unknown'
}

Function Get-MaintenanceStagePlan {
  <#
    .SYNOPSIS
        Decides, for every stage in its fixed order, whether it runs.

    .DESCRIPTION
        Walks the stage catalogue in its mandatory order, so every run honours the
        ordering constraints, and gives each stage a Mode (Run or Skip) with a Reason.
        Every enabled stage runs on every run; each stage acts only on what is due, so a
        stage the time budget cut short is simply done on the next run. With -Stage only
        the listed stages run. A stage that configuration disables is skipped either way.
        On a replica, every stage that declines updates (the decline policies and declined-update
        deletion) is skipped with "skipped: replica", and when the tier is unknown it is skipped
        too. A stage whose database permissions are missing is skipped and names them in Missing.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER MissingPermission
        Missing permissions by stage name (Test-SusdbPermission), or null when not checked.

    .PARAMETER Stage
        Canonical stage names given with -Stage; empty means every enabled stage.

    .PARAMETER Tier
        Detected server tier (TopTier, Autonomous, Replica or Unknown); empty before discovery.

    .EXAMPLE
        Get-MaintenanceStagePlan -Configuration $Effective -Stage @('Backup', 'Reindex')

    .OUTPUTS
        [System.Management.Automation.PSCustomObject[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancestageplan',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject[]])]
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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Collections.Hashtable]
    $MissingPermission = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Stage = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [ValidateSet('', 'TopTier', 'Autonomous', 'Replica', 'Unknown')]
    [System.String]
    $Tier = ''
  )

  Write-Debug -Message:'[Get-MaintenanceStagePlan] Entering'

  # Initialize Variable(s)
  [System.String[]]$Private:Gated = @('SupersededDecline', 'AcceleratedDecline', 'ExpiredDecline', 'RuleDecline', 'DeclinedDeletion')
  [System.Boolean]$Private:Listed = @($Stage).Count -gt 0
  [System.String[]]$Private:Missing = @()
  [System.Boolean]$Private:PermissionSkip = $False
  [System.String]$Private:Mode = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Plan = $Null
  [System.String]$Private:Reason = [System.String]::Empty
  [PSCustomObject[]]$Private:Result = @()

  $Plan = [System.Collections.Generic.List[PSCustomObject]]::new()

  ForEach ($Entry In @(Get-MaintenanceStageCatalog)) {
    $Missing = @()
    $PermissionSkip = $False
    If ($Null -ne $MissingPermission) {
      $Missing = [System.String[]]@($MissingPermission[$Entry.Name] | Where-Object -FilterScript { $Null -ne $PSItem })
    }

    If ((Test-MaintenanceStageEnabled -Configuration:$Configuration -Name:$Entry.Name) -eq $False) {
      $Mode = 'Skip'
      $Reason = $Script:Message['Get-MaintenanceStagePlan.Disabled']
    } ElseIf (($Listed -eq $True) -and ($Stage -notcontains $Entry.Name)) {
      $Mode = 'Skip'
      $Reason = $Script:Message['Get-MaintenanceStagePlan.NotListed']
    } ElseIf (($Tier -eq 'Replica') -and ($Gated -contains $Entry.Name)) {
      $Mode = 'Skip'
      $Reason = $Script:Message['Get-MaintenanceStagePlan.Replica']
    } ElseIf (($Tier -eq 'Unknown') -and ($Gated -contains $Entry.Name)) {
      $Mode = 'Skip'
      $Reason = $Script:Message['Get-MaintenanceStagePlan.RoleUnknown']
    } ElseIf ($Missing.Count -gt 0) {
      $Mode = 'Skip'
      $PermissionSkip = $True
      $Reason = $Script:Message['Get-MaintenanceStagePlan.NoPermission'] -f ($Missing -join ', ')
    } ElseIf ($Listed -eq $True) {
      $Mode = 'Run'
      $Reason = $Script:Message['Get-MaintenanceStagePlan.Listed']
    } Else {
      $Mode = 'Run'
      $Reason = $Script:Message['Get-MaintenanceStagePlan.Enabled']
    }

    If ($PermissionSkip -eq $False) {
      $Missing = @()
    }

    $Plan.Add(
      [PSCustomObject]@{
        Name           = [System.String]$Entry.Name
        Order          = [System.Int32]$Entry.Order
        AltersDatabase = [System.Boolean]$Entry.AltersDatabase
        Mode           = [System.String]$Mode
        Reason         = [System.String]$Reason
        Missing        = [System.String[]]$Missing
      }
    )
  }

  [PSCustomObject[]]$Result = $Plan.ToArray()
  $Result
  Write-Debug -Message:'[Get-MaintenanceStagePlan] Exiting'
}
