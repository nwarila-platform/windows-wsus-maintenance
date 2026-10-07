#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-WsusBuiltInCleanup.Budget'                            = 'Time budget reached before the built-in cleanup option(s) {0} could start; they run on the next run.'
  'Invoke-WsusBuiltInCleanup.CatalogNote'                       = 'Unneeded content file cleanup also deletes update files imported manually from the Microsoft Update Catalog.'
  'Invoke-WsusBuiltInCleanup.CleanupObsoleteComputers'          = 'obsolete computers'
  'Invoke-WsusBuiltInCleanup.CleanupObsoleteComputersResult'    = '{0} computer(s) deleted'
  'Invoke-WsusBuiltInCleanup.CleanupObsoleteUpdates'            = 'obsolete updates'
  'Invoke-WsusBuiltInCleanup.CleanupObsoleteUpdatesResult'      = '{0} update(s) deleted'
  'Invoke-WsusBuiltInCleanup.CleanupUnneededContentFiles'       = 'unneeded content files'
  'Invoke-WsusBuiltInCleanup.CleanupUnneededContentFilesResult' = '{0} freed'
  'Invoke-WsusBuiltInCleanup.CompressUpdates'                   = 'obsolete update revisions'
  'Invoke-WsusBuiltInCleanup.CompressUpdatesResult'             = '{0} update(s) with obsolete revisions removed'
  'Invoke-WsusBuiltInCleanup.DeclineExpiredUpdates'             = 'expired-update decline'
  'Invoke-WsusBuiltInCleanup.DeclineExpiredUpdatesResult'       = '{0} update(s) declined'
  'Invoke-WsusBuiltInCleanup.DeclineSupersededUpdates'          = 'superseded-update decline'
  'Invoke-WsusBuiltInCleanup.DeclineSupersededUpdatesResult'    = '{0} update(s) declined'
  'Invoke-WsusBuiltInCleanup.DrySummary'                        = 'Would run {0} built-in cleanup option(s); nothing was changed.'
  'Invoke-WsusBuiltInCleanup.Failed'                            = 'failed after {0} attempt(s): {1}'
  'Invoke-WsusBuiltInCleanup.FailedNotice'                      = 'The built-in cleanup option {0} failed after {1} attempt(s): {2}'
  'Invoke-WsusBuiltInCleanup.Item'                              = '{0}: {1}'
  'Invoke-WsusBuiltInCleanup.NotStarted'                        = 'not started: time budget reached'
  'Invoke-WsusBuiltInCleanup.Off'                               = 'off'
  'Invoke-WsusBuiltInCleanup.Rejected'                          = 'rejected by server role: {0}'
  'Invoke-WsusBuiltInCleanup.RejectedNotice'                    = 'The built-in cleanup option {0} was refused, as expected on a replica (rejected by server role): {1}'
  'Invoke-WsusBuiltInCleanup.Replica'                           = 'skipped: replica'
  'Invoke-WsusBuiltInCleanup.Retry'                             = 'Built-in cleanup option {0} timed out on attempt {1} of {2}: {3} Retrying.'
  'Invoke-WsusBuiltInCleanup.RoleUnknown'                       = 'skipped: server role unknown'
  'Invoke-WsusBuiltInCleanup.Summary'                           = 'Ran {0} of {1} built-in cleanup option(s); {2} failed; {3} freed.'
  'Invoke-WsusBuiltInCleanup.Took'                              = '{0} in {1} s (attempt {2})'
  'Invoke-WsusBuiltInCleanup.WouldRun'                          = 'would run'
}

Function Invoke-WsusBuiltInCleanup {
  <#
    .SYNOPSIS
        Runs the built-in WSUS cleanup, one option at a time.

    .DESCRIPTION
        Runs each enabled option of the WSUS cleanup manager (IUpdateServer.GetCleanupManager and
        PerformCleanup) in a cleanup scope of its own, in this order: superseded-update decline,
        expired-update decline, obsolete updates, obsolete revisions (compress updates), obsolete
        computers and unneeded content files. Each option is isolated: a time-out is retried up to
        builtInCleanup.timeoutRetries times, a failure is recorded and the next option still runs, and
        the count reported for the option is the one counter of the cleanup results that belongs to it
        (the disk space freed for unneeded content files). The two decline options are suppressed on a
        replica ("skipped: replica") and when the server role is unknown. On a replica any other refusal
        is reported as "rejected by server role" with a warning. The time budget is checked before each
        option; an option cannot be interrupted once started. A dry run calls nothing and lists the
        options that would run.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-WsusBuiltInCleanup -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-wsusbuiltincleanup',
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
    $Context
  )

  Write-Debug -Message:'[Invoke-WsusBuiltInCleanup] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Attempt = 0
  [System.Boolean]$Private:ContentFiles = $False
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Boolean]$Private:Done = $False
  [System.Int32]$Private:Enabled = 0
  [System.String]$Private:Failure = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.String]$Private:Label = [System.String]::Empty
  [System.Object]$Private:Manager = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Collections.Generic.List[System.String]]$Private:NotStarted = $Null
  [System.DateTime]$Private:OptionStarted = [System.DateTime]::MinValue
  [PSCustomObject[]]$Private:Options = @()
  [System.Object]$Private:Outcome = $Null
  [System.Boolean]$Private:Rejected = $False
  [System.Int32]$Private:Retries = 0
  [System.Object]$Private:Scope = $Null
  [System.Object]$Private:Settings = $Null
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.String]$Private:Text = [System.String]::Empty
  [System.String]$Private:Tier = [System.String]::Empty
  [System.Boolean]$Private:TimedOut = $False
  [System.Object]$Private:UpdateServer = $Null
  [System.Int64]$Private:Value = 0
  [PSCustomObject]$Private:Result = $Null

  $UpdateServer = Get-WsusConnection -Context:$Context
  $Settings = $Context.Configuration.builtInCleanup
  $Retries = [System.Int32]$Settings.timeoutRetries
  $Tier = [System.String](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'Tier' -Default:'')
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $NotStarted = [System.Collections.Generic.List[System.String]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('SupersededUpdatesDeclined', 'ExpiredUpdatesDeclined', 'ObsoleteUpdatesDeleted', 'UpdatesCompressed', 'ObsoleteComputersDeleted', 'DiskSpaceFreed', 'OptionsRun', 'OptionsFailed', 'Attempts')) {
    $Counts[$Name] = [System.Int64]0
  }

  # The cleanup scope options and their counters are those of the WSUS administration API:
  #   https://learn.microsoft.com/previous-versions/windows/desktop/aa354275(v=vs.85)
  $Options = @(
    [PSCustomObject]@{ Option = 'DeclineSupersededUpdates'; Setting = 'declineSupersededUpdates'; Counter = 'SupersededUpdatesDeclined'; Decline = $True }
    [PSCustomObject]@{ Option = 'DeclineExpiredUpdates'; Setting = 'declineExpiredUpdates'; Counter = 'ExpiredUpdatesDeclined'; Decline = $True }
    [PSCustomObject]@{ Option = 'CleanupObsoleteUpdates'; Setting = 'obsoleteUpdates'; Counter = 'ObsoleteUpdatesDeleted'; Decline = $False }
    [PSCustomObject]@{ Option = 'CompressUpdates'; Setting = 'compressUpdates'; Counter = 'UpdatesCompressed'; Decline = $False }
    [PSCustomObject]@{ Option = 'CleanupObsoleteComputers'; Setting = 'obsoleteComputers'; Counter = 'ObsoleteComputersDeleted'; Decline = $False }
    [PSCustomObject]@{ Option = 'CleanupUnneededContentFiles'; Setting = 'unneededContentFiles'; Counter = 'DiskSpaceFreed'; Decline = $False }
  )

  ForEach ($Definition In $Options) {
    $Label = $Script:Message[('Invoke-WsusBuiltInCleanup.{0}' -f $Definition.Option)]
    If ([System.Boolean]$Settings.($Definition.Setting) -eq $False) {
      $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Script:Message['Invoke-WsusBuiltInCleanup.Off']))
      Continue
    }

    If (($Definition.Decline -eq $True) -and ($Tier -eq 'Replica')) {
      $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Script:Message['Invoke-WsusBuiltInCleanup.Replica']))
      Continue
    }

    If (($Definition.Decline -eq $True) -and ($Tier -eq 'Unknown')) {
      $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Script:Message['Invoke-WsusBuiltInCleanup.RoleUnknown']))
      Continue
    }

    $Enabled++
    If ($Definition.Option -eq 'CleanupUnneededContentFiles') {
      $ContentFiles = $True
    }

    If ($Context.DryRun -eq $True) {
      $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Script:Message['Invoke-WsusBuiltInCleanup.WouldRun']))
      Continue
    }

    If (($Stopped -eq $True) -or ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True)) {
      $Stopped = $True
      $NotStarted.Add($Label)
      $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Script:Message['Invoke-WsusBuiltInCleanup.NotStarted']))
      Continue
    }

    $Attempt = 0
    $Done = $False
    $OptionStarted = Get-MaintenanceTime
    While ($Done -eq $False) {
      $Attempt++
      $Counts['Attempts'] = $Counts['Attempts'] + 1
      Try {
        If ($Null -eq $Manager) {
          $Manager = $UpdateServer.GetCleanupManager()
        }

        $Scope = New-WsusAdministrationObject -TypeName:'CleanupScope'
        ForEach ($Each In $Options) {
          $Scope.($Each.Option) = [System.Boolean]($Each.Option -eq $Definition.Option)
        }

        $Outcome = $Manager.PerformCleanup($Scope)
        $Value = [System.Int64](Get-MaintenancePropertyValue -InputObject:$Outcome -Name:$Definition.Counter -Default:0)
        $Counts[$Definition.Counter] = $Counts[$Definition.Counter] + $Value
        $Counts['OptionsRun'] = $Counts['OptionsRun'] + 1
        If ($Definition.Counter -eq 'DiskSpaceFreed') {
          $Text = $Script:Message[('Invoke-WsusBuiltInCleanup.{0}Result' -f $Definition.Option)] -f (ConvertTo-MaintenanceByteText -Bytes:$Value)
        } Else {
          $Text = $Script:Message[('Invoke-WsusBuiltInCleanup.{0}Result' -f $Definition.Option)] -f $Value
        }

        $Text = $Script:Message['Invoke-WsusBuiltInCleanup.Took'] -f $Text, [System.Math]::Max([System.Double]0, ((Get-MaintenanceTime) - $OptionStarted).TotalSeconds).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $Attempt
        $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Text))
        Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, $Text) -Stage:'BuiltInCleanup'
        $Done = $True
      } Catch {
        $Failure = $PSItem.Exception.Message
        $TimedOut = Test-MaintenanceTimeout -Exception:$PSItem.Exception
        If (($TimedOut -eq $True) -and ($Attempt -le $Retries) -and ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $False)) {
          Write-MaintenanceLog -Level:'Warning' -Log:$Context.Log -Message:($Script:Message['Invoke-WsusBuiltInCleanup.Retry'] -f $Label, $Attempt, ($Retries + 1), $Failure) -Stage:'BuiltInCleanup'
        } ElseIf (($TimedOut -eq $False) -and ($Tier -eq 'Replica')) {
          $Rejected = $True
          $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, ($Script:Message['Invoke-WsusBuiltInCleanup.Rejected'] -f $Failure)))
          $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-WsusBuiltInCleanup.RejectedNotice'] -f $Label, $Failure) -Severity:'Warning' -Stage:'BuiltInCleanup'))
          $Done = $True
        } Else {
          $Counts['OptionsFailed'] = $Counts['OptionsFailed'] + 1
          $Items.Add(($Script:Message['Invoke-WsusBuiltInCleanup.Item'] -f $Label, ($Script:Message['Invoke-WsusBuiltInCleanup.Failed'] -f $Attempt, $Failure)))
          $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-WsusBuiltInCleanup.FailedNotice'] -f $Label, $Attempt, $Failure) -Severity:'Error' -Stage:'BuiltInCleanup'))
          Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-WsusBuiltInCleanup.FailedNotice'] -f $Label, $Attempt, $Failure) -Stage:'BuiltInCleanup'
          $Done = $True
        }
      }
    }
  }

  If ($NotStarted.Count -gt 0) {
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-WsusBuiltInCleanup.Budget'] -f ($NotStarted -join ', ')) -Severity:'Warning' -Stage:'BuiltInCleanup'))
  }

  If ($Counts['OptionsFailed'] -gt 0) {
    $Status = 'Error'
  } ElseIf (($Rejected -eq $True) -or ($Stopped -eq $True)) {
    $Status = 'Warning'
  }

  If ($Context.DryRun -eq $True) {
    $Summary = $Script:Message['Invoke-WsusBuiltInCleanup.DrySummary'] -f $Enabled
  } Else {
    $Summary = $Script:Message['Invoke-WsusBuiltInCleanup.Summary'] -f $Counts['OptionsRun'], $Enabled, $Counts['OptionsFailed'], (ConvertTo-MaintenanceByteText -Bytes:$Counts['DiskSpaceFreed'])
  }

  If ($ContentFiles -eq $True) {
    $Summary = '{0} {1}' -f $Summary, $Script:Message['Invoke-WsusBuiltInCleanup.CatalogNote']
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:$Items.ToArray() -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Invoke-WsusBuiltInCleanup] Exiting'
}
