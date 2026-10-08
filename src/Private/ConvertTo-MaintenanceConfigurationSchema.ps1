#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-MaintenanceConfigurationSchema {
  <#
    .SYNOPSIS
        Renders the configuration catalogue as a JSON Schema document.

    .DESCRIPTION
        Produces the published schema (JSON Schema draft-07) from the same catalogue the
        validator uses, so the documentation and the run-time checks cannot drift. Every
        key carries its description, unit, range or allowed values and default. The
        structured types (decline rules and conditions, rule groups, index definitions)
        are described under definitions. Runtime validation additionally applies the
        cross-field rules, which JSON Schema cannot express.

    .PARAMETER Rule
        The configuration catalogue; defaults to Get-MaintenanceConfigurationRule.

    .EXAMPLE
        ConvertTo-MaintenanceConfigurationSchema | Set-Content -Path 'docs/reference/maintenance.schema.json'

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-maintenanceconfigurationschema',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
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

  Write-Debug -Message:'[ConvertTo-MaintenanceConfigurationSchema] Entering'

  # Initialize Variable(s)
  [PSCustomObject[]]$Private:Catalogue = @()
  [System.Collections.Specialized.OrderedDictionary]$Private:Container = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Definitions = $Null
  [System.String]$Private:Description = [System.String]::Empty
  [System.String]$Private:IdentityPattern = '^[A-Za-z_][A-Za-z0-9_]{0,127}$'
  [System.Collections.Specialized.OrderedDictionary]$Private:Leaf = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Root = $Null
  [System.String[]]$Private:Segments = @()
  [System.String[]]$Private:TextFields = @('ClassificationTitle', 'KnowledgeBaseArticles', 'LegacyName', 'ProductFamilyTitles', 'ProductTitles', 'Title')
  [System.String]$Private:Result = [System.String]::Empty

  If ($Null -eq $Rule) {
    $Catalogue = @(Get-MaintenanceConfigurationRule)
  } Else {
    $Catalogue = $Rule
  }

  $Root = [ordered]@{
    '$schema'            = 'http://json-schema.org/draft-07/schema#'
    '$id'                = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/maintenance.schema.json'
    title                = 'WSUS maintenance configuration'
    description          = 'Configuration document read by Invoke-WsusMaintenance.ps1. Generated from the parameter catalogue; do not edit by hand.'
    type                 = 'object'
    additionalProperties = $False
    required             = [System.String[]]@($Catalogue | Where-Object -FilterScript { $PSItem.Required -eq $True } | ForEach-Object -Process:({ $PSItem.Path }))
    properties           = [ordered]@{}
  }

  ForEach ($Entry In $Catalogue) {
    $Description = $Entry.Description
    If ([System.String]::IsNullOrEmpty($Entry.Unit) -eq $False) {
      $Description = '{0} Unit: {1}.' -f $Description, $Entry.Unit
    }

    If ([System.String]::IsNullOrEmpty($Entry.ReplacedBy) -eq $False) {
      $Description = '{0} Deprecated: use {1}.' -f $Description, $Entry.ReplacedBy
    }

    $Leaf = [ordered]@{ description = $Description }
    Switch ($Entry.Type) {
      'Boolean' {
        $Leaf['type'] = 'boolean'
      }
      'Integer' {
        $Leaf['type'] = 'integer'
        $Leaf['minimum'] = $Entry.Minimum
        $Leaf['maximum'] = $Entry.Maximum
      }
      'String' {
        $Leaf['type'] = 'string'
        $Leaf['minLength'] = 1
        If ($Entry.AllowedValues.Count -gt 0) {
          $Leaf['enum'] = [System.String[]]$Entry.AllowedValues
        }
        If ([System.String]::IsNullOrEmpty($Entry.Pattern) -eq $False) {
          $Leaf['pattern'] = $Entry.Pattern
        }
      }
      'Path' {
        $Leaf['type'] = 'string'
        $Leaf['pattern'] = $Entry.Pattern
      }
      'StringArray' {
        $Leaf['type'] = 'array'
        $Leaf['items'] = [ordered]@{ type = 'string'; minLength = 1 }
        If ($Entry.AllowedValues.Count -gt 0) {
          $Leaf['items']['enum'] = [System.String[]]$Entry.AllowedValues
        }
        If ([System.String]::IsNullOrEmpty($Entry.Pattern) -eq $False) {
          $Leaf['items']['pattern'] = $Entry.Pattern
        }
        $Leaf['uniqueItems'] = $Entry.Unique
        If ($Entry.NonEmpty -eq $True) {
          $Leaf['minItems'] = 1
        }
      }
      'IntegerArray' {
        $Leaf['type'] = 'array'
        $Leaf['items'] = [ordered]@{ type = 'integer'; minimum = $Entry.Minimum; maximum = $Entry.Maximum }
        $Leaf['uniqueItems'] = $Entry.Unique
        If ($Entry.NonEmpty -eq $True) {
          $Leaf['minItems'] = 1
        }
      }
      'IndexArray' {
        $Leaf['type'] = 'array'
        $Leaf['items'] = [ordered]@{ '$ref' = '#/definitions/customIndex' }
      }
      'GroupArray' {
        $Leaf['type'] = 'array'
        $Leaf['items'] = [ordered]@{ '$ref' = '#/definitions/declineGroup' }
      }
      'ApprovalGroupArray' {
        $Leaf['type'] = 'array'
        $Leaf['items'] = [ordered]@{ '$ref' = '#/definitions/approvalGroup' }
      }
      Default {
        $Leaf['type'] = 'array'
        $Leaf['items'] = [ordered]@{ '$ref' = '#/definitions/declineRule' }
      }
    }

    If ($Entry.Nullable -eq $True) {
      $Leaf['type'] = [System.String[]]@($Leaf['type'], 'null')
    }

    If ($Entry.HasDefault -eq $True) {
      $Leaf['default'] = $Entry.Default
    }

    $Segments = $Entry.Path.Split('.')
    $Container = $Root
    For ($Depth = 0; $Depth -lt ($Segments.Count - 1); $Depth++) {
      If ($Container['properties'].Contains($Segments[$Depth]) -eq $False) {
        $Container['properties'][$Segments[$Depth]] = [ordered]@{
          type                 = 'object'
          additionalProperties = $False
          properties           = [ordered]@{}
        }
      }

      $Container = $Container['properties'][$Segments[$Depth]]
    }

    $Container['properties'][$Segments[$Segments.Count - 1]] = $Leaf
  }

  $Definitions = [ordered]@{
    customIndex   = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('name', 'table', 'columns')
      properties           = [ordered]@{
        name    = [ordered]@{ type = 'string'; pattern = $IdentityPattern }
        table   = [ordered]@{ type = 'string'; pattern = $IdentityPattern }
        columns = [ordered]@{ type = 'array'; minItems = 1; uniqueItems = $True; items = [ordered]@{ type = 'string'; pattern = $IdentityPattern } }
      }
    }
    declineGroup  = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('name', 'enabled')
      properties           = [ordered]@{
        name    = [ordered]@{ type = 'string'; minLength = 1 }
        enabled = [ordered]@{ type = 'boolean' }
      }
    }
    approvalGroup = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('name', 'delayDays')
      properties           = [ordered]@{
        name         = [ordered]@{ type = 'string'; minLength = 1 }
        delayDays    = [ordered]@{ type = 'integer'; minimum = 0; maximum = 3650 }
        deadlineDays = [ordered]@{ type = 'integer'; minimum = 0; maximum = 3650 }
      }
    }
    declineRule   = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('name', 'enabled', 'condition')
      properties           = [ordered]@{
        name      = [ordered]@{ type = 'string'; minLength = 1 }
        enabled   = [ordered]@{ type = 'boolean' }
        group     = [ordered]@{ type = 'string'; minLength = 1 }
        condition = [ordered]@{ '$ref' = '#/definitions/condition' }
      }
    }
    condition     = [ordered]@{
      oneOf = @(
        [ordered]@{ type = 'object'; additionalProperties = $False; required = [System.String[]]@('all'); properties = [ordered]@{ all = [ordered]@{ type = 'array'; minItems = 1; items = [ordered]@{ '$ref' = '#/definitions/condition' } } } }
        [ordered]@{ type = 'object'; additionalProperties = $False; required = [System.String[]]@('any'); properties = [ordered]@{ any = [ordered]@{ type = 'array'; minItems = 1; items = [ordered]@{ '$ref' = '#/definitions/condition' } } } }
        [ordered]@{ type = 'object'; additionalProperties = $False; required = [System.String[]]@('not'); properties = [ordered]@{ not = [ordered]@{ '$ref' = '#/definitions/condition' } } }
        [ordered]@{ '$ref' = '#/definitions/textTest' }
        [ordered]@{ '$ref' = '#/definitions/dateTest' }
        [ordered]@{ '$ref' = '#/definitions/sourceTest' }
      )
    }
    textTest      = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('field', 'operator', 'value')
      properties           = [ordered]@{
        field    = [ordered]@{ type = 'string'; enum = $TextFields }
        operator = [ordered]@{ type = 'string'; enum = [System.String[]]@('Contains', 'Equals', 'Like', 'Match') }
        value    = [ordered]@{ type = 'string'; minLength = 1 }
      }
    }
    dateTest      = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('field', 'operator', 'value')
      properties           = [ordered]@{
        field    = [ordered]@{ type = 'string'; enum = [System.String[]]@('ArrivalDate', 'CreationDate') }
        operator = [ordered]@{ type = 'string'; enum = [System.String[]]@('NewerThanDays', 'OlderThanDays') }
        value    = [ordered]@{ type = 'integer'; minimum = 0; maximum = 36500 }
      }
    }
    sourceTest    = [ordered]@{
      type                 = 'object'
      additionalProperties = $False
      required             = [System.String[]]@('field', 'operator', 'value')
      properties           = [ordered]@{
        field    = [ordered]@{ type = 'string'; enum = [System.String[]]@('UpdateSource') }
        operator = [ordered]@{ type = 'string'; enum = [System.String[]]@('Equals') }
        value    = [ordered]@{ type = 'string'; enum = [System.String[]]@('MicrosoftUpdate', 'Other') }
      }
    }
  }
  $Root['definitions'] = $Definitions

  [System.String]$Result = ConvertTo-Json -InputObject:$Root -Depth:64
  $Result
  Write-Debug -Message:'[ConvertTo-MaintenanceConfigurationSchema] Exiting'
}
