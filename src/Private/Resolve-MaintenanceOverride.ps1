#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Resolve-MaintenanceOverride.DuplicateStage'   = "-Stage: '{0}' is listed more than once."
  'Resolve-MaintenanceOverride.RemoveNeedsStage' = '-RemoveCustomIndexes runs the CustomIndexes stage, so -Stage must include CustomIndexes when it is given.'
  'Resolve-MaintenanceOverride.UnknownStage'     = "-Stage: '{0}' is not a stage name; use one of {1}."
}

Function Resolve-MaintenanceOverride {
  <#
    .SYNOPSIS
        Validates the command-line options and applies their one-run overrides.

    .DESCRIPTION
        Checks the stage names given with -Stage and records them in their canonical
        spelling, checks the report formats and the verbosity against the values the
        configuration allows, then applies the overrides the command line may make for one run:
        dry-run, report folder and formats, and log verbosity. Every
        override in effect is described for the run log. Problems are returned, not
        thrown, so they can be reported together with configuration errors. When no
        configuration is supplied (because the document itself was invalid) only the
        options are validated.

    .PARAMETER ConfigPath
        Configuration path given on the command line, recorded as an override.

    .PARAMETER Configuration
        Effective configuration to apply overrides to, or null.

    .PARAMETER DryRun
        Run as a simulation.

    .PARAMETER RemoveCustomIndexes
        Drop the custom indexes this script created (and only those) instead of creating
        missing ones; runs the CustomIndexes stage only unless -Stage lists more.

    .PARAMETER ReportFolder
        Report folder for this run.

    .PARAMETER ReportFormat
        Report formats for this run.

    .PARAMETER Rule
        The configuration catalogue; defaults to Get-MaintenanceConfigurationRule.

    .PARAMETER Stage
        Stage names given with -Stage: only these stages run.

    .PARAMETER Verbosity
        Log verbosity for this run.

    .EXAMPLE
        Resolve-MaintenanceOverride -Configuration $Effective -Stage 'reindex'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#resolve-maintenanceoverride',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $ConfigPath = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Configuration = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $DryRun,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $RemoveCustomIndexes,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $ReportFolder = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $ReportFormat = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject[]]
    $Rule = $Null,

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
    [System.String]
    $Verbosity = ''
  )

  Write-Debug -Message:'[Resolve-MaintenanceOverride] Entering'

  # Initialize Variable(s)
  [PSCustomObject[]]$Private:Catalogue = @()
  [System.String]$Private:Canonical = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [PSCustomObject]$Private:FolderRule = $Null
  [PSCustomObject]$Private:FormatRule = $Null
  [System.Collections.Generic.List[System.String]]$Private:Overrides = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:SeenStages = $Null
  [System.Collections.Generic.List[System.String]]$Private:Stages = $Null
  [System.String[]]$Private:StageNames = @()
  [PSCustomObject]$Private:VerbosityRule = $Null
  [PSCustomObject]$Private:Result = $Null

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $Overrides = [System.Collections.Generic.List[System.String]]::new()
  $Stages = [System.Collections.Generic.List[System.String]]::new()

  If ($Null -eq $Rule) {
    $Catalogue = @(Get-MaintenanceConfigurationRule)
  } Else {
    $Catalogue = $Rule
  }

  $FolderRule = $Catalogue | Where-Object -FilterScript { $PSItem.Path -ceq 'report.folder' } | Select-Object -First:1
  $FormatRule = $Catalogue | Where-Object -FilterScript { $PSItem.Path -ceq 'report.formats' } | Select-Object -First:1
  $VerbosityRule = $Catalogue | Where-Object -FilterScript { $PSItem.Path -ceq 'log.verbosity' } | Select-Object -First:1
  $StageNames = [System.String[]]@(Get-MaintenanceStageCatalog | ForEach-Object -Process:({ $PSItem.Name }))

  $SeenStages = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
  ForEach ($Name In @($Stage)) {
    $Canonical = [System.String]::Empty
    ForEach ($Known In $StageNames) {
      If ($Known -ieq $Name) {
        $Canonical = $Known
      }
    }

    If ([System.String]::IsNullOrEmpty($Canonical) -eq $True) {
      $Errors.Add(($Script:Message['Resolve-MaintenanceOverride.UnknownStage'] -f $Name, ($StageNames -join ', ')))
    } ElseIf ($SeenStages.Add($Canonical) -eq $False) {
      $Errors.Add(($Script:Message['Resolve-MaintenanceOverride.DuplicateStage'] -f $Canonical))
    } Else {
      $Stages.Add($Canonical)
    }
  }

  If ($PSBoundParameters.ContainsKey('ReportFolder') -eq $True) {
    ForEach ($FolderError In @(Test-MaintenancePathValue -Path:'-ReportFolder' -Pattern:$FolderRule.Pattern -Value:$ReportFolder)) {
      $Errors.Add($FolderError)
    }
  }

  If ($PSBoundParameters.ContainsKey('ReportFormat') -eq $True) {
    ForEach ($FormatError In @(Test-MaintenanceConfigurationValue -Path:'-ReportFormat' -Rule:$FormatRule -Value:([System.Object[]]@($ReportFormat)))) {
      $Errors.Add($FormatError)
    }
  }

  If ([System.String]::IsNullOrEmpty($Verbosity) -eq $False) {
    ForEach ($VerbosityError In @(Test-MaintenanceConfigurationValue -Path:'-Verbosity' -Rule:$VerbosityRule -Value:$Verbosity)) {
      $Errors.Add($VerbosityError)
    }
  }

  If ($PSBoundParameters.ContainsKey('ConfigPath') -eq $True) {
    $Overrides.Add(('configuration path = {0} (-ConfigPath)' -f $ConfigPath))
  }

  If ($Stages.Count -gt 0) {
    $Overrides.Add(('stages = {0} (-Stage)' -f ($Stages -join ', ')))
  }

  If ($RemoveCustomIndexes.IsPresent -eq $True) {
    If ((@($Stage).Count -gt 0) -and ($Stages.Contains('CustomIndexes') -eq $False)) {
      $Errors.Add($Script:Message['Resolve-MaintenanceOverride.RemoveNeedsStage'])
    } ElseIf ($Stages.Count -eq 0) {
      $Stages.Add('CustomIndexes')
    }

    $Overrides.Add('custom indexes = remove the ones this script created (-RemoveCustomIndexes)')
  }

  If (($Null -ne $Configuration) -and ($Errors.Count -eq 0)) {
    If ($DryRun.IsPresent -eq $True) {
      $Configuration.run.dryRun = $True
      $Overrides.Add('run.dryRun = true (-DryRun)')
    }

    If ($PSBoundParameters.ContainsKey('ReportFolder') -eq $True) {
      $Configuration.report.folder = $ReportFolder
      $Overrides.Add(('report.folder = {0} (-ReportFolder)' -f $ReportFolder))
    }

    If ($PSBoundParameters.ContainsKey('ReportFormat') -eq $True) {
      $Configuration.report.formats = [System.Object[]]@($ReportFormat)
      $Overrides.Add(('report.formats = {0} (-ReportFormat)' -f ($ReportFormat -join ', ')))
    }

    If ([System.String]::IsNullOrEmpty($Verbosity) -eq $False) {
      $Configuration.log.verbosity = $Verbosity
      $Overrides.Add(('log.verbosity = {0} (-Verbosity)' -f $Verbosity))
    }
  }

  # It's always desirable to explicitly set the Result object with its desired class as close
  #   to the soft return to ensure the output is predictable and easily traceable.
  [PSCustomObject]$Result = [PSCustomObject]@{
    Configuration       = $Configuration
    Stages              = [System.String[]]$Stages.ToArray()
    RemoveCustomIndexes = [System.Boolean]$RemoveCustomIndexes.IsPresent
    Overrides           = [System.String[]]$Overrides.ToArray()
    Errors              = [System.String[]]$Errors.ToArray()
  }

  $Result
  Write-Debug -Message:'[Resolve-MaintenanceOverride] Exiting'
}
