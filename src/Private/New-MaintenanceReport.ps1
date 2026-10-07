#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'New-MaintenanceReport.Command'              = 'Command:'
  'New-MaintenanceReport.Connection'           = 'WSUS connection: {0}'
  'New-MaintenanceReport.Counts'               = 'Counts: {0}'
  'New-MaintenanceReport.Duration'             = 'Total duration: {0} s'
  'New-MaintenanceReport.ErrorAt'              = 'Error: {0} (at {1})'
  'New-MaintenanceReport.FailureHeading'       = 'Failure'
  'New-MaintenanceReport.FullRun'              = 'every enabled stage'
  'New-MaintenanceReport.ItemsHeading'         = 'Items ({0}):'
  'New-MaintenanceReport.LabelConfiguration'   = 'Configuration'
  'New-MaintenanceReport.LabelDatabase'        = 'Database'
  'New-MaintenanceReport.LabelDryRun'          = 'Dry run'
  'New-MaintenanceReport.LabelEndpoint'        = 'WSUS endpoint'
  'New-MaintenanceReport.LabelIdentity'        = 'Run identity'
  'New-MaintenanceReport.LabelLog'             = 'Run log'
  'New-MaintenanceReport.LabelOverrides'       = 'Overrides'
  'New-MaintenanceReport.LabelPermissions'     = 'Database permissions'
  'New-MaintenanceReport.LabelProfile'         = 'Profile'
  'New-MaintenanceReport.LabelRole'            = 'Server role'
  'New-MaintenanceReport.LabelRun'             = 'Run identifier'
  'New-MaintenanceReport.LabelServer'          = 'Server'
  'New-MaintenanceReport.LabelStarted'         = 'Started'
  'New-MaintenanceReport.LabelSynchronization' = 'Synchronization'
  'New-MaintenanceReport.LabelUpstream'        = 'Upstream source'
  'New-MaintenanceReport.LabelVersion'         = 'WSUS version'
  'New-MaintenanceReport.MessageLine'          = 'Message: {0}'
  'New-MaintenanceReport.No'                   = 'no'
  'New-MaintenanceReport.None'                 = 'none'
  'New-MaintenanceReport.NoNotices'            = 'None.'
  'New-MaintenanceReport.NoStage'              = 'No stage ran.'
  'New-MaintenanceReport.NotConnected'         = 'not yet connected'
  'New-MaintenanceReport.NotDiscovered'        = 'not yet discovered'
  'New-MaintenanceReport.NoticesHeading'       = 'Notices ({0})'
  'New-MaintenanceReport.NoticesHighest'       = 'Notices ({0}; highest: {1})'
  'New-MaintenanceReport.NoticeTotals'         = 'Notice totals: {0} error, {1} high, {2} warning, {3} information'
  'New-MaintenanceReport.NotWritten'           = 'not written'
  'New-MaintenanceReport.Omitted'              = '... and {0} more in the run log'
  'New-MaintenanceReport.PointReached'         = 'Point reached'
  'New-MaintenanceReport.Reason'               = 'Reason: {0}'
  'New-MaintenanceReport.See'                  = 'See: {0}'
  'New-MaintenanceReport.StageList'            = 'stage list: {0}'
  'New-MaintenanceReport.StagesHeading'        = 'Stages'
  'New-MaintenanceReport.StageTotals'          = 'Stage totals: {0} succeeded, {1} with warnings, {2} failed, {3} skipped, {4} not run'
  'New-MaintenanceReport.Started'              = '{0} ({1})'
  'New-MaintenanceReport.Status'               = 'Run status: {0} (exit code {1})'
  'New-MaintenanceReport.Title'                = 'WSUS maintenance report'
  'New-MaintenanceReport.WhatHappened'         = 'What happened'
  'New-MaintenanceReport.WhatToDo'             = 'What to do'
  'New-MaintenanceReport.Yes'                  = 'yes'
}

Function New-MaintenanceReport {
  <#
    .SYNOPSIS
        Builds the report of one run, ready to render.

    .DESCRIPTION
        Assembles, in report order: a header (server, WSUS version, server role, upstream source,
        database, WSUS endpoint, run identity, database permissions and synchronization guard,
        taken from discovery and reading "not yet discovered" for anything the run did not reach,
        then the run identifier, profile, dry-run flag, start time with time zone, configuration
        path, overrides and run log); the failure, for a run that stopped on a precondition; the
        notices ordered by severity, highest first, keeping the order they were raised within one
        severity; the WSUS connection time; one section per stage that ran or was skipped, with its
        status, reason, counts, items (at most MaxItems; the rest are only in the run log), duration
        and any error; and the totals, duration and run status. Every text taken from a stage or a
        notice passes through Protect-MaintenanceText. The text and HTML renderings and the JSON
        summary are all made from this one model, so their counts agree.

    .PARAMETER Discovery
        Discovered facts for the header: WsusVersion, Role, Upstream, Database, Endpoint,
        Identity, Permissions, Synchronization and Connection; any may be missing.

    .PARAMETER ExitCode
        Exit code of the run.

    .PARAMETER Failure
        Kind, Point, Message and Guidance of a run that stopped early, or null.

    .PARAMETER LogPath
        Path of the run log, if one was written.

    .PARAMETER MaxItems
        Items listed per stage section.

    .PARAMETER Notice
        Notices of the run, in the order they were raised.

    .PARAMETER Run
        The run record (New-MaintenanceRunRecord).

    .PARAMETER Stage
        Stage outcomes in catalogue order.

    .PARAMETER Status
        Run status.

    .PARAMETER Validation
        The validation summary, for the configuration path and the overrides.

    .EXAMPLE
        New-MaintenanceReport -Run $Record -Stage $Outcomes -Notice $Notices -Status 'Success' -ExitCode 0 -Validation $Summary -MaxItems 100

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancereport',
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
    $Discovery = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 255)]
    [System.Int32]
    $ExitCode,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Failure = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $LogPath = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(1, 2147483647)]
    [System.Int32]
    $MaxItems,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Notice = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Run,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Stage = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Success', 'Warning', 'Error')]
    [System.String]
    $Status,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Validation
  )

  Write-Debug -Message:'[New-MaintenanceReport] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:CountList = $Null
  [System.Collections.Hashtable]$Private:Discovered = $Null
  [System.String]$Private:DryRunText = [System.String]::Empty
  [PSCustomObject]$Private:FailureCopy = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Header = $Null
  [System.String]$Private:Highest = [System.String]::Empty
  [System.String[]]$Private:Items = @()
  [System.Object[]]$Private:Keys = @()
  [System.String]$Private:LogText = [System.String]::Empty
  [System.Collections.Specialized.OrderedDictionary]$Private:NoticeTotals = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String]$Private:Overrides = [System.String]::Empty
  [System.Object[]]$Private:Pairs = @()
  [System.Object]$Private:RawCounts = $Null
  [System.String]$Private:RunProfile = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Sections = $Null
  [System.String[]]$Private:Severities = @('Error', 'High', 'Warning', 'Information')
  [System.String[]]$Private:Shown = @()
  [System.String]$Private:StageStatus = [System.String]::Empty
  [System.Collections.Specialized.OrderedDictionary]$Private:StageTotals = $Null
  [PSCustomObject]$Private:Result = $Null

  $Header = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Sections = [System.Collections.Generic.List[PSCustomObject]]::new()
  $StageTotals = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Success', 'Warning', 'Error', 'Skipped', 'NotRun')) {
    $StageTotals[$Name] = 0
  }

  $NoticeTotals = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In $Severities) {
    $NoticeTotals[$Name] = 0
  }

  # Highest severity first; notices of one severity keep the order they were raised in.
  ForEach ($Level In $Severities) {
    ForEach ($Item In @($Notice)) {
      If ([System.String](Get-MaintenancePropertyValue -InputObject:$Item -Name:'Severity' -Default:'') -eq $Level) {
        If ([System.String]::IsNullOrEmpty($Highest) -eq $True) {
          $Highest = $Level
        }

        $NoticeTotals[$Level] = $NoticeTotals[$Level] + 1
        $Notices.Add(
          [PSCustomObject]@{
            Severity  = [System.String]$Level
            Message   = Protect-MaintenanceText -Text:([System.String](Get-MaintenancePropertyValue -InputObject:$Item -Name:'Message' -Default:''))
            Stage     = [System.String](Get-MaintenancePropertyValue -InputObject:$Item -Name:'Stage' -Default:'')
            Link      = Protect-MaintenanceText -Text:([System.String](Get-MaintenancePropertyValue -InputObject:$Item -Name:'Link' -Default:''))
            Command   = Protect-MaintenanceText -Text:([System.String](Get-MaintenancePropertyValue -InputObject:$Item -Name:'Command' -Default:''))
            RaisedAt  = Get-MaintenancePropertyValue -InputObject:$Item -Name:'RaisedAt' -Default:$Null
            IsHighest = [System.Boolean]($Level -eq $Highest)
          }
        )
      }
    }
  }

  ForEach ($Outcome In @($Stage)) {
    If ($Null -eq $Outcome) {
      Continue
    }

    $Items = [System.String[]]@(
      @(Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Items' -Default:@()) |
        Where-Object -FilterScript { $Null -ne $PSItem } |
        ForEach-Object -Process:({ Protect-MaintenanceText -Text:([System.String]$PSItem) })
    )
    $Shown = [System.String[]]@($Items | Select-Object -First:$MaxItems)

    $CountList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $RawCounts = Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Counts' -Default:$Null
    If ($RawCounts -is [System.Collections.IDictionary]) {
      $Keys = @($RawCounts.Keys)
      If ($RawCounts -is [System.Collections.Hashtable]) {
        $Keys = @($Keys | Sort-Object)
      }

      ForEach ($Key In $Keys) {
        $CountList.Add([PSCustomObject]@{ Name = [System.String]$Key; Value = $RawCounts[$Key] })
      }
    } ElseIf ($Null -ne $RawCounts) {
      ForEach ($Property In $RawCounts.PSObject.Properties) {
        $CountList.Add([PSCustomObject]@{ Name = [System.String]$Property.Name; Value = $Property.Value })
      }
    }

    $StageStatus = [System.String](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Status' -Default:'')
    If ($StageTotals.Contains($StageStatus) -eq $True) {
      $StageTotals[$StageStatus] = $StageTotals[$StageStatus] + 1
    }

    $Sections.Add(
      [PSCustomObject]@{
        Name            = [System.String](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Name' -Default:'')
        Order           = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Order' -Default:0)
        Status          = $StageStatus
        Reason          = Protect-MaintenanceText -Text:([System.String](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Reason' -Default:''))
        StartedAt       = Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'StartedAt' -Default:$Null
        DurationSeconds = [System.Double](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'DurationSeconds' -Default:0)
        Counts          = [PSCustomObject[]]$CountList.ToArray()
        Message         = Protect-MaintenanceText -Text:([System.String](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'Message' -Default:''))
        Items           = $Shown
        ItemCount       = [System.Int32]$Items.Count
        OmittedItems    = [System.Int32]($Items.Count - $Shown.Count)
        ErrorMessage    = Protect-MaintenanceText -Text:([System.String](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'ErrorMessage' -Default:''))
        ErrorTime       = Get-MaintenancePropertyValue -InputObject:$Outcome -Name:'ErrorTime' -Default:$Null
      }
    )
  }

  If ($Null -ne $Failure) {
    $FailureCopy = [PSCustomObject]@{
      Kind     = [System.String]$Failure.Kind
      Point    = [System.String]$Failure.Point
      Message  = Protect-MaintenanceText -Text:([System.String]$Failure.Message)
      Guidance = [System.String]$Failure.Guidance
    }
  }

  $RunProfile = $Script:Message['New-MaintenanceReport.FullRun']
  If (@($Run.Stages).Count -gt 0) {
    $RunProfile = $Script:Message['New-MaintenanceReport.StageList'] -f (@($Run.Stages) -join ', ')
  }

  $Overrides = $Script:Message['New-MaintenanceReport.None']
  If (@($Validation.Overrides).Count -gt 0) {
    $Overrides = @($Validation.Overrides) -join '; '
  }

  $LogText = $Script:Message['New-MaintenanceReport.NotWritten']
  If ([System.String]::IsNullOrEmpty($LogPath) -eq $False) {
    $LogText = $LogPath
  }

  $DryRunText = $Script:Message['New-MaintenanceReport.No']
  If ($Run.DryRun -eq $True) {
    $DryRunText = $Script:Message['New-MaintenanceReport.Yes']
  }

  $Discovered = @{}
  ForEach ($Name In @('WsusVersion', 'Role', 'Upstream', 'Database', 'Endpoint', 'Identity', 'Permissions', 'Synchronization', 'Connection')) {
    $Discovered[$Name] = [System.String](Get-MaintenancePropertyValue -InputObject:$Discovery -Name:$Name -Default:'')
    If ([System.String]::IsNullOrWhiteSpace($Discovered[$Name]) -eq $True) {
      $Discovered[$Name] = $Script:Message['New-MaintenanceReport.NotDiscovered']
    }
  }

  If ([System.String]::IsNullOrWhiteSpace([System.String](Get-MaintenancePropertyValue -InputObject:$Discovery -Name:'Connection' -Default:'')) -eq $True) {
    $Discovered['Connection'] = $Script:Message['New-MaintenanceReport.NotConnected']
  }

  $Pairs = @(
    @('LabelServer', [System.Environment]::MachineName),
    @('LabelVersion', $Discovered['WsusVersion']),
    @('LabelRole', $Discovered['Role']),
    @('LabelUpstream', $Discovered['Upstream']),
    @('LabelDatabase', $Discovered['Database']),
    @('LabelEndpoint', $Discovered['Endpoint']),
    @('LabelIdentity', $Discovered['Identity']),
    @('LabelPermissions', $Discovered['Permissions']),
    @('LabelSynchronization', $Discovered['Synchronization']),
    @('LabelRun', $Run.RunId),
    @('LabelProfile', $RunProfile),
    @('LabelDryRun', $DryRunText),
    @('LabelStarted', ($Script:Message['New-MaintenanceReport.Started'] -f $Run.StartedAt.ToString('yyyy-MM-dd HH:mm:ss zzz', [System.Globalization.CultureInfo]::InvariantCulture), [System.TimeZoneInfo]::Local.Id)),
    @('LabelConfiguration', $Validation.ConfigurationPath),
    @('LabelOverrides', $Overrides),
    @('LabelLog', $LogText)
  )
  ForEach ($Pair In $Pairs) {
    $Header.Add([PSCustomObject]@{ Label = [System.String]$Script:Message[('New-MaintenanceReport.{0}' -f $Pair[0])]; Value = Protect-MaintenanceText -Text:([System.String]$Pair[1]) })
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Title           = [System.String]$Script:Message['New-MaintenanceReport.Title']
    RunId           = [System.String]$Run.RunId
    Server          = [System.String][System.Environment]::MachineName
    Status          = [System.String]$Status
    ExitCode        = [System.Int32]$ExitCode
    StartedAt       = $Run.StartedAt
    CompletedAt     = $Run.CompletedAt
    DurationSeconds = [System.Double]$Run.DurationSeconds
    DryRun          = [System.Boolean]$Run.DryRun
    StagesRequested = [System.String[]]@($Run.Stages)
    Header          = [PSCustomObject[]]$Header.ToArray()
    Failure         = $FailureCopy
    Notices         = [PSCustomObject[]]$Notices.ToArray()
    HighestSeverity = [System.String]$Highest
    Connection      = [System.String]$Discovered['Connection']
    Stages          = [PSCustomObject[]]$Sections.ToArray()
    Totals          = [PSCustomObject]@{
      Stages  = [PSCustomObject]$StageTotals
      Notices = [PSCustomObject]$NoticeTotals
    }
  }
  $Result.PSTypeNames.Insert(0, 'WsusMaintenance.Report')

  $Result
  Write-Debug -Message:'[New-MaintenanceReport] Exiting'
}
