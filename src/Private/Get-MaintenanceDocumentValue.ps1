#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceDocumentValue {
  <#
    .SYNOPSIS
        Looks up one dotted configuration path in a parsed document.

    .DESCRIPTION
        Walks the parsed JSON document one segment at a time with case-sensitive key
        matching, so 'Backup' is never mistaken for 'backup'. Returns whether the path is
        present and, when it is, its value. A path that runs into a non-object value is
        reported as absent; validation reports the wrong-typed container separately.

    .PARAMETER Document
        Parsed configuration document.

    .PARAMETER Path
        Dotted configuration path, for example backup.minimumKept.

    .EXAMPLE
        Get-MaintenanceDocumentValue -Document $Document -Path 'backup.minimumKept'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancedocumentvalue',
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
    [AllowNull()]
    [System.Object]
    $Document,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Path
  )

  Write-Debug -Message:'[Get-MaintenanceDocumentValue] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Current = $Null
  [System.Boolean]$Private:Found = $True
  [System.Management.Automation.PSPropertyInfo]$Private:Property = $Null
  [PSCustomObject]$Private:Result = $Null

  $Current = $Document
  ForEach ($Segment In $Path.Split('.')) {
    $Property = $Null

    If ($Current -is [System.Management.Automation.PSCustomObject]) {
      ForEach ($Candidate In $Current.PSObject.Properties) {
        If ($Candidate.Name -ceq $Segment) {
          $Property = $Candidate
          Break
        }
      }
    }

    If ($Null -eq $Property) {
      $Found = $False
      $Current = $Null
      Break
    }

    $Current = $Property.Value
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Found = [System.Boolean]$Found
    Value = $Current
  }
  $Result
  Write-Debug -Message:'[Get-MaintenanceDocumentValue] Exiting'
}
