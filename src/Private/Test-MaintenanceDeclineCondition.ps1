#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceDeclineCondition.BadOperator'  = "{0}.operator: '{1}' is not valid for field '{2}'; use one of {3}."
  'Test-MaintenanceDeclineCondition.BadPattern'   = '{0}.value: {1} pattern {2} is invalid: {3}'
  'Test-MaintenanceDeclineCondition.BadValue'     = '{0}.value: {1} (got {2}).'
  'Test-MaintenanceDeclineCondition.EmptyList'    = "{0}.{1}: must be a non-empty array of conditions."
  'Test-MaintenanceDeclineCondition.NotObject'    = '{0}: a condition must be an object (got {1}).'
  'Test-MaintenanceDeclineCondition.TooDeep'      = '{0}: conditions may nest at most {1} levels.'
  'Test-MaintenanceDeclineCondition.UnknownField' = "{0}.field: '{1}' is not a rule field; use one of {2}."
  'Test-MaintenanceDeclineCondition.UnknownKey'   = "{0}.{1}: is not a condition key."
  'Test-MaintenanceDeclineCondition.WrongShape'   = '{0}: a condition is exactly one of {{all}}, {{any}}, {{not}} or a {{field, operator, value}} test.'
}

Function Test-MaintenanceDeclineCondition {
  <#
    .SYNOPSIS
        Validates one decline-rule condition tree.

    .DESCRIPTION
        A condition is one of: {"all": [conditions]}, {"any": [conditions]},
        {"not": condition}, or a leaf test {"field", "operator", "value"}. Text fields
        (Title, LegacyName, ClassificationTitle) and list fields (ProductTitles,
        ProductFamilyTitles, KnowledgeBaseArticles) accept Contains, Equals, Like
        (wildcard) and Match (regular expression); UpdateSource accepts Equals with
        MicrosoftUpdate or Other; CreationDate and ArrivalDate accept OlderThanDays and
        NewerThanDays with a whole number of days. Every problem is returned, none is
        corrected, and nothing is evaluated against updates here.

    .PARAMETER Depth
        Current nesting depth; the caller starts at zero.

    .PARAMETER Node
        The condition to validate.

    .PARAMETER Path
        Location of the condition in the document, used in messages.

    .EXAMPLE
        Test-MaintenanceDeclineCondition -Node $Condition -Path 'declines.rules[0].condition'

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancedeclinecondition',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 64)]
    [System.Int32]
    $Depth = 0,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Node,

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

  Write-Debug -Message:'[Test-MaintenanceDeclineCondition] Entering'

  # Initialize Variable(s)
  [System.String[]]$Private:DateFields = @('ArrivalDate', 'CreationDate')
  [System.String[]]$Private:DateOperators = @('NewerThanDays', 'OlderThanDays')
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.String]$Private:Field = [System.String]::Empty
  [System.Object]$Private:FieldValue = $Null
  [System.Int32]$Private:Index = 0
  [System.String[]]$Private:Keys = @()
  [System.Int32]$Private:MaximumDepth = 16
  [System.String]$Private:Operator = [System.String]::Empty
  [System.Object]$Private:OperatorValue = $Null
  [System.String[]]$Private:Result = @()
  [System.String[]]$Private:TextFields = @('ClassificationTitle', 'KnowledgeBaseArticles', 'LegacyName', 'ProductFamilyTitles', 'ProductTitles', 'Title')
  [System.String[]]$Private:TextOperators = @('Contains', 'Equals', 'Like', 'Match')
  [System.Object]$Private:TestValue = $Null

  $Errors = [System.Collections.Generic.List[System.String]]::new()

  If ($Depth -gt $MaximumDepth) {
    $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.TooDeep'] -f $Path, $MaximumDepth))
  } ElseIf (($Node -is [System.Management.Automation.PSCustomObject]) -eq $False) {
    $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.NotObject'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Node)))
  } Else {
    $Keys = [System.String[]]@($Node.PSObject.Properties | ForEach-Object -Process:({ $PSItem.Name }))

    If (($Keys.Count -eq 1) -and ($Keys[0] -ceq 'all' -or $Keys[0] -ceq 'any')) {
      $FieldValue = $Node.PSObject.Properties[$Keys[0]].Value

      If ((($FieldValue -is [System.Array]) -eq $False) -or (@($FieldValue).Count -eq 0)) {
        $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.EmptyList'] -f $Path, $Keys[0]))
      } Else {
        For ($Index = 0; $Index -lt @($FieldValue).Count; $Index++) {
          ForEach ($ChildError In @(Test-MaintenanceDeclineCondition -Depth:($Depth + 1) -Node:(@($FieldValue)[$Index]) -Path:('{0}.{1}[{2}]' -f $Path, $Keys[0], $Index))) {
            $Errors.Add($ChildError)
          }
        }
      }
    } ElseIf (($Keys.Count -eq 1) -and ($Keys[0] -ceq 'not')) {
      ForEach ($ChildError In @(Test-MaintenanceDeclineCondition -Depth:($Depth + 1) -Node:($Node.PSObject.Properties['not'].Value) -Path:('{0}.not' -f $Path))) {
        $Errors.Add($ChildError)
      }
    } ElseIf (($Keys -ccontains 'field') -or ($Keys -ccontains 'operator') -or ($Keys -ccontains 'value')) {
      ForEach ($Key In $Keys) {
        If (@('field', 'operator', 'value') -cnotcontains $Key) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.UnknownKey'] -f $Path, $Key))
        }
      }

      $FieldValue = $Null
      $OperatorValue = $Null
      $TestValue = $Null
      If ($Keys -ccontains 'field') {
        $FieldValue = $Node.PSObject.Properties['field'].Value
      }
      If ($Keys -ccontains 'operator') {
        $OperatorValue = $Node.PSObject.Properties['operator'].Value
      }
      If ($Keys -ccontains 'value') {
        $TestValue = $Node.PSObject.Properties['value'].Value
      }

      $Field = [System.String]::Empty
      If (($FieldValue -is [System.String]) -and (($TextFields + $DateFields + @('UpdateSource')) -ccontains $FieldValue)) {
        $Field = $FieldValue
      } Else {
        $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.UnknownField'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$FieldValue), (($TextFields + $DateFields + @('UpdateSource')) -join ', ')))
      }

      $Operator = [System.String]::Empty
      If ($OperatorValue -is [System.String]) {
        $Operator = $OperatorValue
      }

      If ($TextFields -ccontains $Field) {
        If ($TextOperators -cnotcontains $Operator) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadOperator'] -f $Path, $Operator, $Field, ($TextOperators -join ', ')))
        } ElseIf ((($TestValue -is [System.String]) -eq $False) -or ([System.String]::IsNullOrWhiteSpace($TestValue) -eq $True)) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadValue'] -f $Path, 'must be a non-empty string', (ConvertTo-MaintenanceDisplayValue -Value:$TestValue)))
        } ElseIf ($Operator -ceq 'Match') {
          Try {
            $Null = [System.Text.RegularExpressions.Regex]::new($TestValue, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [System.TimeSpan]::FromSeconds(1))
          } Catch {
            $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadPattern'] -f $Path, 'regular expression', (ConvertTo-MaintenanceDisplayValue -Value:$TestValue), $PSItem.Exception.GetBaseException().Message))
          }
        } ElseIf ($Operator -ceq 'Like') {
          Try {
            $Null = [System.Management.Automation.WildcardPattern]::Get($TestValue, [System.Management.Automation.WildcardOptions]::IgnoreCase).IsMatch('')
          } Catch {
            $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadPattern'] -f $Path, 'wildcard', (ConvertTo-MaintenanceDisplayValue -Value:$TestValue), $PSItem.Exception.GetBaseException().Message))
          }
        }
      } ElseIf ($DateFields -ccontains $Field) {
        If ($DateOperators -cnotcontains $Operator) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadOperator'] -f $Path, $Operator, $Field, ($DateOperators -join ', ')))
        } ElseIf ((($TestValue -is [System.Int32]) -or ($TestValue -is [System.Int64])) -eq $False) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadValue'] -f $Path, 'must be a whole number of days from 0 to 36500', (ConvertTo-MaintenanceDisplayValue -Value:$TestValue)))
        } ElseIf (($TestValue -lt 0) -or ($TestValue -gt 36500)) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadValue'] -f $Path, 'must be a whole number of days from 0 to 36500', (ConvertTo-MaintenanceDisplayValue -Value:$TestValue)))
        }
      } ElseIf ($Field -ceq 'UpdateSource') {
        If ($Operator -cne 'Equals') {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadOperator'] -f $Path, $Operator, $Field, 'Equals'))
        } ElseIf (@('MicrosoftUpdate', 'Other') -cnotcontains $TestValue) {
          $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.BadValue'] -f $Path, 'must be MicrosoftUpdate or Other', (ConvertTo-MaintenanceDisplayValue -Value:$TestValue)))
        }
      }
    } Else {
      $Errors.Add(($Script:Message['Test-MaintenanceDeclineCondition.WrongShape'] -f $Path))
    }
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceDeclineCondition] Exiting'
}
