#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceOutputSetting {
  <#
    .SYNOPSIS
        Works out where and how this run reports, even when the configuration is invalid.

    .DESCRIPTION
        Returns the report folder, formats and item limit, the log folder and verbosity, the summary
        folder, the event-log settings, the built-in default folders and whether a data folder that
        other principals can change may be used (run.permissiveFolderOverride). With a valid configuration
        the values come from it, command-line overrides included. When the document is missing,
        unreadable or invalid, each setting the document states validly is still used and every other
        setting takes its built-in default, so a failure report can be delivered; command-line
        overrides that are valid on their own apply on top.

    .PARAMETER Configuration
        Effective configuration with overrides applied, or null when the document is invalid.

    .PARAMETER Document
        Parsed configuration document, or null when it could not be read.

    .PARAMETER ReportFolder
        -ReportFolder, when given.

    .PARAMETER ReportFormat
        -ReportFormat, when given.

    .PARAMETER Rule
        The configuration catalogue; defaults to Get-MaintenanceConfigurationRule.

    .PARAMETER Verbosity
        -Verbosity, when given.

    .EXAMPLE
        Get-MaintenanceOutputSetting -Configuration $Resolution.Configuration -Document $Document

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenanceoutputsetting',
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
    [AllowNull()]
    [PSCustomObject]
    $Document = $Null,

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
    [AllowEmptyString()]
    [System.String]
    $Verbosity = ''
  )

  Write-Debug -Message:'[Get-MaintenanceOutputSetting] Entering'

  # Initialize Variable(s)
  [PSCustomObject[]]$Private:Catalogue = @()
  [System.Collections.Hashtable]$Private:Defaults = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:EventIds = $Null
  [PSCustomObject]$Private:Lookup = $Null
  [System.Collections.Hashtable]$Private:Rules = $Null
  [System.Object]$Private:Value = $Null
  [System.Collections.Hashtable]$Private:Values = $Null
  [PSCustomObject]$Private:Result = $Null

  If ($Null -eq $Rule) {
    $Catalogue = @(Get-MaintenanceConfigurationRule)
  } Else {
    $Catalogue = $Rule
  }

  $Defaults = @{}
  $Rules = @{}
  $Values = @{}
  ForEach ($Entry In $Catalogue) {
    If (($Entry.Path -clike 'report.*') -or ($Entry.Path -clike 'log.*') -or ($Entry.Path -clike 'summary.*') -or ($Entry.Path -clike 'eventLog.*') -or ($Entry.Path -ceq 'run.permissiveFolderOverride')) {
      $Defaults[$Entry.Path] = $Entry.Default
      $Rules[$Entry.Path] = $Entry
      $Value = $Entry.Default

      If ($Null -ne $Configuration) {
        $Value = (Get-MaintenanceDocumentValue -Document:$Configuration -Path:$Entry.Path).Value
      } ElseIf ($Null -ne $Document) {
        $Lookup = Get-MaintenanceDocumentValue -Document:$Document -Path:$Entry.Path
        If (($Lookup.Found -eq $True) -and (@(Test-MaintenanceConfigurationValue -Path:$Entry.Path -Rule:$Entry -Value:$Lookup.Value).Count -eq 0)) {
          $Value = $Lookup.Value
        }
      }

      $Values[$Entry.Path] = $Value
    }
  }

  # A valid configuration already carries the command-line overrides.
  If ($Null -eq $Configuration) {
    If (([System.String]::IsNullOrEmpty($ReportFolder) -eq $False) -and (@(Test-MaintenancePathValue -Path:'-ReportFolder' -Pattern:$Rules['report.folder'].Pattern -Value:$ReportFolder).Count -eq 0)) {
      $Values['report.folder'] = $ReportFolder
    }

    If ((@($ReportFormat).Count -gt 0) -and (@(Test-MaintenanceConfigurationValue -Path:'-ReportFormat' -Rule:$Rules['report.formats'] -Value:([System.Object[]]@($ReportFormat))).Count -eq 0)) {
      $Values['report.formats'] = [System.Object[]]@($ReportFormat)
    }

    If (([System.String]::IsNullOrEmpty($Verbosity) -eq $False) -and (@(Test-MaintenanceConfigurationValue -Path:'-Verbosity' -Rule:$Rules['log.verbosity'] -Value:$Verbosity).Count -eq 0)) {
      $Values['log.verbosity'] = $Verbosity
    }
  }

  $EventIds = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Kind In @('runStarted', 'runSucceeded', 'runWarning', 'runFailed', 'stageError', 'preconditionFailure', 'configurationInvalid', 'lateContent')) {
    $EventIds[$Kind] = [System.Int32]$Values[('eventLog.eventIds.{0}' -f $Kind)]
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    ReportFolder             = [System.String]$Values['report.folder']
    ReportFormats            = [System.String[]]@($Values['report.formats'])
    MaxItems                 = [System.Int32]$Values['report.maxItemsPerSection']
    LogFolder                = [System.String]$Values['log.folder']
    LogVerbosity             = [System.String]$Values['log.verbosity']
    SummaryFolder            = [System.String]$Values['summary.folder']
    DefaultReportFolder      = [System.String]$Defaults['report.folder']
    DefaultSummaryFolder     = [System.String]$Defaults['summary.folder']
    PermissiveFolderOverride = [System.Boolean]$Values['run.permissiveFolderOverride']
    EventLog                 = [PSCustomObject]@{
      Enabled  = [System.Boolean]$Values['eventLog.enabled']
      LogName  = [System.String]$Values['eventLog.logName']
      Source   = [System.String]$Values['eventLog.source']
      EventIds = [PSCustomObject]$EventIds
    }
  }

  $Result
  Write-Debug -Message:'[Get-MaintenanceOutputSetting] Exiting'
}
