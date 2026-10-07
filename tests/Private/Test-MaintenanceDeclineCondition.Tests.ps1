#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Test-MaintenanceDeclineCondition' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')

    Function script:Test-Condition {
      Param ([System.String]$Json)
      @(Test-MaintenanceDeclineCondition -Node ($Json | ConvertFrom-Json) -Path 'c')
    }
  }

  It 'accepts a nested all, any and not tree of valid tests' {
    $Json = '{ "all": [ { "any": [ { "field": "Title", "operator": "Contains", "value": "Preview" }, { "field": "Title", "operator": "Like", "value": "*Beta*" } ] }, { "not": { "field": "ArrivalDate", "operator": "NewerThanDays", "value": 14 } }, { "field": "UpdateSource", "operator": "Equals", "value": "MicrosoftUpdate" }, { "field": "KnowledgeBaseArticles", "operator": "Equals", "value": "5005112" } ] }'

    Test-Condition -Json $Json | Should -HaveCount 0
  }

  It 'accepts a regular expression test that compiles' {
    Test-Condition -Json '{ "field": "LegacyName", "operator": "Match", "value": "^KB[0-9]+-ia64$" }' | Should -HaveCount 0
  }

  It 'refuses <Case>' -ForEach @(
    @{ Case = 'a non-object condition'; Json = '[ 1 ]'; Message = '*must be an object*' }
    @{ Case = 'an empty all list'; Json = '{ "all": [] }'; Message = '*non-empty array*' }
    @{ Case = 'an any that is not a list'; Json = '{ "any": { "field": "Title" } }'; Message = '*non-empty array*' }
    @{ Case = 'two combinators in one object'; Json = '{ "all": [], "any": [] }'; Message = '*exactly one of*' }
    @{ Case = 'an unknown field'; Json = '{ "field": "Severity", "operator": "Equals", "value": "Critical" }'; Message = '*is not a rule field*' }
    @{ Case = 'a text operator on a date field'; Json = '{ "field": "CreationDate", "operator": "Contains", "value": "2026" }'; Message = '*not valid for field*' }
    @{ Case = 'a date operator on a text field'; Json = '{ "field": "Title", "operator": "OlderThanDays", "value": 3 }'; Message = '*not valid for field*' }
    @{ Case = 'a non-integer day count'; Json = '{ "field": "CreationDate", "operator": "OlderThanDays", "value": "30" }'; Message = '*whole number of days*' }
    @{ Case = 'a day count out of range'; Json = '{ "field": "CreationDate", "operator": "OlderThanDays", "value": 40000 }'; Message = '*whole number of days*' }
    @{ Case = 'an empty text value'; Json = '{ "field": "Title", "operator": "Contains", "value": " " }'; Message = '*non-empty string*' }
    @{ Case = 'an invalid regular expression'; Json = '{ "field": "Title", "operator": "Match", "value": "[unclosed" }'; Message = '*regular expression pattern*invalid*' }
    @{ Case = 'an invalid wildcard'; Json = '{ "field": "Title", "operator": "Like", "value": "[unclosed" }'; Message = '*wildcard pattern*invalid*' }
    @{ Case = 'an unknown update source'; Json = '{ "field": "UpdateSource", "operator": "Equals", "value": "ThirdParty" }'; Message = '*MicrosoftUpdate or Other*' }
    @{ Case = 'a non-Equals source operator'; Json = '{ "field": "UpdateSource", "operator": "Contains", "value": "Other" }'; Message = '*not valid for field*' }
    @{ Case = 'an extra key in a test'; Json = '{ "field": "Title", "operator": "Contains", "value": "x", "negate": true }'; Message = '*negate: is not a condition key*' }
  ) {
    (Test-Condition -Json $Json) -join "`n" | Should -BeLike $Message
  }

  It 'locates errors inside nested conditions' {
    $Errors = @(Test-Condition -Json '{ "any": [ { "field": "Title", "operator": "Contains", "value": "x" }, { "not": { "field": "Nope", "operator": "Equals", "value": "y" } } ] }')

    $Errors | Should -HaveCount 1
    $Errors[0] | Should -BeLike 'c.any`[1`].not.field:*'
  }

  It 'refuses conditions nested deeper than sixteen levels' {
    $Json = ('{ "not": ' * 18) + '{ "field": "Title", "operator": "Contains", "value": "x" }' + (' }' * 18)

    (Test-Condition -Json $Json) -join "`n" | Should -BeLike '*nest at most 16 levels*'
  }
}
