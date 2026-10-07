#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-MaintenanceStage.Budget'      = 'time budget reached before the stage could start'
  'Invoke-MaintenanceStage.ErrorLog'    = 'Stage error at {0}: {1}'
  'Invoke-MaintenanceStage.Failed'      = 'stage error'
  'Invoke-MaintenanceStage.FinishedLog' = 'Stage finished: {0} in {1} s.'
  'Invoke-MaintenanceStage.ItemLog'     = 'Item: {0}'
  'Invoke-MaintenanceStage.NotRunLog'   = 'Stage not run: {0}.'
  'Invoke-MaintenanceStage.ResultLog'   = 'Result: {0}'
  'Invoke-MaintenanceStage.SkippedLog'  = 'Stage skipped: {0}.'
  'Invoke-MaintenanceStage.StartedLog'  = 'Stage started.'
  'Invoke-MaintenanceStage.Unavailable' = 'not available in this release'
}

Function Invoke-MaintenanceStage {
  <#
    .SYNOPSIS
        Runs one planned stage inside its own error boundary.

    .DESCRIPTION
        Starts the stage only while the time budget lasts; otherwise records it as NotRun.
        Runs the stage's handler and records its status, counters, items, message, notices
        and duration. An error inside the stage is caught and recorded with the stage name,
        the error text and the time, so the run moves on to the next stage. A stage with
        no handler in this build is recorded as Skipped. The run log records the start, the
        end with status and duration, any error, the stage's message and every item, which
        the report may list only in part.

    .PARAMETER Context
        Stage context passed to the handler; its Deadline bounds the run.

    .PARAMETER Handler
        Script block that carries out the stage, or null.

    .PARAMETER Log
        The run log, or null.

    .PARAMETER Stage
        The plan entry of a stage that is to run.

    .EXAMPLE
        Invoke-MaintenanceStage -Stage $Entry -Handler (Get-MaintenanceStageHandler -Name $Entry.Name) -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-maintenancestage',
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
    $Context,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Management.Automation.ScriptBlock]
    $Handler = $Null,

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
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Stage
  )

  Write-Debug -Message:'[Invoke-MaintenanceStage] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Counts = $Null
  [System.Double]$Private:DurationSeconds = 0
  [System.String]$Private:ErrorMessage = [System.String]::Empty
  [System.Object]$Private:ErrorTime = $Null
  [System.Object]$Private:HandlerResult = $Null
  [System.String[]]$Private:Items = @()
  [PSCustomObject[]]$Private:Notices = @()
  [System.String]$Private:OutcomeMessage = [System.String]::Empty
  [System.Object[]]$Private:Output = @()
  [System.String]$Private:Reason = $Stage.Reason
  [System.DateTime]$Private:StartedAt = [System.DateTime]::MinValue
  [System.String]$Private:Status = 'Success'
  [System.Collections.Hashtable]$Private:StatusLevels = @{ Success = 'Information'; Warning = 'Warning'; Error = 'Error' }
  [PSCustomObject]$Private:Result = $Null

  If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
    [PSCustomObject]$Result = New-MaintenanceStageOutcome -Reason:$Script:Message['Invoke-MaintenanceStage.Budget'] -Stage:$Stage -Status:'NotRun'
    Write-MaintenanceLog -Level:'Warning' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceStage.NotRunLog'] -f $Result.Reason) -Stage:$Stage.Name
  } ElseIf ($Null -eq $Handler) {
    [PSCustomObject]$Result = New-MaintenanceStageOutcome -Reason:$Script:Message['Invoke-MaintenanceStage.Unavailable'] -Stage:$Stage -Status:'Skipped'
    Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceStage.SkippedLog'] -f $Result.Reason) -Stage:$Stage.Name
  } Else {
    $StartedAt = Get-MaintenanceTime
    Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:$Script:Message['Invoke-MaintenanceStage.StartedLog'] -Stage:$Stage.Name

    Try {
      $Output = @(& $Handler -Context:$Context)
      If ($Output.Count -gt 0) {
        $HandlerResult = $Output[-1]
      }
    } Catch {
      $Status = 'Error'
      $Reason = $Script:Message['Invoke-MaintenanceStage.Failed']
      $ErrorMessage = $PSItem.Exception.Message
      $ErrorTime = Get-MaintenanceTime
    }

    If ($Null -ne $HandlerResult) {
      If (($Status -ne 'Error') -and ($Null -ne $HandlerResult.PSObject.Properties['Status']) -and (@('Success', 'Warning', 'Error') -contains $HandlerResult.Status)) {
        $Status = [System.String]$HandlerResult.Status
      }

      If ($Null -ne $HandlerResult.PSObject.Properties['Counts']) {
        $Counts = $HandlerResult.Counts
      }

      If ($Null -ne $HandlerResult.PSObject.Properties['Items']) {
        $Items = [System.String[]]@($HandlerResult.Items | Where-Object -FilterScript { $Null -ne $PSItem })
      }

      If ($Null -ne $HandlerResult.PSObject.Properties['Message']) {
        $OutcomeMessage = [System.String]$HandlerResult.Message
      }

      If ($Null -ne $HandlerResult.PSObject.Properties['Notices']) {
        $Notices = [PSCustomObject[]]@($HandlerResult.Notices | Where-Object -FilterScript { $Null -ne $PSItem })
      }
    }

    $DurationSeconds = [System.Math]::Max([System.Double]0, ((Get-MaintenanceTime) - $StartedAt).TotalSeconds)

    [PSCustomObject]$Result = New-MaintenanceStageOutcome `
      -Counts:$Counts `
      -DurationSeconds:$DurationSeconds `
      -ErrorMessage:$ErrorMessage `
      -ErrorTime:$ErrorTime `
      -Item:$Items `
      -Message:$OutcomeMessage `
      -Notice:$Notices `
      -Reason:$Reason `
      -Stage:$Stage `
      -StartedAt:$StartedAt `
      -Status:$Status

    If ([System.String]::IsNullOrEmpty($ErrorMessage) -eq $False) {
      Write-MaintenanceLog -Level:'Error' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceStage.ErrorLog'] -f $ErrorTime.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture), $ErrorMessage) -Stage:$Stage.Name
    }

    If ([System.String]::IsNullOrEmpty($OutcomeMessage) -eq $False) {
      Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceStage.ResultLog'] -f $OutcomeMessage) -Stage:$Stage.Name
    }

    ForEach ($Entry In $Items) {
      Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-MaintenanceStage.ItemLog'] -f $Entry) -Stage:$Stage.Name
    }

    Write-MaintenanceLog -Level:$StatusLevels[$Status] -Log:$Log -Message:($Script:Message['Invoke-MaintenanceStage.FinishedLog'] -f $Status, $DurationSeconds.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)) -Stage:$Stage.Name
  }

  $Result
  Write-Debug -Message:'[Invoke-MaintenanceStage] Exiting'
}
