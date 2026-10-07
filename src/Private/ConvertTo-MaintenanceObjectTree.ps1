#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceObjectTree {
  <#
    .SYNOPSIS
        Converts nested ordered dictionaries into nested objects.

    .DESCRIPTION
        Turns every ordered dictionary in the tree into a PSCustomObject with the same
        keys in the same order, recursively, so configuration sections read as
        $Configuration.backup.minimumKept. Other values are returned unchanged.

    .PARAMETER InputObject
        The ordered dictionary to convert.

    .EXAMPLE
        ConvertTo-MaintenanceObjectTree -InputObject $Root

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenanceobjecttree',
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
    [System.Collections.Specialized.OrderedDictionary]
    $InputObject
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceObjectTree] Entering'

  # Initialize Variable(s)
  [System.Collections.Specialized.OrderedDictionary]$Private:Converted = $Null
  [PSCustomObject]$Private:Result = $Null

  $Converted = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Key In @($InputObject.Keys)) {
    If ($InputObject[$Key] -is [System.Collections.Specialized.OrderedDictionary]) {
      $Converted[$Key] = ConvertTo-MaintenanceObjectTree -InputObject:$InputObject[$Key]
    } Else {
      $Converted[$Key] = $InputObject[$Key]
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]$Converted
  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceObjectTree] Exiting'
}
