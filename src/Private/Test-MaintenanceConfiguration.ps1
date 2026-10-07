#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceConfiguration.Required'    = '{0}: is required.'
  'Test-MaintenanceConfiguration.Unsupported' = 'schemaVersion: version {0} is not supported; this release reads version {1}.'
}

Function Test-MaintenanceConfiguration {
  <#
    .SYNOPSIS
        Validates a parsed configuration document completely.

    .DESCRIPTION
        Runs every check before anything is changed and reports all problems together:
        unknown keys (under the document's unknown-key policy), embedded expressions and
        plain-text secrets, each value's type, range, allowed values and format, required
        keys, and the cross-field rules. Nothing is corrected. Unknown keys reported as
        warnings do not make the document invalid.

    .PARAMETER Document
        Parsed configuration document.

    .PARAMETER Rule
        The configuration catalogue; defaults to Get-MaintenanceConfigurationRule.

    .EXAMPLE
        Test-MaintenanceConfiguration -Document (Read-MaintenanceConfiguration -Path $Path)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceconfiguration',
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

  Write-Debug -Message:'[Test-MaintenanceConfiguration] Entering'

  # Initialize Variable(s)
  [PSCustomObject[]]$Private:Catalogue = @()
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.Collections.Generic.List[System.String]]$Private:InvalidPaths = $Null
  [PSCustomObject]$Private:Lookup = $Null
  [System.String]$Private:Policy = 'Error'
  [PSCustomObject]$Private:PolicyLookup = $Null
  [PSCustomObject]$Private:Structure = $Null
  [System.String[]]$Private:ValueErrors = @()
  [System.Collections.Generic.List[System.String]]$Private:Warnings = $Null
  [PSCustomObject]$Private:Result = $Null

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $Warnings = [System.Collections.Generic.List[System.String]]::new()
  $InvalidPaths = [System.Collections.Generic.List[System.String]]::new()

  If ($Null -eq $Rule) {
    $Catalogue = @(Get-MaintenanceConfigurationRule)
  } Else {
    $Catalogue = $Rule
  }

  # The unknown-key policy is read before the walk that applies it. Anything but the exact
  #   value 'Warning' keeps the strict default; a malformed policy is reported below.
  $PolicyLookup = Get-MaintenanceDocumentValue -Document:$Document -Path:'configuration.unknownKeyPolicy'
  If (($PolicyLookup.Found -eq $True) -and ($PolicyLookup.Value -ceq 'Warning')) {
    $Policy = 'Warning'
  }

  $Structure = Test-MaintenanceDocumentStructure -Node:$Document -Rule:$Catalogue -UnknownKeyPolicy:$Policy
  ForEach ($StructureError In $Structure.Errors) {
    $Errors.Add($StructureError)
  }
  ForEach ($StructureWarning In $Structure.Warnings) {
    $Warnings.Add($StructureWarning)
  }

  ForEach ($Entry In $Catalogue) {
    $Lookup = Get-MaintenanceDocumentValue -Document:$Document -Path:$Entry.Path

    If ($Lookup.Found -eq $False) {
      If ($Entry.Required -eq $True) {
        $Errors.Add(($Script:Message['Test-MaintenanceConfiguration.Required'] -f $Entry.Path))
        $InvalidPaths.Add($Entry.Path)
      }

      Continue
    }

    $ValueErrors = @(Test-MaintenanceConfigurationValue -Path:$Entry.Path -Rule:$Entry -Value:$Lookup.Value)

    # A whole-number schema version outside the supported range is a version mismatch, which
    #   deserves its own message rather than a generic range complaint.
    If (($Entry.Path -ceq 'schemaVersion') -and ($ValueErrors.Count -gt 0) -and (($Lookup.Value -is [System.Int32]) -or ($Lookup.Value -is [System.Int64]))) {
      $ValueErrors = @(($Script:Message['Test-MaintenanceConfiguration.Unsupported'] -f $Lookup.Value, $Entry.Maximum))
    }
    If ($ValueErrors.Count -gt 0) {
      ForEach ($ValueError In $ValueErrors) {
        $Errors.Add($ValueError)
      }

      $InvalidPaths.Add($Entry.Path)
    }
  }

  ForEach ($CrossError In @(Test-MaintenanceConfigurationCrossField -Document:$Document -InvalidPath:$InvalidPaths.ToArray() -Rule:$Catalogue)) {
    $Errors.Add($CrossError)
  }

  # It's always desirable to explicitly set the Result object with its desired class as close
  #   to the soft return to ensure the output is predictable and easily traceable.
  [PSCustomObject]$Result = [PSCustomObject]@{
    IsValid  = [System.Boolean]($Errors.Count -eq 0)
    Errors   = [System.String[]]$Errors.ToArray()
    Warnings = [System.String[]]$Warnings.ToArray()
  }
  $Result.PSTypeNames.Insert(0, 'WsusMaintenance.ConfigurationValidation')

  $Result
  Write-Debug -Message:'[Test-MaintenanceConfiguration] Exiting'
}
