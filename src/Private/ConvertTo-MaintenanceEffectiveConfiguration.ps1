#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceEffectiveConfiguration {
  <#
    .SYNOPSIS
        Builds the effective configuration from a validated document.

    .DESCRIPTION
        Produces one nested object holding every catalogue key: the document's value
        where it sets one, the catalogue default otherwise. Call it only with a document
        that passed Test-MaintenanceConfiguration.

    .PARAMETER Document
        Parsed, validated configuration document.

    .PARAMETER Rule
        The configuration catalogue; defaults to Get-MaintenanceConfigurationRule.

    .EXAMPLE
        ConvertTo-MaintenanceEffectiveConfiguration -Document $Document

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenanceeffectiveconfiguration',
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
    $Document,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject[]]
    $Rule = $Null
  )

  Write-Debug -Message:'[ConvertTo-MaintenanceEffectiveConfiguration] Entering'

  # Initialize Variable(s)
  [PSCustomObject[]]$Private:Catalogue = @()
  [System.Collections.Specialized.OrderedDictionary]$Private:Container = $Null
  [PSCustomObject]$Private:Lookup = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Root = $Null
  [System.String[]]$Private:Segments = @()
  [System.Object]$Private:Value = $Null
  [PSCustomObject]$Private:Result = $Null

  If ($Null -eq $Rule) {
    $Catalogue = @(Get-MaintenanceConfigurationRule)
  } Else {
    $Catalogue = $Rule
  }

  $Root = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Entry In $Catalogue) {
    $Lookup = Get-MaintenanceDocumentValue -Document:$Document -Path:$Entry.Path

    If ($Lookup.Found -eq $True) {
      $Value = $Lookup.Value
    } Else {
      $Value = $Entry.Default
    }

    $Segments = $Entry.Path.Split('.')
    $Container = $Root
    For ($Depth = 0; $Depth -lt ($Segments.Count - 1); $Depth++) {
      If ($Container.Contains($Segments[$Depth]) -eq $False) {
        $Container[$Segments[$Depth]] = [System.Collections.Specialized.OrderedDictionary]::new()
      }

      $Container = $Container[$Segments[$Depth]]
    }

    $Container[$Segments[$Segments.Count - 1]] = $Value
  }

  [PSCustomObject]$Result = ConvertTo-MaintenanceObjectTree -InputObject:$Root
  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceEffectiveConfiguration] Exiting'
}
