#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-WsusMaintenance.ApiGuidance'         = 'Check that the WSUS service and its IIS site are running and that the run identity is a WSUS administrator; set discovery.wsusHostName, discovery.wsusPort or discovery.wsusUseTls when WSUS listens elsewhere.'
  'Invoke-WsusMaintenance.Connected'           = 'WSUS administration interface at {0}; SUSDB at {1}'
  'Invoke-WsusMaintenance.ConnectedApi'        = 'WSUS administration interface at {0}; SUSDB not connected'
  'Invoke-WsusMaintenance.DatabaseGuidance'    = 'Check that the SQL Server service is running and that the run identity has a login in SUSDB; set discovery.sqlInstance or discovery.databaseName when they are not discovered correctly.'
  'Invoke-WsusMaintenance.Effective'           = 'Effective configuration: {0}'
  'Invoke-WsusMaintenance.Elevation'           = 'The run must be elevated or run as LocalSystem; nothing was changed. {0}'
  'Invoke-WsusMaintenance.ElevationGuidance'   = 'Run the scheduled task as SYSTEM with the highest privileges, or start the script from an elevated session.'
  'Invoke-WsusMaintenance.Environment'         = 'Environment: {0}; database {1}.'
  'Invoke-WsusMaintenance.EnvironmentFailed'   = 'This server is not a combination this release supports: {0}'
  'Invoke-WsusMaintenance.EnvironmentGuidance' = 'Run the script on Windows Server 2019, 2022 or 2025 with the WSUS role installed and SUSDB on SQL Server on the same server.'
  'Invoke-WsusMaintenance.FullRun'             = 'every enabled stage'
  'Invoke-WsusMaintenance.Invalid'             = "Configuration '{0}' is invalid ({1} problem(s)):{2}{3}"
  'Invoke-WsusMaintenance.InvalidGuidance'     = 'Correct each problem listed under Notices in the configuration document, then check it with -ValidateOnly before the next run.'
  'Invoke-WsusMaintenance.LockGuidance'        = 'Make sure the run identity may create the system-wide lock, then run again.'
  'Invoke-WsusMaintenance.LockHeld'            = 'Another run holds the lock; this run stops without changing anything.'
  'Invoke-WsusMaintenance.LogGuidance'         = 'Point log.folder at a folder the run identity can create and write, then run again.'
  'Invoke-WsusMaintenance.Overrides'           = 'Overrides: {0}.'
  'Invoke-WsusMaintenance.PermissionLog'       = 'Database permissions: {0}.'
  'Invoke-WsusMaintenance.PermissionUnchecked' = 'Database permissions could not be checked ({0}); each stage reports its own failure.'
  'Invoke-WsusMaintenance.PointApi'            = 'connection to the WSUS administration interface'
  'Invoke-WsusMaintenance.PointDatabase'       = 'connection to SUSDB'
  'Invoke-WsusMaintenance.PointElevation'      = 'elevation check'
  'Invoke-WsusMaintenance.PointEnvironment'    = 'environment discovery'
  'Invoke-WsusMaintenance.PointLock'           = 'taking of the run lock'
  'Invoke-WsusMaintenance.PointLog'            = 'opening of the run log'
  'Invoke-WsusMaintenance.PointSyncGuard'      = 'synchronization guard'
  'Invoke-WsusMaintenance.PointValidation'     = 'configuration validation'
  'Invoke-WsusMaintenance.RoleLog'             = 'Server role: {0}; upstream {1}; WSUS {2}.'
  'Invoke-WsusMaintenance.RoleUnknown'         = 'The server role could not be determined ({0}); every action that declines updates or changes approvals or computer groups is skipped.'
  'Invoke-WsusMaintenance.StageList'           = 'stage list {0}'
  'Invoke-WsusMaintenance.Started'             = 'Run started: {0}; dry run {1}; configuration {2}.'
  'Invoke-WsusMaintenance.StartedEvent'        = 'Run {0} started: {1}.'
  'Invoke-WsusMaintenance.SyncGuardFailed'     = 'The synchronization guard could not make sure that no synchronization runs: {0}.'
  'Invoke-WsusMaintenance.SyncGuardGuidance'   = 'Let the running synchronization finish, or move the synchronization schedule away from the maintenance window, then run again.'
}

Function Invoke-WsusMaintenance {
  <#
    .SYNOPSIS
        Runs one unattended WSUS maintenance pass.

    .DESCRIPTION
        Reads the configuration document, validates it completely together with the
        command-line options, builds the effective configuration, and emits one
        WsusMaintenance.RunResult whose ExitCode the entry point returns. An invalid
        configuration or invalid options stop the run before anything is changed, with
        every problem listed and the ConfigurationInvalid exit code. With -ValidateOnly
        the run stops after validation and writes no files and no events.

        Any other run first opens its run log, under a new run identifier, and chooses
        its report and summary folders; even an invalid configuration names them where it
        validly can, falling back to the built-in defaults. A log that cannot be written,
        an invalid configuration, a run that is not elevated and a lock that cannot be
        created each stop the run with a failure report, a summary and an event, and the
        matching exit code (PreconditionFailed or ConfigurationInvalid). When another run
        holds the lock, the run logs that and stops with LockHeld. Under the lock it discovers
        the environment (an unsupported combination stops the run), connects to the WSUS
        administration interface and to SUSDB, detects the server tier, checks the database
        permissions of each stage and runs the synchronization guard; a failed connection or
        a synchronization that will not stop also stops the run with a failure report and
        PreconditionFailed. It then writes the run-started event, plans and runs the stages,
        restarts the synchronization it stopped, closes the database connection and releases
        the lock on every path, including an unexpected error, and saves the report, the
        summary and the completion event.

    .PARAMETER ConfigPath
        Configuration document to read; defaults to the fixed path under
        %ProgramData%\NWarila\WsusMaintenance.

    .PARAMETER DryRun
        Report intended changes without changing anything.

    .PARAMETER ReportFolder
        Report folder for this run.

    .PARAMETER ReportFormat
        Report formats for this run.

    .PARAMETER Stage
        Run only these stages, in their fixed order. Without it every enabled stage runs.

    .PARAMETER ValidateOnly
        Validate the configuration and options, then stop.

    .PARAMETER Verbosity
        Log verbosity for this run.

    .EXAMPLE
        Invoke-WsusMaintenance -ConfigPath 'D:\Maintenance\maintenance.json' -ValidateOnly

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-wsusmaintenance',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $ConfigPath,

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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $ReportFolder,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Text', 'Html')]
    [System.String[]]
    $ReportFormat,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $Stage,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $ValidateOnly,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [System.String]
    $Verbosity
  )

  Write-Debug -Message:'[Invoke-WsusMaintenance] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Connection = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Discovery = $Null
  [PSCustomObject]$Private:Document = $Null
  [PSCustomObject]$Private:Effective = $Null
  [System.Boolean]$Private:Elevated = $False
  [PSCustomObject]$Private:Environment = $Null
  [System.String]$Private:ElevationDetail = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [PSCustomObject]$Private:Execution = $Null
  [PSCustomObject]$Private:Guard = $Null
  [System.Object]$Private:Lock = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Output = $Null
  [System.Collections.Hashtable]$Private:OverrideParameters = $Null
  [PSCustomObject]$Private:Permission = $Null
  [PSCustomObject]$Private:Published = $Null
  [PSCustomObject]$Private:Resolution = $Null
  [PSCustomObject]$Private:Restore = $Null
  [System.Boolean]$Private:Restored = $False
  [PSCustomObject]$Private:Role = $Null
  [System.String]$Private:ResolvedPath = [System.String]::Empty
  [PSCustomObject]$Private:RunRecord = $Null
  [System.String]$Private:RunDescription = [System.String]::Empty
  [System.String]$Private:RunId = [System.String]::Empty
  [System.DateTime]$Private:RunStart = [System.DateTime]::MinValue
  [PSCustomObject]$Private:Server = $Null
  [PSCustomObject]$Private:Setting = $Null
  [System.String]$Private:Status = [System.String]::Empty
  [PSCustomObject]$Private:Validation = $Null
  [PSCustomObject]$Private:ValidationSummary = $Null
  [System.String[]]$Private:Warnings = @()
  [PSCustomObject]$Private:Result = $Null

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()

  If ($PSBoundParameters.ContainsKey('ConfigPath') -eq $True) {
    $ResolvedPath = $ConfigPath
  } Else {
    $ResolvedPath = Get-MaintenanceDefaultConfigurationPath
  }

  # A document that cannot be read is one more configuration problem: it is reported with the
  #   option errors, and a scheduled run still delivers a failure report.
  Try {
    $Document = Read-MaintenanceConfiguration -Path:$ResolvedPath
  } Catch {
    If (([System.String]$PSItem.FullyQualifiedErrorId -like 'ConfigurationInvalid,*') -eq $False) {
      Throw
    }

    $Errors.Add($PSItem.Exception.Message)
  }

  If ($Null -ne $Document) {
    $Validation = Test-MaintenanceConfiguration -Document:$Document
    $Warnings = [System.String[]]@($Validation.Warnings)
    ForEach ($ValidationError In $Validation.Errors) {
      $Errors.Add($ValidationError)
    }

    If ($Validation.IsValid -eq $True) {
      $Effective = ConvertTo-MaintenanceEffectiveConfiguration -Document:$Document
    }
  }

  # Only options the caller actually gave are forwarded, so an override is recorded only when
  #   one was requested.
  $OverrideParameters = @{
    Configuration = $Effective
  }
  ForEach ($Name In @('ConfigPath', 'DryRun', 'ReportFolder', 'ReportFormat', 'Stage', 'Verbosity')) {
    If ($PSBoundParameters.ContainsKey($Name) -eq $True) {
      $OverrideParameters[$Name] = $PSBoundParameters[$Name]
    }
  }

  $Resolution = Resolve-MaintenanceOverride @OverrideParameters
  ForEach ($OptionError In $Resolution.Errors) {
    $Errors.Add($OptionError)
  }

  $ValidationSummary = [PSCustomObject]@{
    ConfigurationPath = [System.String]$ResolvedPath
    IsValid           = [System.Boolean]($Errors.Count -eq 0)
    Errors            = [System.String[]]$Errors.ToArray()
    Warnings          = [System.String[]]$Warnings
    Overrides         = [System.String[]]$Resolution.Overrides
    Stages            = [System.String[]]$Resolution.Stages
    ValidateOnly      = [System.Boolean]$ValidateOnly.IsPresent
    Configuration     = $Resolution.Configuration
  }

  ForEach ($ValidationWarning In $Warnings) {
    $Notices.Add((New-MaintenanceNotice -Message:$ValidationWarning -Severity:'Warning'))
  }

  If ($ValidateOnly.IsPresent -eq $True) {
    If ($Errors.Count -gt 0) {
      New-ErrorRecord `
        -Category:([System.Management.Automation.ErrorCategory]::InvalidData) `
        -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
        -IsFatal `
        -Message:($Script:Message['Invoke-WsusMaintenance.Invalid'] -f $ResolvedPath, $Errors.Count, [System.Environment]::NewLine, ($Errors -join [System.Environment]::NewLine)) `
        -TargetObject:$ValidationSummary
    }

    [PSCustomObject]$Result = New-MaintenanceRunResult `
      -Notice:$Notices.ToArray() `
      -Status:(Resolve-MaintenanceRunStatus -Notice:$Notices.ToArray()) `
      -Validation:$ValidationSummary
  } Else {
    $RunStart = Get-MaintenanceTime
    $RunId = New-MaintenanceRunId -RunStart:$RunStart
    $Setting = Get-MaintenanceOutputSetting `
      -Configuration:$Resolution.Configuration `
      -Document:$Document `
      -ReportFolder:([System.String]$PSBoundParameters['ReportFolder']) `
      -ReportFormat:([System.String[]]@($PSBoundParameters['ReportFormat'] | Where-Object -FilterScript { $Null -ne $PSItem })) `
      -Verbosity:([System.String]$PSBoundParameters['Verbosity'])
    $Output = Open-MaintenanceRunOutput -RunId:$RunId -Setting:$Setting
    ForEach ($FolderNotice In $Output.Notices) {
      $Notices.Add($FolderNotice)
    }

    $Discovery = [System.Collections.Specialized.OrderedDictionary]::new()
    $Discovery['Identity'] = Get-MaintenanceIdentity

    $RunDescription = $Script:Message['Invoke-WsusMaintenance.FullRun']
    If (@($Resolution.Stages).Count -gt 0) {
      $RunDescription = $Script:Message['Invoke-WsusMaintenance.StageList'] -f (@($Resolution.Stages) -join ', ')
    }

    Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Invoke-WsusMaintenance.Started'] -f $RunDescription, ($DryRun.IsPresent -or (($Null -ne $Resolution.Configuration) -and ($Resolution.Configuration.run.dryRun -eq $True))), $ResolvedPath)
    If (@($Resolution.Overrides).Count -gt 0) {
      Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Invoke-WsusMaintenance.Overrides'] -f (@($Resolution.Overrides) -join '; '))
    }

    If ([System.String]::IsNullOrEmpty($Output.Log.Error) -eq $False) {
      Stop-MaintenanceRun `
        -Category:([System.Management.Automation.ErrorCategory]::WriteError) `
        -Discovery:([PSCustomObject]$Discovery) `
        -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
        -Guidance:$Script:Message['Invoke-WsusMaintenance.LogGuidance'] `
        -Message:$Output.Log.Error `
        -Notice:$Notices.ToArray() `
        -Output:$Output `
        -Point:$Script:Message['Invoke-WsusMaintenance.PointLog'] `
        -Run:(New-MaintenanceRunRecord -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
        -TargetObject:$ValidationSummary `
        -Validation:$ValidationSummary
    }

    If ($Errors.Count -gt 0) {
      ForEach ($ConfigurationError In $Errors) {
        $Notices.Add((New-MaintenanceNotice -Message:$ConfigurationError -Severity:'Error'))
      }

      Stop-MaintenanceRun `
        -Category:([System.Management.Automation.ErrorCategory]::InvalidData) `
        -Discovery:([PSCustomObject]$Discovery) `
        -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
        -Guidance:$Script:Message['Invoke-WsusMaintenance.InvalidGuidance'] `
        -Message:($Script:Message['Invoke-WsusMaintenance.Invalid'] -f $ResolvedPath, $Errors.Count, [System.Environment]::NewLine, ($Errors -join [System.Environment]::NewLine)) `
        -Notice:$Notices.ToArray() `
        -Output:$Output `
        -Point:$Script:Message['Invoke-WsusMaintenance.PointValidation'] `
        -Run:(New-MaintenanceRunRecord -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
        -TargetObject:$ValidationSummary `
        -Validation:$ValidationSummary
    }

    Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Invoke-WsusMaintenance.Effective'] -f (ConvertTo-Json -InputObject:$Resolution.Configuration -Depth:32 -Compress))

    Try {
      $Elevated = Test-MaintenanceElevation
    } Catch {
      $Elevated = $False
      $ElevationDetail = $PSItem.Exception.Message
    }

    If ($Elevated -eq $False) {
      Stop-MaintenanceRun `
        -Category:([System.Management.Automation.ErrorCategory]::PermissionDenied) `
        -Discovery:([PSCustomObject]$Discovery) `
        -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
        -Guidance:$Script:Message['Invoke-WsusMaintenance.ElevationGuidance'] `
        -Message:($Script:Message['Invoke-WsusMaintenance.Elevation'] -f $ElevationDetail).Trim() `
        -Notice:$Notices.ToArray() `
        -Output:$Output `
        -Point:$Script:Message['Invoke-WsusMaintenance.PointElevation'] `
        -Run:(New-MaintenanceRunRecord -DryRun:$Resolution.Configuration.run.dryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
        -TargetObject:$ValidationSummary `
        -Validation:$ValidationSummary
    }

    Try {
      $Lock = Enter-MaintenanceLock -Name:'Global\Invoke-WsusMaintenance'
    } Catch {
      If (([System.String]$PSItem.FullyQualifiedErrorId -like 'LockHeld,*') -eq $True) {
        Write-MaintenanceLog -Level:'Warning' -Log:$Output.Log -Message:$Script:Message['Invoke-WsusMaintenance.LockHeld']
        Throw
      }

      Stop-MaintenanceRun `
        -Category:([System.Management.Automation.ErrorCategory]::ResourceUnavailable) `
        -Discovery:([PSCustomObject]$Discovery) `
        -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
        -Guidance:$Script:Message['Invoke-WsusMaintenance.LockGuidance'] `
        -Message:$PSItem.Exception.Message `
        -Notice:$Notices.ToArray() `
        -Output:$Output `
        -Point:$Script:Message['Invoke-WsusMaintenance.PointLock'] `
        -Run:(New-MaintenanceRunRecord -DryRun:$Resolution.Configuration.run.dryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
        -TargetObject:$ValidationSummary `
        -Validation:$ValidationSummary
    }

    $Restored = $False
    Try {
      $Environment = Get-WsusEnvironment -Configuration:$Resolution.Configuration -OperatingSystem:(Get-MaintenanceOperatingSystem) -Setup:(Get-WsusSetupValue)
      $Discovery['Database'] = $Environment.Description
      Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Invoke-WsusMaintenance.Environment'] -f $Environment.OperatingSystem, $Environment.Description)
      If (@($Environment.Problems).Count -gt 0) {
        Stop-MaintenanceRun `
          -Category:([System.Management.Automation.ErrorCategory]::NotInstalled) `
          -Discovery:([PSCustomObject]$Discovery) `
          -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
          -Guidance:$Script:Message['Invoke-WsusMaintenance.EnvironmentGuidance'] `
          -Message:($Script:Message['Invoke-WsusMaintenance.EnvironmentFailed'] -f (@($Environment.Problems) -join ' ')) `
          -Notice:$Notices.ToArray() `
          -Output:$Output `
          -Point:$Script:Message['Invoke-WsusMaintenance.PointEnvironment'] `
          -Run:(New-MaintenanceRunRecord -DryRun:$Resolution.Configuration.run.dryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
          -TargetObject:$ValidationSummary `
          -Validation:$ValidationSummary
      }

      $Connection = Connect-MaintenanceServer -Configuration:$Resolution.Configuration -Environment:$Environment
      $Discovery['Endpoint'] = $Connection.Endpoint
      If ($Null -ne $Connection.DatabaseConnectedAt) {
        $Discovery['Connection'] = $Script:Message['Invoke-WsusMaintenance.Connected'] -f $Connection.ApiConnectedAt.ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture), $Connection.DatabaseConnectedAt.ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
      } ElseIf ($Null -ne $Connection.ApiConnectedAt) {
        $Discovery['Connection'] = $Script:Message['Invoke-WsusMaintenance.ConnectedApi'] -f $Connection.ApiConnectedAt.ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
      }

      If ($Connection.Point -eq 'Api') {
        Stop-MaintenanceRun `
          -Category:([System.Management.Automation.ErrorCategory]::ConnectionError) `
          -Discovery:([PSCustomObject]$Discovery) `
          -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
          -Guidance:$Script:Message['Invoke-WsusMaintenance.ApiGuidance'] `
          -Message:$Connection.Error `
          -Notice:$Notices.ToArray() `
          -Output:$Output `
          -Point:$Script:Message['Invoke-WsusMaintenance.PointApi'] `
          -Run:(New-MaintenanceRunRecord -DryRun:$Resolution.Configuration.run.dryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
          -TargetObject:$ValidationSummary `
          -Validation:$ValidationSummary
      } ElseIf ($Connection.Point -eq 'Database') {
        Stop-MaintenanceRun `
          -Category:([System.Management.Automation.ErrorCategory]::ConnectionError) `
          -Discovery:([PSCustomObject]$Discovery) `
          -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
          -Guidance:$Script:Message['Invoke-WsusMaintenance.DatabaseGuidance'] `
          -Message:$Connection.Error `
          -Notice:$Notices.ToArray() `
          -Output:$Output `
          -Point:$Script:Message['Invoke-WsusMaintenance.PointDatabase'] `
          -Run:(New-MaintenanceRunRecord -DryRun:$Resolution.Configuration.run.dryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
          -TargetObject:$ValidationSummary `
          -Validation:$ValidationSummary
      }

      $Role = Get-WsusServerRole -UpdateServer:$Connection.UpdateServer
      $Discovery['WsusVersion'] = $Role.Version
      $Discovery['Role'] = $Role.Description
      $Discovery['Upstream'] = $Role.Upstream
      Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Invoke-WsusMaintenance.RoleLog'] -f $Role.Description, $Role.Upstream, $Role.Version)
      If ([System.String]::IsNullOrEmpty($Role.Error) -eq $False) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-WsusMaintenance.RoleUnknown'] -f $Role.Error) -Severity:'Warning'))
      }

      $Permission = Test-SusdbPermission -Connection:$Connection.Database -Log:$Output.Log -TimeoutSeconds:([System.Int32]$Resolution.Configuration.run.databaseCommandTimeoutSeconds)
      $Discovery['Permissions'] = $Permission.Summary
      Write-MaintenanceLog -Level:'Information' -Log:$Output.Log -Message:($Script:Message['Invoke-WsusMaintenance.PermissionLog'] -f $Permission.Summary)
      If ($Permission.Checked -eq $False) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-WsusMaintenance.PermissionUnchecked'] -f $Permission.Error) -Severity:'Warning'))
      }

      $Guard = Invoke-SynchronizationGuard -Configuration:$Resolution.Configuration -Log:$Output.Log -UpdateServer:$Connection.UpdateServer
      $Discovery['Synchronization'] = $Guard.Summary
      If ($Guard.Succeeded -eq $False) {
        $Restore = Restore-Synchronization -Guard:$Guard -Log:$Output.Log -UpdateServer:$Connection.UpdateServer
        $Restored = $True
        $Discovery['Synchronization'] = $Restore.Summary
        ForEach ($RestoreNotice In $Restore.Notices) {
          $Notices.Add($RestoreNotice)
        }

        Stop-MaintenanceRun `
          -Category:([System.Management.Automation.ErrorCategory]::ResourceBusy) `
          -Discovery:([PSCustomObject]$Discovery) `
          -ErrorId:([MaintenanceExitCode]::PreconditionFailed) `
          -Guidance:$Script:Message['Invoke-WsusMaintenance.SyncGuardGuidance'] `
          -Message:($Script:Message['Invoke-WsusMaintenance.SyncGuardFailed'] -f $Guard.Summary) `
          -Notice:$Notices.ToArray() `
          -Output:$Output `
          -Point:$Script:Message['Invoke-WsusMaintenance.PointSyncGuard'] `
          -Run:(New-MaintenanceRunRecord -DryRun:$Resolution.Configuration.run.dryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages) `
          -TargetObject:$ValidationSummary `
          -Validation:$ValidationSummary
      }

      $Server = [PSCustomObject]@{
        Tier                  = [System.String]$Role.Tier
        Role                  = $Role
        Environment           = $Environment
        Permission            = $Permission
        UpdateServer          = $Connection.UpdateServer
        Database              = $Connection.Database
        CommandTimeoutSeconds = [System.Int32]$Resolution.Configuration.run.databaseCommandTimeoutSeconds
      }

      Write-MaintenanceEvent -Channel:$Output.Events -Kind:'runStarted' -Message:($Script:Message['Invoke-WsusMaintenance.StartedEvent'] -f $RunId, $RunDescription)
      $Execution = Invoke-MaintenanceRun `
        -Configuration:$Resolution.Configuration `
        -Log:$Output.Log `
        -RunStart:$RunStart `
        -Server:$Server `
        -Stage:$Resolution.Stages

      $Restore = Restore-Synchronization -Guard:$Guard -Log:$Output.Log -UpdateServer:$Connection.UpdateServer
      $Restored = $True
      $Discovery['Synchronization'] = $Restore.Summary
      ForEach ($RestoreNotice In $Restore.Notices) {
        $Notices.Add($RestoreNotice)
      }
    } Finally {
      # An unexpected failure must still give back the synchronization the guard stopped.
      If (($Null -ne $Guard) -and ($Restored -eq $False)) {
        $Null = Restore-Synchronization -Guard:$Guard -Log:$Output.Log -UpdateServer:$Connection.UpdateServer
      }

      Disconnect-MaintenanceServer -Connection:$Connection
      Exit-MaintenanceLock -Lock:$Lock
    }

    ForEach ($RunNotice In $Execution.Notices) {
      $Notices.Add($RunNotice)
    }

    $RunRecord = New-MaintenanceRunRecord -Deadline:$Execution.Deadline -DryRun:$Execution.DryRun -RunId:$RunId -RunStart:$RunStart -Stage:$Resolution.Stages
    $Status = Resolve-MaintenanceRunStatus -Notice:$Notices.ToArray() -Stage:$Execution.Outcomes
    $Published = Publish-MaintenanceRunOutput `
      -Discovery:([PSCustomObject]$Discovery) `
      -ExitCode:([System.Int32](New-MaintenanceRunResult -Status:$Status -Validation:$ValidationSummary).ExitCode) `
      -Notice:$Notices.ToArray() `
      -Output:$Output `
      -Run:$RunRecord `
      -Stage:$Execution.Outcomes `
      -Status:$Status `
      -Validation:$ValidationSummary
    $RunRecord.Artifacts = [PSCustomObject]@{
      Log     = [System.String]$Output.Log.Path
      Reports = [System.String[]]$Published.ReportPaths
      Summary = [System.String]$Published.SummaryPath
    }

    [PSCustomObject]$Result = New-MaintenanceRunResult `
      -Notice:$Notices.ToArray() `
      -Run:$RunRecord `
      -Stage:$Execution.Outcomes `
      -Status:$Status `
      -Validation:$ValidationSummary
  }

  $Result
  Write-Debug -Message:'[Invoke-WsusMaintenance] Exiting'
}
