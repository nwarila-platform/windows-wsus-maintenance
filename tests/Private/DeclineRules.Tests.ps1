#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Decline rule evaluation' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    $script:Now = [System.DateTime]::new(2026, 11, 2, 6, 0, 0, [System.DateTimeKind]::Utc)
    $script:Record = ConvertTo-DeclineRecord -Update (New-FakeUpdate -Title 'Security Update for Windows Server 2022 (KB5000301)' -Kb @('KB5000301', ' 5000302 ') -Classification 'Security Updates' -Products @('Windows Server 2022', 'Windows Server 2019') -Families @('Windows') -Source 'MicrosoftUpdate' -Created $script:Now.AddDays(-40) -Arrived $script:Now.AddDays(-39) -LegacyName 'KB5000301-Win2022-x64' -Id ([System.Guid]'0d5bd6c1-6a1f-4d43-9d0e-0b0a3c5a9e11'))

    Function script:Test-Condition {
      Param ([System.String]$Json)
      Test-DeclineRuleCondition -Condition ($Json | ConvertFrom-Json) -Now $script:Now -Record $script:Record
    }
  }

  It 'reads the attributes of an update into a record' {
    $script:Record.Id | Should -Be '0d5bd6c1-6a1f-4d43-9d0e-0b0a3c5a9e11'
    $script:Record.KnowledgeBaseArticles | Should -Be @('5000301', '5000302')
    $script:Record.ProductTitles | Should -Be @('Windows Server 2022', 'Windows Server 2019')
    $script:Record.UpdateSource | Should -Be 'MicrosoftUpdate'
    $script:Record.IsExpired | Should -BeFalse
    ConvertTo-DeclineItemText -Record $script:Record | Should -Be ('Security Update for Windows Server 2022 (KB5000301) (KB5000301, KB5000302, created {0})' -f $script:Now.AddDays(-40).ToString('yyyy-MM-dd'))
  }

  It 'is <Expected> for <Json>' -ForEach @(
    @{ Json = '{ "field": "Title", "operator": "Contains", "value": "windows server 2022" }'; Expected = $True }
    @{ Json = '{ "field": "Title", "operator": "Contains", "value": "Windows 11" }'; Expected = $False }
    @{ Json = '{ "field": "Title", "operator": "Equals", "value": "security update for windows server 2022 (kb5000301)" }'; Expected = $True }
    @{ Json = '{ "field": "Title", "operator": "Like", "value": "Security Update*2022*" }'; Expected = $True }
    @{ Json = '{ "field": "Title", "operator": "Match", "value": "^security update .*\\(KB500030[0-9]\\)$" }'; Expected = $True }
    @{ Json = '{ "field": "LegacyName", "operator": "Like", "value": "*-x64" }'; Expected = $True }
    @{ Json = '{ "field": "ClassificationTitle", "operator": "Equals", "value": "Drivers" }'; Expected = $False }
    @{ Json = '{ "field": "ProductTitles", "operator": "Equals", "value": "Windows Server 2019" }'; Expected = $True }
    @{ Json = '{ "field": "ProductFamilyTitles", "operator": "Equals", "value": "Office" }'; Expected = $False }
    @{ Json = '{ "field": "KnowledgeBaseArticles", "operator": "Equals", "value": "KB5000302" }'; Expected = $True }
    @{ Json = '{ "field": "KnowledgeBaseArticles", "operator": "Contains", "value": "kb50003" }'; Expected = $True }
    @{ Json = '{ "field": "KnowledgeBaseArticles", "operator": "Match", "value": "^50003\\d{2}$" }'; Expected = $True }
    @{ Json = '{ "field": "CreationDate", "operator": "OlderThanDays", "value": 30 }'; Expected = $True }
    @{ Json = '{ "field": "CreationDate", "operator": "OlderThanDays", "value": 40 }'; Expected = $False }
    @{ Json = '{ "field": "ArrivalDate", "operator": "NewerThanDays", "value": 40 }'; Expected = $True }
    @{ Json = '{ "field": "ArrivalDate", "operator": "NewerThanDays", "value": 39 }'; Expected = $False }
    @{ Json = '{ "field": "UpdateSource", "operator": "Equals", "value": "MicrosoftUpdate" }'; Expected = $True }
    @{ Json = '{ "field": "UpdateSource", "operator": "Equals", "value": "Other" }'; Expected = $False }
    @{ Json = '{ "all": [ { "field": "Title", "operator": "Contains", "value": "2022" }, { "field": "UpdateSource", "operator": "Equals", "value": "Other" } ] }'; Expected = $False }
    @{ Json = '{ "any": [ { "field": "Title", "operator": "Contains", "value": "Windows 11" }, { "field": "ClassificationTitle", "operator": "Equals", "value": "Security Updates" } ] }'; Expected = $True }
    @{ Json = '{ "not": { "field": "Title", "operator": "Contains", "value": "2022" } }'; Expected = $False }
    @{ Json = '{ "all": [ { "not": { "any": [ { "field": "Title", "operator": "Contains", "value": "Preview" } ] } }, { "field": "CreationDate", "operator": "OlderThanDays", "value": 0 } ] }'; Expected = $True }
  ) {
    Test-Condition -Json $Json | Should -Be $Expected
  }

  It 'matches <Case> on the identity lists' -ForEach @(
    @{ Case = 'a KB number with its prefix'; Identity = @('KB5000302'); Expected = $True }
    @{ Case = 'a bare KB number'; Identity = @('5000301'); Expected = $True }
    @{ Case = 'the update identifier in another case'; Identity = @('0D5BD6C1-6A1F-4D43-9D0E-0B0A3C5A9E11'); Expected = $True }
    @{ Case = 'nothing for other entries'; Identity = @('KB1234567', '11111111-2222-3333-4444-555555555555'); Expected = $False }
    @{ Case = 'nothing for an empty list'; Identity = @(); Expected = $False }
  ) {
    Test-UpdateIdentity -Identity $Identity -Record $script:Record | Should -Be $Expected
  }

  It 'describes an update without a Knowledge Base article' {
    $Record = ConvertTo-DeclineRecord -Update (New-FakeUpdate -Title 'Vendor driver' -Created ([System.DateTime]::new(2026, 3, 4)) -Expired $True)

    ConvertTo-DeclineItemText -Record $Record | Should -Be 'Vendor driver (no Knowledge Base article, created 2026-03-04)'
    $Record.IsExpired | Should -BeTrue
  }
}
