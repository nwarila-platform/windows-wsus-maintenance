#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Write-MaintenanceProgress.Entry' = 'Progress {0} of {1}: {2} ({3} s elapsed).'
}

Function Write-MaintenanceProgress {
  <#
    .SYNOPSIS
        Logs the progress of a stage that works item by item.

    .DESCRIPTION
        Writes one log entry per batch of items, and always for the last item, giving the position and
        total, the item identifier and the time elapsed since the stage started; the entry's own
        timestamp gives the time of day. Operators can then tell slow progress from a hang. The batch
        size is run.progressBatchSize.

    .PARAMETER BatchSize
        Items per progress entry.

    .PARAMETER Item
        Identifier of the item just processed.

    .PARAMETER Log
        The run log, or null.

    .PARAMETER Position
        Position of the item, starting at 1.

    .PARAMETER Stage
        Stage name.

    .PARAMETER StartedAt
        When the stage started.

    .PARAMETER Total
        Number of items the stage will process.

    .EXAMPLE
        Write-MaintenanceProgress -Log $Log -Stage 'ObsoleteUpdates' -Position 50 -Total 1200 -Item '12345' -StartedAt $Start -BatchSize 50

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#write-maintenanceprogress',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(1, 2147483647)]
    [System.Int32]
    $BatchSize,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Item,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Log,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(1, 2147483647)]
    [System.Int32]
    $Position,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Stage,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $StartedAt,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(1, 2147483647)]
    [System.Int32]
    $Total
  )

  Write-Debug -Message:'[Write-MaintenanceProgress] Entering'

  # Initialize Variable(s)
  [System.Double]$Private:Elapsed = 0

  If ((($Position % $BatchSize) -eq 0) -or ($Position -eq $Total)) {
    $Elapsed = [System.Math]::Max([System.Double]0, ((Get-MaintenanceTime) - $StartedAt).TotalSeconds)
    Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Write-MaintenanceProgress.Entry'] -f $Position, $Total, $Item, $Elapsed.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)) -Stage:$Stage
  }

  Write-Debug -Message:'[Write-MaintenanceProgress] Exiting'
}
