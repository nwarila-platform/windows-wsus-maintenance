#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Report rendering' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Start = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
    $script:Run = [PSCustomObject]@{ RunId = 'RUN'; Stages = @(); DryRun = $False; StartedAt = $script:Start; CompletedAt = $script:Start.AddSeconds(12.5); DurationSeconds = 12.5 }
    $script:Validation = [PSCustomObject]@{ ConfigurationPath = 'C:\m.json'; Overrides = @() }

    Function script:New-Stage {
      Param ([System.String]$Name, [System.Int32]$Order, [System.String]$Status, $Extra = @{})
      $Outcome = [ordered]@{ Name = $Name; Order = $Order; Status = $Status; Reason = 'enabled'; StartedAt = $script:Start; DurationSeconds = 2.4; Counts = $Null; Message = ''; Items = @(); ErrorMessage = ''; ErrorTime = $Null }
      ForEach ($Key In $Extra.Keys) {
        $Outcome[$Key] = $Extra[$Key]
      }
      [PSCustomObject]$Outcome
    }

    $script:Stages = @(
      New-Stage -Name 'Backup' -Order 1 -Status 'Error' -Extra @{ ErrorMessage = 'disk <full> & "busy"'; ErrorTime = $script:Start; Reason = 'stage error' }
      New-Stage -Name 'Reindex' -Order 13 -Status 'Success' -Extra @{ Counts = [ordered]@{ Rebuilt = 3; Ratio = 0.5 }; Items = @('idx<1>', 'idx2', 'idx3'); Message = 'Rebuilt 3' }
      New-Stage -Name 'HealthChecks' -Order 16 -Status 'Skipped' -Extra @{ Reason = 'not available in this release' }
    )
    $script:Notices = @(
      New-MaintenanceNotice -Severity 'Warning' -Message 'Budget nearly used.'
      New-MaintenanceNotice -Severity 'Error' -Message 'Backup failed <now>.' -Stage 'Backup' -Link 'https://learn.microsoft.com/a?b=1&c=2' -Command "Get-Item`nSet-Item"
      New-MaintenanceNotice -Severity 'Information' -Message 'FYI.' -Link 'not-a-url'
      New-MaintenanceNotice -Severity 'High' -Message 'Certificate expires in 14 days.'
    )
    $script:Report = New-MaintenanceReport -ExitCode 1 -LogPath 'C:\Logs\run.log' -MaxItems 2 -Notice $script:Notices -Run $script:Run -Stage $script:Stages -Status 'Error' -Validation $script:Validation
    $script:Failed = New-MaintenanceReport -ExitCode 3 -Failure ([PSCustomObject]@{ Kind = 'PreconditionFailed'; Point = 'elevation check'; Message = 'Not elevated.'; Guidance = 'Run elevated.' }) -MaxItems 2 -Run $script:Run -Status 'Error' -Validation $script:Validation
  }

  Context 'plain text' {
    BeforeAll {
      $script:Text = ConvertTo-MaintenanceReportText -Report $script:Report
      $script:Lines = $script:Text -split "`r`n"
    }

    It 'ends every line with CR LF and starts with the title' {
      $script:Text | Should -Not -Match "[^`r]`n"
      $script:Lines[0] | Should -Be 'WSUS maintenance report'
      $script:Lines | Should -Contain 'Server role          : not yet discovered'
    }

    It 'orders notices by severity and marks the highest prominently' {
      $Start = [System.Array]::IndexOf($script:Lines, 'NOTICES (4; HIGHEST: ERROR)')
      $Start | Should -BeGreaterThan 0
      $script:Lines[$Start + 2] | Should -Be '>>> [ERROR] Backup failed <now>. (Backup)'
      $script:Lines[$Start + 3] | Should -Be '      See: https://learn.microsoft.com/a?b=1&c=2'
      $script:Lines[$Start + 4] | Should -Be '      Command:'
      $script:Lines[$Start + 5] | Should -Be '          Get-Item'
      $script:Lines[$Start + 6] | Should -Be '          Set-Item'
      $script:Lines[$Start + 7] | Should -Be '    [High] Certificate expires in 14 days.'
      $script:Lines[$Start + 8] | Should -Be '    [Warning] Budget nearly used.'
      $script:Lines[$Start + 9] | Should -Be '    [Information] FYI.'
      $script:Lines[$Start + 10] | Should -Be '      See: not-a-url'
    }

    It 'lists each stage exactly once with its status and duration' {
      @($script:Lines | Where-Object -FilterScript { $PSItem -match '^\s*\d+\. Backup: ' }) | Should -Be @(' 1. Backup: Error, 2.4 s')
      @($script:Lines | Where-Object -FilterScript { $PSItem -match '^\s*\d+\. Reindex: ' }) | Should -Be @('13. Reindex: Success, 2.4 s')
      @($script:Lines | Where-Object -FilterScript { $PSItem -match '^\s*\d+\. HealthChecks: ' }) | Should -HaveCount 1
    }

    It 'gives counts, message, the first items and the error of a stage' {
      $script:Lines | Should -Contain '    Counts: Rebuilt=3, Ratio=0.5'
      $script:Lines | Should -Contain '    Message: Rebuilt 3'
      $script:Lines | Should -Contain '    Items (3):'
      $script:Lines | Should -Contain '      - idx<1>'
      $script:Lines | Should -Contain '      ... and 1 more in the run log'
      $script:Lines | Should -Contain '    Error: disk <full> & "busy" (at 2026-11-01 02:00:00)'
    }

    It 'ends with the totals, the duration and the run status' {
      $script:Lines | Should -Contain 'Stage totals: 1 succeeded, 0 with warnings, 1 failed, 1 skipped, 0 not run'
      $script:Lines | Should -Contain 'Notice totals: 1 error, 1 high, 1 warning, 1 information'
      $script:Lines | Should -Contain 'Total duration: 12.5 s'
      $script:Lines[-2] | Should -Be 'Run status: Error (exit code 1)'
      $script:Lines[-1] | Should -Be ''
    }

    It 'states a failure, the point reached and what to do, and that no stage ran' {
      $Lines = (ConvertTo-MaintenanceReportText -Report $script:Failed) -split "`r`n"

      $Lines | Should -Contain 'FAILURE'
      $Lines | Should -Contain 'What happened : Not elevated.'
      $Lines | Should -Contain 'Point reached : elevation check'
      $Lines | Should -Contain 'What to do    : Run elevated.'
      $Lines | Should -Contain 'NOTICES (0)'
      $Lines | Should -Contain 'None.'
      $Lines | Should -Contain 'No stage ran.'
    }
  }

  Context 'HTML' {
    BeforeAll {
      $script:Html = ConvertTo-MaintenanceReportHtml -Report $script:Report
    }

    It 'is a self-contained page with no external resources' {
      $script:Html | Should -Match '^<!DOCTYPE html>'
      $script:Html | Should -Match '<meta charset="utf-8">'
      $script:Html | Should -Match '<title>WSUS maintenance report - .+ - RUN</title>'
      $script:Html | Should -Not -Match '<(script|link|img)'
    }

    It 'encodes every text' {
      $script:Html | Should -Match 'Backup failed &lt;now&gt;\.'
      $script:Html | Should -Match 'disk &lt;full&gt; &amp; &quot;busy&quot;'
      $script:Html | Should -Match '<li>idx&lt;1&gt;</li>'
      $script:Html | Should -Not -Match '<now>'
    }

    It 'orders notices by severity, colours them and marks the highest' {
      $Order = @([System.Text.RegularExpressions.Regex]::Matches($script:Html, 'class="notice sev-([a-z]+)') | ForEach-Object -Process { $PSItem.Groups[1].Value })
      $Order | Should -Be @('error', 'high', 'warning', 'information')
      $script:Html | Should -Match 'class="notice sev-error highest"'
      $script:Html | Should -Not -Match 'class="notice sev-high highest"'
      $script:Html | Should -Match '\.sev-error\{'
    }

    It 'renders an http link as a hyperlink, anything else as text, and commands as preformatted text' {
      $script:Html | Should -Match '<a href="https://learn.microsoft.com/a\?b=1&amp;c=2">https://learn.microsoft.com/a\?b=1&amp;c=2</a>'
      $script:Html | Should -Match '<br>not-a-url</li>'
      $script:Html | Should -Match "<pre>Get-Item`nSet-Item</pre>"
    }

    It 'gives each stage exactly one row with its status and duration' {
      @([System.Text.RegularExpressions.Regex]::Matches($script:Html, '<tr class="status-[a-z]+"><td>\d+</td><td>Backup</td><td>Error</td><td>2\.4 s</td>')) | Should -HaveCount 1
      @([System.Text.RegularExpressions.Regex]::Matches($script:Html, '<tr class="status-')) | Should -HaveCount 3
      $script:Html | Should -Match '\.\.\. and 1 more in the run log'
      $script:Html | Should -Match 'Counts: Rebuilt=3, Ratio=0\.5'
    }

    It 'ends with the same totals and status as the text rendering' {
      $script:Html | Should -Match 'Stage totals: 1 succeeded, 0 with warnings, 1 failed, 1 skipped, 0 not run'
      $script:Html | Should -Match 'Notice totals: 1 error, 1 high, 1 warning, 1 information'
      $script:Html | Should -Match '<p class="run-status status-error">Run status: Error \(exit code 1\)</p>'
    }

    It 'states a failure and that no stage ran or no notice was raised' {
      $Html = ConvertTo-MaintenanceReportHtml -Report $script:Failed

      $Html | Should -Match '<section class="failure">'
      $Html | Should -Match '<tr><th>Point reached</th><td>elevation check</td></tr>'
      $Html | Should -Match '<p>No stage ran\.</p>'
      $Html | Should -Match '<p>None\.</p>'
    }
  }
}
