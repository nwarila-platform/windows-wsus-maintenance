#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceEntryArray.Array'      = '{0}: must be an array (got {1}).'
  'Test-MaintenanceEntryArray.Duplicate'  = "{0}: the name '{1}' is used more than once."
  'Test-MaintenanceEntryArray.Missing'    = '{0}.{1}: is required.'
  'Test-MaintenanceEntryArray.NotObject'  = '{0}: each entry must be an object (got {1}).'
  'Test-MaintenanceEntryArray.UnknownKey' = '{0}.{1}: is not a key of this entry.'
}

Function Test-MaintenanceEntryArray {
  <#
    .SYNOPSIS
        Validates an array of structured configuration entries.

    .DESCRIPTION
        Validates the three structured array types entry by entry:
        IndexArray entries {name, table, columns} name additional SUSDB indexes;
        GroupArray entries {name, enabled} define decline-rule groups;
        RuleArray entries {name, enabled, condition, group?} define decline rules.
        Every entry must carry exactly its keys, names must be unique (ignoring case),
        and each field is checked against its own type. Returns every problem found.

    .PARAMETER Path
        Location of the array in the document, used in messages.

    .PARAMETER Type
        IndexArray, GroupArray or RuleArray.

    .PARAMETER Value
        The array to validate.

    .EXAMPLE
        Test-MaintenanceEntryArray -Path 'declines.groups' -Type 'GroupArray' -Value $Groups

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceentryarray',
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
    [ValidateSet('IndexArray', 'GroupArray', 'RuleArray')]
    [System.String]
    $Type,

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

  Write-Debug -Message:'[Test-MaintenanceEntryArray] Entering'

  # Initialize Variable(s)
  [System.String[]]$Private:AllowedKeys = @()
  [PSCustomObject]$Private:BooleanRule = $Null
  [PSCustomObject]$Private:ColumnsRule = $Null
  [System.Object]$Private:Entry = $Null
  [System.String]$Private:EntryPath = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.String]$Private:IdentifierPattern = '^[A-Za-z_][A-Za-z0-9_]{0,127}$'
  [System.Int32]$Private:Index = 0
  [System.Object[]]$Private:Items = @()
  [System.String]$Private:NamePattern = '^\S(?:.{0,126}\S)?$'
  [System.Collections.Generic.HashSet[System.String]]$Private:Names = $Null
  [System.String[]]$Private:Present = @()
  [System.String[]]$Private:RequiredKeys = @()
  [System.String[]]$Private:Result = @()

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $BooleanRule = [PSCustomObject]@{ Type = 'Boolean'; Nullable = $False }
  $ColumnsRule = [PSCustomObject]@{
    Type          = 'StringArray'
    Nullable      = $False
    AllowedValues = [System.String[]]@()
    Pattern       = $IdentifierPattern
    Unique        = $True
    NonEmpty      = $True
  }

  Switch ($Type) {
    'IndexArray' {
      $AllowedKeys = @('columns', 'name', 'table')
      $RequiredKeys = @('columns', 'name', 'table')
    }
    'GroupArray' {
      $AllowedKeys = @('enabled', 'name')
      $RequiredKeys = @('enabled', 'name')
    }
    Default {
      $AllowedKeys = @('condition', 'enabled', 'group', 'name')
      $RequiredKeys = @('condition', 'enabled', 'name')
    }
  }

  If (($Value -is [System.Array]) -eq $False) {
    $Errors.Add(($Script:Message['Test-MaintenanceEntryArray.Array'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
  } Else {
    $Items = @($Value)
    $Names = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)

    For ($Index = 0; $Index -lt $Items.Count; $Index++) {
      $Entry = $Items[$Index]
      $EntryPath = '{0}[{1}]' -f $Path, $Index

      If (($Entry -is [System.Management.Automation.PSCustomObject]) -eq $False) {
        $Errors.Add(($Script:Message['Test-MaintenanceEntryArray.NotObject'] -f $EntryPath, (ConvertTo-MaintenanceDisplayValue -Value:$Entry)))
        Continue
      }

      $Present = [System.String[]]@($Entry.PSObject.Properties | ForEach-Object -Process:({ $PSItem.Name }))
      ForEach ($Key In $Present) {
        If ($AllowedKeys -cnotcontains $Key) {
          $Errors.Add(($Script:Message['Test-MaintenanceEntryArray.UnknownKey'] -f $EntryPath, $Key))
        }
      }

      ForEach ($Key In $RequiredKeys) {
        If ($Present -cnotcontains $Key) {
          $Errors.Add(($Script:Message['Test-MaintenanceEntryArray.Missing'] -f $EntryPath, $Key))
        }
      }

      If ($Present -ccontains 'name') {
        If ($Type -eq 'IndexArray') {
          ForEach ($ItemError In @(Test-MaintenanceStringValue -Path:('{0}.name' -f $EntryPath) -Pattern:$IdentifierPattern -Value:$Entry.PSObject.Properties['name'].Value)) {
            $Errors.Add($ItemError)
          }
        } Else {
          ForEach ($ItemError In @(Test-MaintenanceStringValue -Path:('{0}.name' -f $EntryPath) -Pattern:$NamePattern -Value:$Entry.PSObject.Properties['name'].Value)) {
            $Errors.Add($ItemError)
          }
        }

        If (($Entry.PSObject.Properties['name'].Value -is [System.String]) -and ($Names.Add($Entry.PSObject.Properties['name'].Value) -eq $False)) {
          $Errors.Add(($Script:Message['Test-MaintenanceEntryArray.Duplicate'] -f $Path, $Entry.PSObject.Properties['name'].Value))
        }
      }

      If (($Present -ccontains 'enabled') -and (($Entry.PSObject.Properties['enabled'].Value -is [System.Boolean]) -eq $False)) {
        ForEach ($ItemError In @(Test-MaintenanceConfigurationValue -Path:('{0}.enabled' -f $EntryPath) -Rule:$BooleanRule -Value:$Entry.PSObject.Properties['enabled'].Value)) {
          $Errors.Add($ItemError)
        }
      }

      If ($Present -ccontains 'table') {
        ForEach ($ItemError In @(Test-MaintenanceStringValue -Path:('{0}.table' -f $EntryPath) -Pattern:$IdentifierPattern -Value:$Entry.PSObject.Properties['table'].Value)) {
          $Errors.Add($ItemError)
        }
      }

      If ($Present -ccontains 'columns') {
        ForEach ($ItemError In @(Test-MaintenanceConfigurationValue -Path:('{0}.columns' -f $EntryPath) -Rule:$ColumnsRule -Value:$Entry.PSObject.Properties['columns'].Value)) {
          $Errors.Add($ItemError)
        }
      }

      If ($Present -ccontains 'group') {
        ForEach ($ItemError In @(Test-MaintenanceStringValue -Path:('{0}.group' -f $EntryPath) -Pattern:$NamePattern -Value:$Entry.PSObject.Properties['group'].Value)) {
          $Errors.Add($ItemError)
        }
      }

      If ($Present -ccontains 'condition') {
        ForEach ($ItemError In @(Test-MaintenanceDeclineCondition -Node:$Entry.PSObject.Properties['condition'].Value -Path:('{0}.condition' -f $EntryPath))) {
          $Errors.Add($ItemError)
        }
      }
    }
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceEntryArray] Exiting'
}
