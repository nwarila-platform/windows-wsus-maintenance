#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceConfigurationValue.Array'     = '{0}: must be an array (got {1}).'
  'Test-MaintenanceConfigurationValue.Boolean'   = '{0}: must be true or false (got {1}).'
  'Test-MaintenanceConfigurationValue.Duplicate' = '{0}: contains the duplicate entry {1}.'
  'Test-MaintenanceConfigurationValue.Empty'     = '{0}: must not be empty.'
  'Test-MaintenanceConfigurationValue.Null'      = '{0}: must not be null.'
}

Function Test-MaintenanceConfigurationValue {
  <#
    .SYNOPSIS
        Validates one configuration value against its catalogue rule.

    .DESCRIPTION
        Checks type, range, allowed values, format, emptiness and uniqueness for one
        value and returns every problem found. Values are never corrected. Structured
        types (index definitions, rule groups and decline rules) are validated entry by entry; references between them are cross-field rules
        that Test-MaintenanceConfiguration applies.

    .PARAMETER Path
        Location of the value in the document, used in messages.

    .PARAMETER Rule
        The catalogue rule from Get-MaintenanceConfigurationRule.

    .PARAMETER Value
        The value to validate.

    .EXAMPLE
        Test-MaintenanceConfigurationValue -Rule $Rule -Value 7 -Path 'backup.minimumKept'

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceconfigurationvalue',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Path,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Rule,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Value
  )

  Write-Debug -Message:'[Test-MaintenanceConfigurationValue] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.Int32]$Private:Index = 0
  [System.Object]$Private:Item = $Null
  [System.String]$Private:ItemPath = [System.String]::Empty
  [System.Object[]]$Private:Items = @()
  [System.Collections.Generic.HashSet[System.String]]$Private:Seen = $Null
  [System.String[]]$Private:Result = @()

  $Errors = [System.Collections.Generic.List[System.String]]::new()

  If ($Null -eq $Value) {
    If ($Rule.Nullable -eq $False) {
      $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Null'] -f $Path))
    }
  } Else {
    Switch ($Rule.Type) {
      'Boolean' {
        If (($Value -is [System.Boolean]) -eq $False) {
          $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Boolean'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
        }
      }
      'Integer' {
        ForEach ($ItemError In @(Test-MaintenanceIntegerValue -Maximum:$Rule.Maximum -Minimum:$Rule.Minimum -Path:$Path -Value:$Value)) {
          $Errors.Add($ItemError)
        }
      }
      'String' {
        ForEach ($ItemError In @(Test-MaintenanceStringValue -AllowedValues:$Rule.AllowedValues -Path:$Path -Pattern:$Rule.Pattern -Value:$Value)) {
          $Errors.Add($ItemError)
        }
      }
      'Path' {
        ForEach ($ItemError In @(Test-MaintenancePathValue -Path:$Path -Pattern:$Rule.Pattern -Value:$Value)) {
          $Errors.Add($ItemError)
        }
      }
      'StringArray' {
        If (($Value -is [System.Array]) -eq $False) {
          $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Array'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
        } Else {
          $Items = @($Value)
          $Seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
          If (($Rule.NonEmpty -eq $True) -and ($Items.Count -eq 0)) {
            $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Empty'] -f $Path))
          }

          For ($Index = 0; $Index -lt $Items.Count; $Index++) {
            $Item = $Items[$Index]
            $ItemPath = '{0}[{1}]' -f $Path, $Index
            ForEach ($ItemError In @(Test-MaintenanceStringValue -AllowedValues:$Rule.AllowedValues -Path:$ItemPath -Pattern:$Rule.Pattern -Value:$Item)) {
              $Errors.Add($ItemError)
            }

            If (($Rule.Unique -eq $True) -and ($Item -is [System.String]) -and ($Seen.Add($Item) -eq $False)) {
              $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Duplicate'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Item)))
            }
          }
        }
      }
      'IntegerArray' {
        If (($Value -is [System.Array]) -eq $False) {
          $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Array'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
        } Else {
          $Items = @($Value)
          $Seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
          If (($Rule.NonEmpty -eq $True) -and ($Items.Count -eq 0)) {
            $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Empty'] -f $Path))
          }

          For ($Index = 0; $Index -lt $Items.Count; $Index++) {
            $Item = $Items[$Index]
            $ItemPath = '{0}[{1}]' -f $Path, $Index
            ForEach ($ItemError In @(Test-MaintenanceIntegerValue -Maximum:$Rule.Maximum -Minimum:$Rule.Minimum -Path:$ItemPath -Value:$Item)) {
              $Errors.Add($ItemError)
            }

            If (($Rule.Unique -eq $True) -and ($Seen.Add([System.String]$Item) -eq $False)) {
              $Errors.Add(($Script:Message['Test-MaintenanceConfigurationValue.Duplicate'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Item)))
            }
          }
        }
      }
      Default {
        ForEach ($ItemError In @(Test-MaintenanceEntryArray -Path:$Path -Type:$Rule.Type -Value:$Value)) {
          $Errors.Add($ItemError)
        }
      }
    }
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceConfigurationValue] Exiting'
}
