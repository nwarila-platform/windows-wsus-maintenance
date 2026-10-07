#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-MaintenanceRun.Budget'       = 'Time budget of {0} minute(s) reached; {1} stage(s) did not run and will run next time: {2}.'
  'Invoke-MaintenanceRun.GateAdvisory' = 'No recent SUSDB backup ({0}); the stages that delete or alter SUSDB content run anyway because backup.gate is Advisory.'
  'Invoke-MaintenanceRun.GateClosed'   = 'No recent SUSDB backup ({0}); the stages that delete or alter SUSDB content are skipped (backup.gate is Required).'
  'Invoke-MaintenanceRun.GateLog'      = 'Backup gate {0}: {1}.'
  'Invoke-MaintenanceRun.GateReason'   = 'skipped: no recent backup'
  'Invoke-MaintenanceRun.Permission'   = 'Stage {0} is skipped because the run identity lacks {1} in SUSDB.'
  'Invoke-MaintenanceRun.Skipped'      = 'Stage skipped: {0}.'
  'Invoke-MaintenanceRun.Unexpected'   = 'The run stopped early because of an unexpected error: {0}'
}

Function Invoke-MaintenanceRun {
  <#
    .SYNOPSIS
        Plans and executes the stages of one run.

    .DESCRIPTION
        Builds the stage plan and runs each stage in order inside its own error boundary,
        within the time budget. Every enabled stage runs on every run and acts only on
        what is due, so nothing is carried between runs: a stage the budget stopped from
        starting is reported and simply runs again next time. Anything unexpected outside
        a stage stops the loop and is returned as an Error notice together with every
        outcome gathered so far; this function never throws for it. The server facts from
        discovery gate the plan (replica, unknown tier, missing permissions); each stage skipped
        for a missing permission raises a Warning notice before the first stage starts, and
        every handler receives the server facts in its context. Before the first stage that deletes
        or alters SUSDB content, the backup gate is evaluated once (Test-BackupGate): when it is
        Required and closed those stages are skipped with "skipped: no recent backup" and a High
        notice; when it is Advisory they run and a Warning notice is raised.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER Events
        The event channel of the run (New-MaintenanceEventChannel), or null. Stage handlers
        receive it in their context to write stage events.

    .PARAMETER Log
        The run log, or null. Stage starts, ends, errors and items are written to it, and
        stage handlers receive it in their context to log their progress.

    .PARAMETER RemoveCustomIndexes
        Make the CustomIndexes stage drop the indexes this script created instead of creating
        missing ones.

    .PARAMETER RunStart
        The run's start time, local.

    .PARAMETER Server
        Server facts from discovery: Tier, Role, Environment, Permission, UpdateServer, Database
        and CommandTimeoutSeconds; null before discovery.

    .PARAMETER Stage
        Canonical stage names given with -Stage; empty means every enabled stage.

    .EXAMPLE
        Invoke-MaintenanceRun -Configuration $Effective -RunStart (Get-MaintenanceTime)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-maintenancerun',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
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
    [PSCustomObject]
    $Events = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Log = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Boolean]
    $RemoveCustomIndexes = $False,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $RunStart,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Server = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Stage = @()
  )

  Write-Debug -Message:'[Invoke-MaintenanceRun] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Blocked = $False
  [PSCustomObject]$Private:Context = $Null
  [PSCustomObject]$Private:Gate = $Null
  [System.Object]$Private:Deadline = $Null
  [System.Boolean]$Private:DryRun = [System.Boolean]$Configuration.run.dryRun
  [System.Collections.Generic.List[System.String]]$Private:NotRunNames = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Outcome = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Outcomes = $Null
  [PSCustomObject[]]$Private:Plan = @()
  [PSCustomObject]$Private:Result = $Null

  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Outcomes = [System.Collections.Generic.List[PSCustomObject]]::new()
  $NotRunNames = [System.Collections.Generic.List[System.String]]::new()

  If ($Configuration.run.maxDurationMinutes -gt 0) {
    $Deadline = $RunStart.AddMinutes($Configuration.run.maxDurationMinutes)
  }

  Try {
    $Plan = @(
      Get-MaintenanceStagePlan `
        -Configuration:$Configuration `
        -MissingPermission:(Get-MaintenancePropertyValue -InputObject:(Get-MaintenancePropertyValue -InputObject:$Server -Name:'Permission' -Default:$Null) -Name:'MissingByStage' -Default:$Null) `
        -Stage:$Stage `
        -Tier:([System.String](Get-MaintenancePropertyValue -InputObject:$Server -Name:'Tier' -Default:''))
    )

    # Permission shortfalls are reported before any stage starts.
    ForEach ($Entry In $Plan) {
      If (@($Entry.Missing).Count -gt 0) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-MaintenanceRun.Permission'] -f $Entry.Name, (@($Entry.Missing) -join ', ')) -Severity:'Warning' -Stage:$Entry.Name))
        Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceRun.Permission'] -f $Entry.Name, (@($Entry.Missing) -join ', ')) -Stage:$Entry.Name
      }
    }

    ForEach ($Entry In $Plan) {
      If ($Entry.Mode -eq 'Skip') {
        $Outcome = New-MaintenanceStageOutcome -Reason:$Entry.Reason -Stage:$Entry -Status:'Skipped'
        Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceRun.Skipped'] -f $Entry.Reason) -Stage:$Entry.Name
      } Else {
        $Blocked = $False
        If (($Entry.AltersDatabase -eq $True) -and ($Configuration.backup.gate -ne 'Off')) {
          If ($Null -eq $Gate) {
            $Gate = Test-BackupGate -Configuration:$Configuration -Log:$Log -Outcome:$Outcomes.ToArray() -Server:$Server
            If ($Gate.Satisfied -eq $True) {
              Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceRun.GateLog'] -f 'open', $Gate.Detail)
            } ElseIf ($Gate.Mode -eq 'Required') {
              Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceRun.GateLog'] -f 'closed', $Gate.Detail)
              $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-MaintenanceRun.GateClosed'] -f $Gate.Detail) -Severity:'High'))
            } Else {
              Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceRun.GateLog'] -f 'advisory', $Gate.Detail)
              $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-MaintenanceRun.GateAdvisory'] -f $Gate.Detail) -Severity:'Warning'))
            }
          }

          $Blocked = ($Gate.Satisfied -eq $False) -and ($Gate.Mode -eq 'Required')
        }
      }

      If (($Entry.Mode -ne 'Skip') -and ($Blocked -eq $True)) {
        $Outcome = New-MaintenanceStageOutcome -Reason:$Script:Message['Invoke-MaintenanceRun.GateReason'] -Stage:$Entry -Status:'Skipped'
        Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceRun.Skipped'] -f $Script:Message['Invoke-MaintenanceRun.GateReason']) -Stage:$Entry.Name
      } ElseIf ($Entry.Mode -ne 'Skip') {
        $Context = [PSCustomObject]@{
          StageName           = [System.String]$Entry.Name
          DryRun              = [System.Boolean]$DryRun
          Configuration       = $Configuration
          Deadline            = $Deadline
          RunStart            = $RunStart
          Log                 = $Log
          Server              = $Server
          RemoveCustomIndexes = [System.Boolean]$RemoveCustomIndexes
          Events              = $Events
        }
        $Outcome = Invoke-MaintenanceStage -Context:$Context -Handler:(Get-MaintenanceStageHandler -Name:$Entry.Name) -Log:$Log -Stage:$Entry
      }

      $Outcomes.Add($Outcome)
      ForEach ($StageNotice In @($Outcome.Notices)) {
        $Notices.Add($StageNotice)
      }

      If ($Outcome.Status -eq 'NotRun') {
        $NotRunNames.Add($Outcome.Name)
      }
    }

    If ($NotRunNames.Count -gt 0) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-MaintenanceRun.Budget'] -f $Configuration.run.maxDurationMinutes, $NotRunNames.Count, ($NotRunNames -join ', ')) -Severity:'Warning'))
    }
  } Catch {
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-MaintenanceRun.Unexpected'] -f $PSItem.Exception.Message) -Severity:'Error'))
  }

  # It's always desirable to explicitly set the Result object with its desired class as close
  #   to the soft return to ensure the output is predictable and easily traceable.
  [PSCustomObject]$Result = [PSCustomObject]@{
    Plan     = [PSCustomObject[]]$Plan
    Outcomes = [PSCustomObject[]]$Outcomes.ToArray()
    Notices  = [PSCustomObject[]]$Notices.ToArray()
    Deadline = $Deadline
    DryRun   = [System.Boolean]$DryRun
  }
  $Result
  Write-Debug -Message:'[Invoke-MaintenanceRun] Exiting'
}
