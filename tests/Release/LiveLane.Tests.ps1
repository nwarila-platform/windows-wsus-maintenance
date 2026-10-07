#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# The live lane (milestone M11) only runs on a hosted Windows runner. These tests check what can be
#   checked anywhere: the workflow's shape and conventions, the lane scripts' syntax and the install
#   commands they carry, and the behaviour of the lane's helpers that need no Windows component.

Describe 'live lane workflow shape' {
  BeforeAll {
    $script:ProjectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:WorkflowText = Get-Content -LiteralPath (Join-Path -Path $script:ProjectRoot -ChildPath '.github/workflows/live-lane.yaml') -Raw
    $script:LaneFolder = Join-Path -Path $script:ProjectRoot -ChildPath '.github/scripts/live-lane'
  }

  It 'runs only when started by hand or when a pull request changes the lane itself' {
    $script:WorkflowText | Should -Match '(?m)^  workflow_dispatch:\r?\n    inputs:\r?\n      record-pins:'
    $script:WorkflowText | Should -Match '(?ms)^  pull_request:\r?\n    branches: \[main\]\r?\n    paths:\r?\n      - \.github/workflows/live-lane\.yaml\r?\n      - \.github/scripts/live-lane/\*\*'
    $script:WorkflowText | Should -Not -Match '(?m)^  (push|schedule|merge_group|pull_request_target):'
  }

  It 'asks for read access to the repository contents only' {
    $script:WorkflowText | Should -Match '(?m)^permissions:\r?\n  contents: read'
    $script:WorkflowText | Should -Match '(?m)^    permissions:\r?\n      contents: read\r?\n'
    $script:WorkflowText | Should -Not -Match ':\s*write\b'
    $script:WorkflowText | Should -Not -Match 'secrets\.'
  }

  It 'pins every action to a full commit and keeps the checkout token out of the workspace' {
    $Uses = @([System.Text.RegularExpressions.Regex]::Matches($script:WorkflowText, '(?m)^\s*(?:- )?uses:\s*(\S+)(.*)$') | ForEach-Object -Process { $PSItem })
    $Uses.Count | Should -BeGreaterThan 1
    ForEach ($Use In $Uses) {
      $Use.Groups[1].Value | Should -Match '^[^@\s]+@[0-9a-f]{40}$'
      $Use.Groups[2].Value | Should -Match '#\s*v\d+'
    }
    $script:WorkflowText | Should -Match 'persist-credentials: false'
  }

  It 'runs on the latest Windows runner within a time limit' {
    $script:WorkflowText | Should -Match '(?m)^    runs-on: windows-latest$'
    $script:WorkflowText | Should -Match '(?m)^    timeout-minutes: \d+$'
  }

  It 'downloads SQL Server Express from the Microsoft link and checks both downloads against their pins' {
    $script:WorkflowText | Should -Match 'SQLEXPRESS_BOOTSTRAPPER_URL: https://go\.microsoft\.com/fwlink/\?linkid=2215160'
    $script:WorkflowText | Should -Match '(?m)^      SQLEXPRESS_BOOTSTRAPPER_SHA256: '
    $script:WorkflowText | Should -Match '(?m)^      SQLEXPRESS_MEDIA_SHA256: '
    $script:WorkflowText | Should -Match "RECORD_PINS: \$\{\{ github\.event_name == 'workflow_dispatch' && inputs\.record-pins \}\}"
  }

  It 'builds, installs, runs, terminates, validates and always keeps the evidence, in that order' {
    $Order = @('build\.ps1 -Task Build', 'Install-SqlExpress\.ps1', 'Install-WsusRole\.ps1', 'Install-LaneScript\.ps1', 'Invoke-LaneRuns\.ps1', 'Invoke-LaneInterruption\.ps1', 'Test-LaneSchemas\.ps1', 'Save-LaneEvidence\.ps1', 'actions/upload-artifact@')
    $Positions = @(ForEach ($Pattern In $Order) { [System.Text.RegularExpressions.Regex]::Match($script:WorkflowText, $Pattern).Index })
    ForEach ($Index In 1..($Positions.Count - 1)) {
      $Positions[$Index] | Should -BeGreaterThan $Positions[$Index - 1]
    }
    $script:WorkflowText | Should -Match '(?ms)- name: Collect the evidence\r?\n        if: always\(\)'
    $script:WorkflowText | Should -Match '(?ms)- name: Upload the evidence\r?\n        if: always\(\)'
    $script:WorkflowText | Should -Match '(?ms)- name: Validate the configuration and every summary against the schemas\r?\n        shell: pwsh'
  }

  It 'calls only lane scripts that exist' {
    ForEach ($Name In @([System.Text.RegularExpressions.Regex]::Matches($script:WorkflowText, 'live-lane[\\/]([A-Za-z.-]+\.ps1)') | ForEach-Object -Process { $PSItem.Groups[1].Value } | Select-Object -Unique)) {
      Test-Path -LiteralPath (Join-Path -Path $script:LaneFolder -ChildPath $Name) | Should -BeTrue
    }
  }
}

Describe 'live lane scripts' {
  BeforeDiscovery {
    $script:LaneScripts = @(Get-ChildItem -LiteralPath (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath '.github/scripts/live-lane') -Filter '*.ps1' | ForEach-Object -Process { @{ Name = $PSItem.Name; Path = $PSItem.FullName } })
  }

  BeforeAll {
    $script:LaneFolder = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath '.github/scripts/live-lane'

    Function script:Get-LaneText {
      Param ([System.String]$Name)
      Get-Content -LiteralPath (Join-Path -Path $script:LaneFolder -ChildPath $Name) -Raw
    }
  }

  It '<Name> parses without errors and carries the licence header' -ForEach $script:LaneScripts {
    $Tokens = $Null
    $Errors = $Null
    $Null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors)
    @($Errors) | Should -HaveCount 0
    (Get-Content -LiteralPath $Path -TotalCount 3) -join "`n" | Should -Match '# SPDX-FileCopyrightText: 2026 Nicholas Warila\n# SPDX-License-Identifier: MIT'
  }

  It 'cites Microsoft for every install step' {
    (Get-LaneText -Name 'Install-SqlExpress.ps1') | Should -Match 'learn\.microsoft\.com/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt'
    (Get-LaneText -Name 'Install-SqlExpress.ps1') | Should -Match 'learn\.microsoft\.com/sql/database-engine/configure-windows/sql-server-express-localdb'
    (Get-LaneText -Name 'Install-SqlExpress.ps1') | Should -Match 'learn\.microsoft\.com/archive/blogs/sqlexpress/configuring-sql-express-during-installation'
    (Get-LaneText -Name 'Install-WsusRole.ps1') | Should -Match 'learn\.microsoft\.com/powershell/module/servermanager/install-windowsfeature'
    (Get-LaneText -Name 'Install-WsusRole.ps1') | Should -Match 'learn\.microsoft\.com/troubleshoot/mem/configmgr/update-management/wsus-configure-shared-database'
    (Get-LaneText -Name 'Install-LaneScript.ps1') | Should -Match 'learn\.microsoft\.com/windows-server/administration/windows-commands/icacls'
    (Get-LaneText -Name 'Install-LaneScript.ps1') | Should -Match 'learn\.microsoft\.com/sql/t-sql/statements/alter-authorization-transact-sql'
    (Get-LaneText -Name 'LiveLane.Common.ps1') | Should -Match 'learn\.microsoft\.com/powershell/module/scheduledtasks/'
  }

  It 'checks each download against its pin before running it' {
    $Text = Get-LaneText -Name 'Install-SqlExpress.ps1'
    $Text.IndexOf('Assert-LanePin -Path $Bootstrapper') | Should -BeLessThan $Text.IndexOf('Start-Process -FilePath $Bootstrapper')
    $Text.IndexOf('Assert-LanePin -Path $Package.FullName') | Should -BeLessThan $Text.IndexOf('Start-Process -FilePath $Package.FullName')
  }

  It 'installs the Database Engine quietly without making SYSTEM or Administrators a sysadmin' {
    $Text = Get-LaneText -Name 'Install-SqlExpress.ps1'
    ForEach ($Switch In @("'/Q'", "'/ACTION=Install'", "'/FEATURES=SQLENGINE'", "'/IACCEPTSQLSERVERLICENSETERMS'", "'/SUPPRESSPRIVACYSTATEMENTNOTICE'", "'/UPDATEENABLED=False'")) {
      $Text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape($Switch))
    }
    $Text | Should -Match "/SQLSYSADMINACCOUNTS=""\{0\}""' -f \`$Administrator"
    $Text | Should -Not -Match 'BUILTIN\\Administrators'
  }

  It 'runs the script as SYSTEM with the highest run level, as the deployment does' {
    $Text = Get-LaneText -Name 'LiveLane.Common.ps1'
    $Text | Should -Match "New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\\SYSTEM' -LogonType ServiceAccount -RunLevel Highest"
    $Text | Should -Match "New-ScheduledTaskAction -Execute 'powershell\.exe'"
  }

  It 'protects the installation folder before the script is copied there' {
    $Text = Get-LaneText -Name 'Install-LaneScript.ps1'
    $Text | Should -Match "/inheritance:r /grant:r '\*S-1-5-18:\(OI\)\(CI\)F' '\*S-1-5-32-544:\(OI\)\(CI\)F'"
    $Text.IndexOf('/inheritance:r') | Should -BeLessThan $Text.IndexOf('Copy-Item -LiteralPath $BuiltScript')
  }
}

Describe 'live lane helpers' {
  BeforeAll {
    . (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath '.github/scripts/live-lane/LiveLane.Common.ps1')
    $script:PreviousSummary = $env:GITHUB_STEP_SUMMARY
  }

  AfterAll {
    $env:GITHUB_STEP_SUMMARY = $script:PreviousSummary
  }

  BeforeEach {
    # The notes go to the job summary file; the console copy is not needed here.
    Mock -CommandName Write-Information -MockWith { }
    $env:GITHUB_STEP_SUMMARY = Join-Path -Path $TestDrive -ChildPath ('summary-{0}.md' -f [System.Guid]::NewGuid().ToString('N'))
    $script:Download = Join-Path -Path $TestDrive -ChildPath 'download.exe'
    [System.IO.File]::WriteAllText($script:Download, 'payload')
    $script:Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:Download).Hash.ToLowerInvariant()
  }

  It 'accepts a download that matches its pin, in either case' {
    { Assert-LanePin -Path $script:Download -Expected $script:Hash.ToUpperInvariant() } | Should -Not -Throw
    Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw | Should -Match 'passed: download\.exe matches its pinned SHA-256'
  }

  It 'refuses a download that does not match its pin' {
    { Assert-LanePin -Path $script:Download -Expected ('0' * 64) } | Should -Throw -ExpectedMessage ('SHA-256 mismatch for download.exe: pinned {0}, downloaded {1}.' -f ('0' * 64), $script:Hash)
  }

  It 'refuses a download whose pin is not recorded, and prints the value to record when asked' {
    { Assert-LanePin -Path $script:Download -Expected '' } | Should -Throw -ExpectedMessage 'No SHA-256 pin is recorded for download.exe*record-pins*'
    { Assert-LanePin -Path $script:Download -Expected '' -Record $True } | Should -Not -Throw
    Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw | Should -Match ('SHA-256 of download\.exe to pin: `{0}`' -f $script:Hash)
  }

  It 'fails an assertion with its message and notes a passed one' {
    { Assert-LaneCondition -Condition $False -Message 'the lane works' } | Should -Throw -ExpectedMessage 'Live lane assertion failed: the lane works'
    Assert-LaneCondition -Condition $True -Message 'the lane runs'
    Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw | Should -Match '- FAILED: the lane works'
    Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw | Should -Match '- passed: the lane runs'
  }

  Context 'runs' {
    BeforeEach {
      $script:LaneDataFolder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
      $Folder = Join-Path -Path $script:LaneDataFolder -ChildPath 'Summaries'
      $Null = New-Item -ItemType Directory -Path $Folder -Force

      Function script:New-LaneSummary {
        Param ([System.String]$Name, [System.Int32]$ExitCode, [System.String]$Status = 'Success', [System.DateTime]$Written = (Get-Date))
        $Path = Join-Path -Path $script:LaneDataFolder -ChildPath ('Summaries/WsusMaintenance-{0}.json' -f $Name)
        $Json = '{ "exitCode": ' + $ExitCode + ', "stages": [ { "name": "Backup", "status": "' + $Status + '", "errorMessage": "disk full", "counts": { "Created": 1 } } ], "notices": [ { "severity": "Warning", "message": "pool settings differ" } ] }'
        [System.IO.File]::WriteAllText($Path, $Json)
        [System.IO.File]::SetLastWriteTime($Path, $Written)
        $Path
      }
    }

    It 'reads the newest summary written since a run started, and finds a stage in it' {
      $Start = Get-Date
      $Null = New-LaneSummary -Name 'old' -ExitCode 0 -Written $Start.AddHours(-1)
      $Newest = New-LaneSummary -Name 'new' -ExitCode 2 -Written $Start.AddSeconds(5)

      $Summary = Get-LaneSummary -Since $Start

      $Summary.Path | Should -Be $Newest
      $Summary.exitCode | Should -Be 2
      (Get-LaneStage -Summary $Summary -Name 'Backup').counts.Created | Should -Be 1
      Get-LaneSummary -Since $Start.AddMinutes(1) | Should -BeNullOrEmpty
    }

    It 'passes a run whose exit code is expected, matches its summary and has no stage in error' {
      $Start = Get-Date
      $Null = New-LaneSummary -Name 'ok' -ExitCode 2
      $Run = [PSCustomObject]@{ Arguments = '-DryRun'; StartedAt = $Start; ExitCode = 2; Summary = (Get-LaneSummary -Since $Start.AddSeconds(-5)) }

      { Assert-LaneRun -Run $Run -Label 'Dry run' } | Should -Not -Throw
      Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw | Should -Match 'notice Warning: pool settings differ'
    }

    It 'fails a run with <Case>' -ForEach @(
      @{ Case = 'an unexpected exit code'; ExitCode = 1; Recorded = 1; Status = 'Success'; Expected = @(0, 2); Message = 'Live lane assertion failed: Live run: exit code 1 is one of 0, 2' }
      @{ Case = 'a summary that disagrees with Task Scheduler'; ExitCode = 2; Recorded = 0; Status = 'Success'; Expected = @(0, 2); Message = 'Live lane assertion failed: Live run: the summary records the same exit code as Task Scheduler' }
      @{ Case = 'a stage in error'; ExitCode = 1; Recorded = 1; Status = 'Error'; Expected = @(1); Message = 'Live lane assertion failed: Live run: no stage ended in error: Backup (disk full)' }
    ) {
      $Start = Get-Date
      $Null = New-LaneSummary -Name 'bad' -ExitCode $Recorded -Status $Status
      $Run = [PSCustomObject]@{ Arguments = ''; StartedAt = $Start; ExitCode = $ExitCode; Summary = (Get-LaneSummary -Since $Start.AddSeconds(-5)) }

      { Assert-LaneRun -Run $Run -Label 'Live run' -ExpectedExitCode $Expected } | Should -Throw -ExpectedMessage $Message
    }
  }
}
