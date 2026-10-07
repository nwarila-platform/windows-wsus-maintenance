#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-ProcessorHealth.Notice'   = 'This virtual machine has {0} logical processor(s); at least {1} are expected for WSUS.'
  'Test-ProcessorHealth.Physical' = 'processors: {0} on a physical computer, not checked'
  'Test-ProcessorHealth.Virtual'  = 'processors: {0} on a virtual machine (minimum {1})'
}

Function Test-ProcessorHealth {
  <#
    .SYNOPSIS
        Checks the logical-processor count of a virtual machine.

    .DESCRIPTION
        On a virtual machine (Test-VirtualMachine), raises a Warning notice when the computer has fewer
        logical processors than health.processorCount.minimum. A physical computer is not checked.

    .PARAMETER Minimum
        Lowest acceptable logical-processor count.

    .EXAMPLE
        Test-ProcessorHealth -Minimum 4

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-processorhealth',
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
    [System.Int32]
    $Minimum
  )

  Write-Debug -Message:'[Test-ProcessorHealth] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Item = [System.String]::Empty
  [PSCustomObject]$Private:Machine = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [PSCustomObject]$Private:Result = $Null

  $Machine = Get-MaintenanceMachineInfo
  If ((Test-VirtualMachine -Manufacturer:$Machine.Manufacturer -Model:$Machine.Model) -eq $False) {
    $Item = $Script:Message['Test-ProcessorHealth.Physical'] -f $Machine.LogicalProcessors
  } Else {
    $Item = $Script:Message['Test-ProcessorHealth.Virtual'] -f $Machine.LogicalProcessors, $Minimum
    If ($Machine.LogicalProcessors -lt $Minimum) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-ProcessorHealth.Notice'] -f $Machine.LogicalProcessors, $Minimum) -Severity:'Warning' -Stage:'HealthChecks'))
    }
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]$Item
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-ProcessorHealth] Exiting'
}
