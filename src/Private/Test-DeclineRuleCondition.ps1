#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-DeclineRuleCondition {
  <#
    .SYNOPSIS
        Evaluates a decline-rule condition against one update.

    .DESCRIPTION
        Evaluates a validated condition tree: {all} is true when every condition is, {any} when at
        least one is, and {not} negates its condition. A text test compares Title, LegacyName or
        ClassificationTitle, or any of the ProductTitles, ProductFamilyTitles or KnowledgeBaseArticles,
        with Contains, Equals, Like (wildcard) or Match (regular expression), ignoring case; Knowledge Base
        articles are the numbers WSUS stores, and a KB prefix in an Equals or Contains value is ignored. A
        date test is true when CreationDate or ArrivalDate is more (OlderThanDays) or less (NewerThanDays)
        than the given number of days before the run start. UpdateSource Equals compares the update
        source (MicrosoftUpdate or Other).

    .PARAMETER Condition
        The condition (validated).

    .PARAMETER Now
        Run start in UTC, the reference for date tests.

    .PARAMETER Record
        The decline record.

    .EXAMPLE
        Test-DeclineRuleCondition -Condition $Rule.condition -Now $Now -Record $Record

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-declinerulecondition',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
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
    $Condition,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $Now,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Record
  )

  Write-Debug -Message:'[Test-DeclineRuleCondition] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Field = [System.String]::Empty
  [System.Boolean]$Private:Hit = $False
  [System.DateTime]$Private:Limit = [System.DateTime]::MinValue
  [System.String[]]$Private:Names = @()
  [System.String]$Private:Operator = [System.String]::Empty
  [System.String]$Private:Test = [System.String]::Empty
  [System.String]$Private:Text = [System.String]::Empty
  [System.Boolean]$Private:Result = $False

  $Names = [System.String[]]@($Condition.PSObject.Properties | ForEach-Object -Process:({ $PSItem.Name }))
  If ($Names -ccontains 'all') {
    $Result = $True
    ForEach ($Child In @($Condition.all)) {
      If ((Test-DeclineRuleCondition -Condition:$Child -Now:$Now -Record:$Record) -eq $False) {
        $Result = $False
        Break
      }
    }
  } ElseIf ($Names -ccontains 'any') {
    ForEach ($Child In @($Condition.any)) {
      If ((Test-DeclineRuleCondition -Condition:$Child -Now:$Now -Record:$Record) -eq $True) {
        $Result = $True
        Break
      }
    }
  } ElseIf ($Names -ccontains 'not') {
    $Result = (Test-DeclineRuleCondition -Condition:$Condition.not -Now:$Now -Record:$Record) -eq $False
  } Else {
    $Field = [System.String]$Condition.field
    $Operator = [System.String]$Condition.operator
    If (@('CreationDate', 'ArrivalDate') -ccontains $Field) {
      $Limit = $Now.AddDays(0 - [System.Int32]$Condition.value)
      If ($Operator -ceq 'OlderThanDays') {
        $Result = [System.DateTime]$Record.$Field -lt $Limit
      } Else {
        $Result = [System.DateTime]$Record.$Field -gt $Limit
      }
    } ElseIf ($Field -ceq 'UpdateSource') {
      $Result = [System.String]::Equals([System.String]$Record.UpdateSource, [System.String]$Condition.value, [System.StringComparison]::OrdinalIgnoreCase)
    } Else {
      $Test = [System.String]$Condition.value
      If (($Field -ceq 'KnowledgeBaseArticles') -and (@('Equals', 'Contains') -ccontains $Operator)) {
        $Test = $Test -replace '(?i)^KB', ''
      }

      ForEach ($Value In @($Record.$Field)) {
        $Text = [System.String]$Value
        If ($Operator -ceq 'Contains') {
          $Hit = $Text.IndexOf($Test, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        } ElseIf ($Operator -ceq 'Equals') {
          $Hit = [System.String]::Equals($Text, $Test, [System.StringComparison]::OrdinalIgnoreCase)
        } ElseIf ($Operator -ceq 'Like') {
          $Hit = [System.Management.Automation.WildcardPattern]::Get($Test, [System.Management.Automation.WildcardOptions]::IgnoreCase).IsMatch($Text)
        } Else {
          $Hit = [System.Text.RegularExpressions.Regex]::IsMatch($Text, $Test, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [System.TimeSpan]::FromSeconds(1))
        }

        If ($Hit -eq $True) {
          $Result = $True
          Break
        }
      }
    }
  }

  [System.Boolean]$Result = $Result

  $Result
  Write-Debug -Message:'[Test-DeclineRuleCondition] Exiting'
}
