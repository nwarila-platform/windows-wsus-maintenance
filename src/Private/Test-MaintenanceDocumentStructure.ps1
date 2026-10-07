#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceDocumentStructure.Container'   = '{0}: must be an object (got {1}).'
  'Test-MaintenanceDocumentStructure.Deprecated'  = "{0}: is deprecated; use '{1}' instead."
  'Test-MaintenanceDocumentStructure.Unknown'     = "{0}: is not a configuration key."
  'Test-MaintenanceDocumentStructure.UnknownCase' = "{0}: is not a configuration key; keys are case-sensitive (did you mean '{1}'?)."
}

Function Test-MaintenanceDocumentStructure {
  <#
    .SYNOPSIS
        Checks that a configuration document uses only known keys.

    .DESCRIPTION
        Walks the document's objects against the catalogue's dotted paths. An object
        that the catalogue treats as a section must be a JSON object; a key the
        catalogue does not know is reported under the unknown-key policy (as an error,
        or as a warning that is then ignored). Keys are matched case-sensitively, with a
        suggestion when only the casing differs. Leaf values, including structured
        leaves such as decline rules, are validated elsewhere. Every string value and
        key is also scanned for embedded expressions and plain-text secrets.

    .PARAMETER Node
        The object to check; the caller passes the whole document.

    .PARAMETER Prefix
        Dotted path of Node within the document; empty for the document itself.

    .PARAMETER Rule
        The configuration catalogue.

    .PARAMETER UnknownKeyPolicy
        Error or Warning.

    .EXAMPLE
        Test-MaintenanceDocumentStructure -Node $Document -Rule $Rules -UnknownKeyPolicy 'Error'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancedocumentstructure',
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
    $Node,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Prefix = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject[]]
    $Rule,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Error', 'Warning')]
    [System.String]
    $UnknownKeyPolicy
  )

  Write-Debug -Message:'[Test-MaintenanceDocumentStructure] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ChildPath = [System.String]::Empty
  [PSCustomObject]$Private:ChildResult = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:Containers = $Null
  [System.Collections.Hashtable]$Private:Replacements = $Null
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.Collections.Generic.HashSet[System.String]]$Private:Leaves = $Null
  [System.Collections.Generic.List[System.String]]$Private:Siblings = $Null
  [System.String]$Private:Suggestion = [System.String]::Empty
  [System.String]$Private:UnknownMessage = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null
  [System.String[]]$Private:Segments = @()
  [System.Collections.Generic.List[System.String]]$Private:Warnings = $Null

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $Warnings = [System.Collections.Generic.List[System.String]]::new()
  $Leaves = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
  $Containers = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)

  $Replacements = @{}
  ForEach ($Entry In $Rule) {
    [void]$Leaves.Add($Entry.Path)
    If ([System.String]::IsNullOrEmpty($Entry.ReplacedBy) -eq $False) {
      $Replacements[$Entry.Path] = $Entry.ReplacedBy
    }

    $Segments = $Entry.Path.Split('.')
    For ($Depth = 1; $Depth -lt $Segments.Count; $Depth++) {
      [void]$Containers.Add(($Segments[0..($Depth - 1)] -join '.'))
    }
  }

  $Siblings = [System.Collections.Generic.List[System.String]]::new()
  ForEach ($Known In @($Leaves) + @($Containers)) {
    If ([System.String]::IsNullOrEmpty($Prefix) -eq $True) {
      If ($Known.Contains('.') -eq $False) {
        $Siblings.Add($Known)
      }
    } ElseIf ($Known.StartsWith(($Prefix + '.'), [System.StringComparison]::Ordinal) -and ($Known.Substring($Prefix.Length + 1).Contains('.') -eq $False)) {
      $Siblings.Add($Known.Substring($Prefix.Length + 1))
    }
  }

  ForEach ($Property In $Node.PSObject.Properties) {
    If ([System.String]::IsNullOrEmpty($Prefix) -eq $True) {
      $ChildPath = $Property.Name
    } Else {
      $ChildPath = '{0}.{1}' -f $Prefix, $Property.Name
    }

    If ($Leaves.Contains($ChildPath) -eq $True) {
      ForEach ($TextError In @(Test-MaintenanceDocumentText -Path:$ChildPath -Value:$Property.Value)) {
        $Errors.Add($TextError)
      }

      If ($Replacements.ContainsKey($ChildPath) -eq $True) {
        $Warnings.Add(($Script:Message['Test-MaintenanceDocumentStructure.Deprecated'] -f $ChildPath, $Replacements[$ChildPath]))
      }
    } ElseIf ($Containers.Contains($ChildPath) -eq $True) {
      If ($Property.Value -is [System.Management.Automation.PSCustomObject]) {
        $ChildResult = Test-MaintenanceDocumentStructure -Node:$Property.Value -Prefix:$ChildPath -Rule:$Rule -UnknownKeyPolicy:$UnknownKeyPolicy
        ForEach ($ChildError In $ChildResult.Errors) {
          $Errors.Add($ChildError)
        }
        ForEach ($ChildWarning In $ChildResult.Warnings) {
          $Warnings.Add($ChildWarning)
        }
      } Else {
        $Errors.Add(($Script:Message['Test-MaintenanceDocumentStructure.Container'] -f $ChildPath, (ConvertTo-MaintenanceDisplayValue -Value:$Property.Value)))
      }
    } Else {
      ForEach ($TextError In @(Test-MaintenanceDocumentText -Path:$Prefix -Value:([PSCustomObject]@{ $Property.Name = $Property.Value }))) {
        $Errors.Add($TextError)
      }

      $Suggestion = [System.String]::Empty
      ForEach ($Sibling In $Siblings) {
        If ($Sibling -ieq $Property.Name) {
          $Suggestion = $Sibling
        }
      }

      If ([System.String]::IsNullOrEmpty($Suggestion) -eq $True) {
        $UnknownMessage = $Script:Message['Test-MaintenanceDocumentStructure.Unknown'] -f $ChildPath
      } Else {
        $UnknownMessage = $Script:Message['Test-MaintenanceDocumentStructure.UnknownCase'] -f $ChildPath, $Suggestion
      }

      If ($UnknownKeyPolicy -eq 'Warning') {
        $Warnings.Add($UnknownMessage)
      } Else {
        $Errors.Add($UnknownMessage)
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Errors   = [System.String[]]$Errors.ToArray()
    Warnings = [System.String[]]$Warnings.ToArray()
  }
  $Result
  Write-Debug -Message:'[Test-MaintenanceDocumentStructure] Exiting'
}
