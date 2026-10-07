#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Run output' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    $script:Start = [System.DateTime]::new(2026, 11, 1, 2, 0, 0)
    $script:Validation = [PSCustomObject]@{ ConfigurationPath = 'C:\m.json'; Overrides = @() }

    Function script:New-Setting {
      Param ([System.String]$Root, [System.String[]]$Formats = @('Text', 'Html'))
      $Setting = Get-MaintenanceOutputSetting
      $Setting.ReportFolder = Join-Path -Path $Root -ChildPath 'Reports'
      $Setting.DefaultReportFolder = Join-Path -Path $Root -ChildPath 'DefaultReports'
      $Setting.LogFolder = Join-Path -Path $Root -ChildPath 'Logs'
      $Setting.SummaryFolder = Join-Path -Path $Root -ChildPath 'Summaries'
      $Setting.DefaultSummaryFolder = Join-Path -Path $Root -ChildPath 'DefaultSummaries'
      $Setting.ReportFormats = $Formats
      $Setting
    }

    Function script:New-Record {
      [PSCustomObject]@{ RunId = 'RUN'; Stages = @(); DryRun = $False; StartedAt = $script:Start; CompletedAt = $script:Start.AddSeconds(2); DurationSeconds = 2.0; Deadline = $Null; Artifacts = $Null }
    }
  }

  BeforeEach {
    $script:Root = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $script:Events = [System.Collections.Generic.List[PSCustomObject]]::new()
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Start }
    Mock -CommandName Test-MaintenanceEventSource -MockWith { $True }
    Mock -CommandName Write-MaintenanceEventEntry -MockWith { $script:Events.Add([PSCustomObject]@{ EventId = $EventId; EntryType = $EntryType; Message = $Message }) }
  }

  Context 'Open-MaintenanceRunOutput' {
    It 'opens the log, the event channel and the report and summary folders' {
      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Root $script:Root)

      $Output.RunId | Should -Be 'RUN'
      $Output.Log.Path | Should -Be (Join-Path -Path (Join-Path -Path $script:Root -ChildPath 'Logs') -ChildPath 'WsusMaintenance-RUN.log')
      $Output.Log.Error | Should -BeNullOrEmpty
      $Output.Events.Log | Should -Be $Output.Log
      $Output.ReportFolder | Should -Be (Join-Path -Path $script:Root -ChildPath 'Reports')
      $Output.SummaryFolder | Should -Be (Join-Path -Path $script:Root -ChildPath 'Summaries')
      $Output.Notices | Should -HaveCount 0
    }

    It 'returns a warning for each folder that falls back and the log error' {
      $Blocked = Join-Path -Path $TestDrive -ChildPath 'blocked-file'
      Set-Content -LiteralPath $Blocked -Value 'x'
      $Setting = New-Setting -Root $script:Root
      $Setting.ReportFolder = Join-Path -Path $Blocked -ChildPath 'r'
      $Setting.SummaryFolder = Join-Path -Path $Blocked -ChildPath 's'
      $Setting.LogFolder = Join-Path -Path $Blocked -ChildPath 'l'

      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting $Setting

      $Output.Log.Error | Should -BeLike "The log folder '*' cannot be written: *"
      $Output.ReportFolder | Should -Be (Join-Path -Path $script:Root -ChildPath 'DefaultReports')
      $Output.Notices | Should -HaveCount 2
      $Output.Notices.Severity | Should -Be @('Warning', 'Warning')
    }
  }

  Context 'Publish-MaintenanceRunOutput' {
    It 'saves the reports and the summary, logs the notices and writes the completion event' {
      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Root $script:Root)
      $Stage = @([PSCustomObject]@{ Name = 'Backup'; Order = 1; Status = 'Error'; Reason = 'stage error'; StartedAt = $script:Start; DurationSeconds = 1.0; Counts = $Null; Message = ''; Items = @(); ErrorMessage = 'disk full'; ErrorTime = $script:Start })
      $Notice = @(New-MaintenanceNotice -Severity 'High' -Message 'Look at this.' -Stage 'Backup')

      $Published = Publish-MaintenanceRunOutput -Discovery ([PSCustomObject]@{ Role = 'Top-tier server' }) -ExitCode 1 -Notice $Notice -Output $Output -Run (New-Record) -Stage $Stage -Status 'Error' -Validation $script:Validation

      $Published.ReportPaths | Should -HaveCount 2
      Test-Path -LiteralPath $Published.SummaryPath | Should -BeTrue
      $Published.Report.Status | Should -Be 'Error'
      ($Published.Report.Header | Where-Object -FilterScript { $PSItem.Label -eq 'Server role' }).Value | Should -Be 'Top-tier server'
      $script:Events.EventId | Should -Be @(1100, 1003)
      $script:Events[0].Message | Should -Be 'Run RUN: stage Backup failed: disk full'
      $script:Events[1].Message | Should -BeLike 'Run RUN completed with status Error (exit code 1) in 2.0 s. Report: *WsusMaintenance-RUN.txt, *WsusMaintenance-RUN.html.'
      $Log = Get-Content -LiteralPath $Output.Log.Path -Raw
      $Log | Should -Match 'Warning     \[RUN\] Backup: Notice \(High\): Look at this\.'
      $Log | Should -Match 'Run finished with status Error \(exit code 1\) in 2\.0 s\. Report: .+\. Summary: .+WsusMaintenance-RUN\.json\.'
    }

    It 'writes the completion event that matches the run status' -ForEach @(
      @{ Status = 'Success'; Code = 0; Id = 1001 }
      @{ Status = 'Warning'; Code = 2; Id = 1002 }
    ) {
      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Root $script:Root)

      $Null = Publish-MaintenanceRunOutput -ExitCode $Code -Output $Output -Run (New-Record) -Status $Status -Validation $script:Validation

      $script:Events.EventId | Should -Be @($Id)
    }

    It 'writes the event of a failure instead of a completion event' -ForEach @(
      @{ Kind = 'PreconditionFailed'; Code = 3; Id = 1200 }
      @{ Kind = 'ConfigurationInvalid'; Code = 4; Id = 1300 }
    ) {
      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Root $script:Root)
      $Failure = [PSCustomObject]@{ Kind = $Kind; Point = 'elevation check'; Message = 'Not elevated.'; Guidance = 'Elevate.' }

      $Null = Publish-MaintenanceRunOutput -ExitCode $Code -Failure $Failure -Output $Output -Run (New-Record) -Status 'Error' -Validation $script:Validation

      $script:Events.EventId | Should -Be @($Id)
      $script:Events[0].Message | Should -BeLike ('Run RUN stopped at elevation check with exit code {0}: Not elevated. Elevate. Report: *.' -f $Code)
    }

    It 'logs files that cannot be written and carries on' {
      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Root $script:Root)
      Remove-Item -LiteralPath $Output.ReportFolder -Recurse -Force
      Remove-Item -LiteralPath $Output.SummaryFolder -Recurse -Force

      $Published = Publish-MaintenanceRunOutput -ExitCode 0 -Output $Output -Run (New-Record) -Status 'Success' -Validation $script:Validation

      $Published.ReportPaths | Should -HaveCount 0
      $Published.SummaryPath | Should -BeNullOrEmpty
      $Log = Get-Content -LiteralPath $Output.Log.Path -Raw
      $Log | Should -Match 'Error       \[RUN\] The report file .+ could not be written'
      $Log | Should -Match 'Warning     \[RUN\] The summary file .+ could not be written'
      $Log | Should -Match 'Report: not saved\. Summary: not saved\.'
      $script:Events[0].Message | Should -BeLike '*Report: not saved.'
    }
  }

  Context 'Stop-MaintenanceRun' {
    It 'publishes a failure report and throws the error that decides the exit code' {
      $Output = Open-MaintenanceRunOutput -RunId 'RUN' -Setting (New-Setting -Root $script:Root -Formats @('Text'))
      $Caught = $Null

      Try {
        Stop-MaintenanceRun `
          -Category 'PermissionDenied' `
          -Discovery ([PSCustomObject]@{ Identity = 'CORP\svc-wsus' }) `
          -ErrorId ([MaintenanceExitCode]::PreconditionFailed) `
          -Guidance 'Elevate.' `
          -Message 'Not elevated.' `
          -Output $Output `
          -Point 'elevation check' `
          -Run (New-Record) `
          -TargetObject 'target' `
          -Validation $script:Validation
      } Catch {
        $Caught = $PSItem
      }

      $Caught.FullyQualifiedErrorId | Should -Be 'PreconditionFailed,New-ErrorRecord'
      $Caught.CategoryInfo.Category | Should -Be 'PermissionDenied'
      $Caught.TargetObject | Should -Be 'target'
      $Report = Get-Content -LiteralPath (Join-Path -Path $Output.ReportFolder -ChildPath 'WsusMaintenance-RUN.txt') -Raw
      $Report | Should -Match 'What happened : Not elevated\.'
      $Report | Should -Match 'Point reached : elevation check'
      $Report | Should -Match 'Run status: Error \(exit code 3\)'
      $Report | Should -Match 'Run identity\s+: CORP\\svc-wsus'
      (Get-Content -LiteralPath $Output.Log.Path -Raw) | Should -Match 'The run stopped at the elevation check: Not elevated\.'
      $script:Events.EventId | Should -Be @(1200)
    }
  }
}
