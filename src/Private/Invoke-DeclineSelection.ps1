#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-DeclineSelection.Declined' = 'declined: {0}'
  'Invoke-DeclineSelection.Failed'   = 'failed: {0}: {1}'
  'Invoke-DeclineSelection.Labelled' = '[{0}] {1}'
  'Invoke-DeclineSelection.Pending'  = 'pending: {0}'
}

Function Invoke-DeclineSelection {
  <#
    .SYNOPSIS
        Declines the updates a decline policy selected, one at a time.

    .DESCRIPTION
        Declines each selected update with IUpdate.Decline, checking the time budget before each one
        and logging progress (run.progressBatchSize). A failed decline is recorded with the update and
        the error, and the next update proceeds. Each declined update is marked in the catalog, so that a
        later policy of the run does not count it again. A dry run declines nothing, lists each update as
        pending and marks it in the catalog the same way.

    .PARAMETER Candidate
        The decline records to decline, in order.

    .PARAMETER Catalog
        The decline catalog of the run (Get-DeclineCatalog).

    .PARAMETER Context
        The stage context.

    .PARAMETER Label
        Prefix for each listed update, for example the rule name.

    .EXAMPLE
        Invoke-DeclineSelection -Candidate $Selection.Candidates -Catalog $Catalog -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-declineselection',
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
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Candidate,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Catalog,

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
    [AllowEmptyString()]
    [System.String]
    $Label = ''
  )

  Write-Debug -Message:'[Invoke-DeclineSelection] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:BatchSize = 1
  [System.Int32]$Private:Declined = 0
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Int32]$Private:Pending = 0
  [PSCustomObject]$Private:Record = $Null
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Text = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $BatchSize = [System.Int32]$Context.Configuration.run.progressBatchSize
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Failures = [System.Collections.Generic.List[System.String]]::new()
  $Started = Get-MaintenanceTime

  For ($Position = 1; $Position -le $Candidate.Count; $Position++) {
    $Record = $Candidate[$Position - 1]
    $Text = ConvertTo-DeclineItemText -Record:$Record
    If ([System.String]::IsNullOrEmpty($Label) -eq $False) {
      $Text = $Script:Message['Invoke-DeclineSelection.Labelled'] -f $Label, $Text
    }

    If ($Context.DryRun -eq $True) {
      $Pending++
      $Null = $Catalog.Claimed.Add($Record.Id)
      $Items.Add(($Script:Message['Invoke-DeclineSelection.Pending'] -f $Text))
      Continue
    }

    If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
      $Stopped = $True
      Break
    }

    Try {
      $Record.Update.Decline()
      $Declined++
      $Null = $Catalog.Claimed.Add($Record.Id)
      $Items.Add(($Script:Message['Invoke-DeclineSelection.Declined'] -f $Text))
    } Catch {
      $Failures.Add(($Script:Message['Invoke-DeclineSelection.Failed'] -f $Text, $PSItem.Exception.Message))
      Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Invoke-DeclineSelection.Failed'] -f $Text, $PSItem.Exception.Message) -Stage:$Context.StageName
    }

    Write-MaintenanceProgress -BatchSize:$BatchSize -Item:$Record.Title -Log:$Context.Log -Position:$Position -Stage:$Context.StageName -StartedAt:$Started -Total:$Candidate.Count
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Declined = [System.Int32]$Declined
    Pending  = [System.Int32]$Pending
    Failed   = [System.Int32]$Failures.Count
    Items    = [System.String[]]$Items.ToArray()
    Failures = [System.String[]]$Failures.ToArray()
    Stopped  = [System.Boolean]$Stopped
  }

  $Result
  Write-Debug -Message:'[Invoke-DeclineSelection] Exiting'
}
