#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-SupersededCountHealth.Item'   = 'superseded updates not declined: {0} (threshold {1})'
  'Test-SupersededCountHealth.Notice' = '{0} superseded updates are not declined, more than {1}; Microsoft reports problems on servers and clients above 1500. Check the decline policies.'
}

Function Test-SupersededCountHealth {
  <#
    .SYNOPSIS
        Counts the superseded updates that are not declined.

    .DESCRIPTION
        Counts in SUSDB the superseded updates that are not declined, with the query Microsoft's
        maintenance guide gives, and raises a Warning notice when there are more than
        health.supersededCount.threshold: Microsoft reports problems on both servers and clients above
        1500.

    .PARAMETER Context
        The stage context.

    .PARAMETER Threshold
        Highest count that raises no notice.

    .EXAMPLE
        Test-SupersededCountHealth -Context $Context -Threshold 1500

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-supersededcounthealth',
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
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Int32]
    $Threshold
  )

  Write-Debug -Message:'[Test-SupersededCountHealth] Entering'

  # Initialize Variable(s)
  [System.Int64]$Private:Count = 0
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [PSCustomObject]$Private:Result = $Null

  # The count query of Microsoft's WSUS maintenance guide:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide
  #   Code samples in that article: Copyright (c) Microsoft Corporation, MIT License.
  $Count = [System.Int64](@(Invoke-SusdbCommand -CommandText:'SELECT COUNT_BIG(UpdateID) AS Total FROM dbo.vwMinimalUpdate WHERE IsSuperseded = 1 AND Declined = 0' -Connection:(Get-SusdbConnection -Context:$Context) -Log:$Context.Log -TimeoutSeconds:([System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0))) | Select-Object -First:1).Total
  If ($Count -gt $Threshold) {
    $Notices.Add((New-MaintenanceNotice -Link:'https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide' -Message:($Script:Message['Test-SupersededCountHealth.Notice'] -f $Count, $Threshold) -Severity:'Warning' -Stage:'HealthChecks'))
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]($Script:Message['Test-SupersededCountHealth.Item'] -f $Count, $Threshold)
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-SupersededCountHealth] Exiting'
}
