#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-StaleComputerCleanup.Budget'          = 'Time budget reached after {0} of {1} stale computer(s); the rest are handled on the next run.'
  'Invoke-StaleComputerCleanup.Deleted'         = 'deleted: {0}'
  'Invoke-StaleComputerCleanup.DryDelete'       = 'Simulation: would delete {0} computer(s) not synchronized for {1} day(s) (of {2} in total); nothing was changed.'
  'Invoke-StaleComputerCleanup.DryMove'         = 'Simulation: would move {0} computer(s) not synchronized for {1} day(s) (of {2} in total) to {3}; nothing was changed.'
  'Invoke-StaleComputerCleanup.FailedItem'      = 'failed: {0}: {1}'
  'Invoke-StaleComputerCleanup.FailedNotice'    = '{0} stale computer(s) could not be handled. First failure: {1}'
  'Invoke-StaleComputerCleanup.Guard'           = '{0} of {1} computer(s) have not synchronized for {2} day(s), more than staleComputers.guardCount ({3}) or staleComputers.guardPercent ({4}%) allows, so none was changed. Check the list in the report; when the selection is expected, raise the guard or set staleComputers.override.'
  'Invoke-StaleComputerCleanup.GuardSummary'    = 'guard exceeded: {0} of {1} computer(s) selected; nothing was changed'
  'Invoke-StaleComputerCleanup.Held'            = 'not changed (guard): {0}'
  'Invoke-StaleComputerCleanup.Moved'           = 'moved to {0}: {1}'
  'Invoke-StaleComputerCleanup.NoGroup'         = 'Stale computers were not moved: the computer group ''{0}'' does not exist. Create it, or change staleComputers.targetGroup.'
  'Invoke-StaleComputerCleanup.NoGroupSummary'  = 'target group missing; nothing was changed'
  'Invoke-StaleComputerCleanup.Overridden'      = 'The stale-computer guard was exceeded ({0} of {1} computer(s) selected) and staleComputers.override is set, so the selection is processed.'
  'Invoke-StaleComputerCleanup.Rejected'        = 'The change to stale computers was refused, as expected on a replica (rejected by server role): {0}'
  'Invoke-StaleComputerCleanup.RejectedSummary' = 'rejected by server role'
  'Invoke-StaleComputerCleanup.SummaryDelete'   = 'Deleted {0} of {1} computer(s) not synchronized for {2} day(s) (of {3} in total); {4} failed.'
  'Invoke-StaleComputerCleanup.SummaryMove'     = 'Moved {0} of {1} computer(s) not synchronized for {2} day(s) (of {3} in total) to {5}; {4} failed.'
  'Invoke-StaleComputerCleanup.WouldDelete'     = 'simulation, would delete: {0}'
  'Invoke-StaleComputerCleanup.WouldMove'       = 'simulation, would move to {0}: {1}'
}

Function Invoke-StaleComputerCleanup {
  <#
    .SYNOPSIS
        Deletes, or moves into a group, the computers that have stopped synchronizing.

    .DESCRIPTION
        Selects the client computers whose last synchronization is more than staleComputers.thresholdDays
        days old (ComputerTargetScope.ToLastSyncTime, compared in UTC), leaving out computers reported
        through downstream servers unless staleComputers.includeDownstream is set, and either deletes them
        (IComputerTarget.Delete) or adds them to the computer group staleComputers.targetGroup
        (IComputerTargetGroup.AddComputerTarget), as Microsoft's stale-computer sample does; computers
        already in that group are left out. The group must exist; it is never created. When more
        computers are selected than staleComputers.guardCount, or a larger share of all computers than
        staleComputers.guardPercent, nothing is changed and a High notice is raised, unless
        staleComputers.override is set. A failed computer is recorded and the next one proceeds; the
        stage then ends in error. On a replica the first refusal ends the stage with "rejected by server
        role". The time budget is checked before each computer. The items list the computers sorted by
        name with their last synchronization time, operating system and client version; a dry run
        changes nothing and marks the list as a simulation.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-StaleComputerCleanup -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-stalecomputercleanup',
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

  Write-Debug -Message:'[Invoke-StaleComputerCleanup] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:BatchSize = 1
  [System.Object[]]$Private:Computers = @()
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.DateTime]$Private:Cutoff = [System.DateTime]::MinValue
  [System.Int32]$Private:Days = 0
  [System.String]$Private:Description = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.Object]$Private:Group = $Null
  [System.String]$Private:GroupName = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Collections.Generic.List[System.Object]]$Private:Kept = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:Members = $Null
  [System.Boolean]$Private:Move = $False
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Boolean]$Private:Proceed = $True
  [System.Boolean]$Private:Rejected = $False
  [System.Object]$Private:Scope = $Null
  [System.Object]$Private:Settings = $Null
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [System.String]$Private:Tier = [System.String]::Empty
  [System.Object]$Private:UpdateServer = $Null
  [PSCustomObject]$Private:Result = $Null

  $UpdateServer = Get-WsusConnection -Context:$Context
  $Settings = $Context.Configuration.staleComputers
  $Days = [System.Int32]$Settings.thresholdDays
  $Move = [System.String]$Settings.action -eq 'Move'
  $GroupName = [System.String]$Settings.targetGroup
  $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
  $Tier = [System.String](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'Tier' -Default:'')
  $Cutoff = $Context.RunStart.ToUniversalTime().AddDays(-$Days)
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Failures = [System.Collections.Generic.List[System.String]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Total', 'Selected', 'Deleted', 'Moved', 'Failed', 'GuardExceeded')) {
    $Counts[$Name] = [System.Int64]0
  }

  # The selection and the delete-or-move actions follow Microsoft's stale-computer sample:
  #   https://learn.microsoft.com/previous-versions/windows/desktop/ee958382(v=vs.85)
  $Scope = New-WsusAdministrationObject -TypeName:'ComputerTargetScope'
  $Scope.IncludeDownstreamComputerTargets = [System.Boolean]$Settings.includeDownstream
  $Counts['Total'] = [System.Int64]$UpdateServer.GetComputerTargetCount($Scope)

  $Scope = New-WsusAdministrationObject -TypeName:'ComputerTargetScope'
  $Scope.IncludeDownstreamComputerTargets = [System.Boolean]$Settings.includeDownstream
  $Scope.ToLastSyncTime = $Cutoff
  $Computers = @($UpdateServer.GetComputerTargets($Scope))

  If ($Move -eq $True) {
    ForEach ($Candidate In @($UpdateServer.GetComputerTargetGroups())) {
      If ([System.String]::Equals([System.String]$Candidate.Name, $GroupName, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
        $Group = $Candidate
      }
    }

    If ($Null -eq $Group) {
      $Proceed = $False
      $Status = 'Error'
      $Summary = $Script:Message['Invoke-StaleComputerCleanup.NoGroupSummary']
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-StaleComputerCleanup.NoGroup'] -f $GroupName) -Severity:'Error' -Stage:'StaleComputers'))
    } Else {
      $Members = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
      ForEach ($Member In @($Group.GetComputerTargets())) {
        $Null = $Members.Add([System.String]$Member.Id)
      }

      $Kept = [System.Collections.Generic.List[System.Object]]::new()
      ForEach ($Computer In $Computers) {
        If ($Members.Contains([System.String]$Computer.Id) -eq $False) {
          $Kept.Add($Computer)
        }
      }

      $Computers = $Kept.ToArray()
    }
  }

  $Computers = @($Computers | Sort-Object -Property:@{ Expression = { [System.String]$PSItem.FullDomainName } })
  $Counts['Selected'] = [System.Int64]$Computers.Count

  If (($Proceed -eq $True) -and ($Computers.Count -gt 0)) {
    If (($Computers.Count -gt [System.Int32]$Settings.guardCount) -or (($Counts['Total'] -gt 0) -and (($Computers.Count * 100) -gt ([System.Int64]$Settings.guardPercent * $Counts['Total'])))) {
      $Counts['GuardExceeded'] = 1
      If ([System.Boolean]$Settings.override -eq $True) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-StaleComputerCleanup.Overridden'] -f $Computers.Count, $Counts['Total']) -Severity:'Warning' -Stage:'StaleComputers'))
      } Else {
        $Proceed = $False
        $Status = 'Warning'
        $Summary = $Script:Message['Invoke-StaleComputerCleanup.GuardSummary'] -f $Computers.Count, $Counts['Total']
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-StaleComputerCleanup.Guard'] -f $Computers.Count, $Counts['Total'], $Days, $Settings.guardCount, $Settings.guardPercent) -Severity:'High' -Stage:'StaleComputers'))
        ForEach ($Computer In $Computers) {
          $Items.Add(($Script:Message['Invoke-StaleComputerCleanup.Held'] -f (ConvertTo-StaleComputerText -Computer:$Computer)))
        }
      }
    }
  }

  If ($Proceed -eq $True) {
    $Started = Get-MaintenanceTime
    For ($Position = 1; $Position -le $Computers.Count; $Position++) {
      $Computer = $Computers[$Position - 1]
      $Description = ConvertTo-StaleComputerText -Computer:$Computer
      If ($Context.DryRun -eq $True) {
        If ($Move -eq $True) {
          $Items.Add(($Script:Message['Invoke-StaleComputerCleanup.WouldMove'] -f $Group.Name, $Description))
        } Else {
          $Items.Add(($Script:Message['Invoke-StaleComputerCleanup.WouldDelete'] -f $Description))
        }

        Continue
      }

      If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
        $Stopped = $True
        Break
      }

      Try {
        If ($Move -eq $True) {
          $Group.AddComputerTarget($Computer)
          $Counts['Moved'] = $Counts['Moved'] + 1
          $Items.Add(($Script:Message['Invoke-StaleComputerCleanup.Moved'] -f $Group.Name, $Description))
        } Else {
          $Computer.Delete()
          $Counts['Deleted'] = $Counts['Deleted'] + 1
          $Items.Add(($Script:Message['Invoke-StaleComputerCleanup.Deleted'] -f $Description))
        }
      } Catch {
        If ($Tier -eq 'Replica') {
          $Rejected = $True
          $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-StaleComputerCleanup.Rejected'] -f $PSItem.Exception.Message) -Severity:'Warning' -Stage:'StaleComputers'))
          Break
        }

        $Failures.Add(($Script:Message['Invoke-StaleComputerCleanup.FailedItem'] -f $Description, $PSItem.Exception.Message))
        Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-StaleComputerCleanup.FailedItem'] -f $Description, $PSItem.Exception.Message) -Stage:'StaleComputers'
      }

      Write-MaintenanceProgress -BatchSize:$BatchSize -Item:([System.String]$Computer.FullDomainName) -Log:$Context.Log -Position:$Position -Stage:'StaleComputers' -StartedAt:$Started -Total:$Computers.Count
    }

    $Counts['Failed'] = [System.Int64]$Failures.Count
    If ($Failures.Count -gt 0) {
      $Status = 'Error'
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-StaleComputerCleanup.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Error' -Stage:'StaleComputers'))
    } ElseIf (($Rejected -eq $True) -or ($Stopped -eq $True)) {
      $Status = 'Warning'
    }

    If ($Stopped -eq $True) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-StaleComputerCleanup.Budget'] -f ($Counts['Deleted'] + $Counts['Moved'] + $Failures.Count), $Computers.Count) -Severity:'Warning' -Stage:'StaleComputers'))
    }

    If (($Context.DryRun -eq $True) -and ($Move -eq $True)) {
      $Summary = $Script:Message['Invoke-StaleComputerCleanup.DryMove'] -f $Computers.Count, $Days, $Counts['Total'], $Group.Name
    } ElseIf ($Context.DryRun -eq $True) {
      $Summary = $Script:Message['Invoke-StaleComputerCleanup.DryDelete'] -f $Computers.Count, $Days, $Counts['Total']
    } ElseIf ($Rejected -eq $True) {
      $Summary = $Script:Message['Invoke-StaleComputerCleanup.RejectedSummary']
    } ElseIf ($Move -eq $True) {
      $Summary = $Script:Message['Invoke-StaleComputerCleanup.SummaryMove'] -f $Counts['Moved'], $Computers.Count, $Days, $Counts['Total'], $Failures.Count, $Group.Name
    } Else {
      $Summary = $Script:Message['Invoke-StaleComputerCleanup.SummaryDelete'] -f $Counts['Deleted'], $Computers.Count, $Days, $Counts['Total'], $Failures.Count
    }
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Invoke-StaleComputerCleanup] Exiting'
}
