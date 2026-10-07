#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

BeforeDiscovery {
  $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

Describe 'Housekeeping' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

    $script:Setup = [PSCustomObject]@{ TargetDir = 'C:\Program Files\Update Services\'; UsingSSL = 1 }
    $script:RunStart = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)

    Function script:New-Folder {
      $Folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
      $Null = New-Item -ItemType Directory -Path $Folder
      $Folder
    }

    Function script:New-File {
      Param ([System.String]$Folder, [System.String]$Name, [System.Int32]$AgeDays = 0)
      $Path = Join-Path -Path $Folder -ChildPath $Name
      [System.IO.File]::WriteAllText($Path, 'x' * 100)
      [System.IO.File]::SetLastWriteTimeUtc($Path, $script:RunStart.ToUniversalTime().AddDays(-$AgeDays).AddHours(-1))
      $Path
    }

    Function script:Get-Names {
      Param ([System.String]$Folder)
      $Names = [System.String[]]@([System.IO.Directory]::GetFiles($Folder) | ForEach-Object -Process { [System.IO.Path]::GetFileName($PSItem) })
      [System.Array]::Sort($Names, [System.StringComparer]::Ordinal)
      $Names
    }

    Function script:New-HouseContext {
      Param ([System.String]$Extra = '', [System.Boolean]$DryRun = $False, [System.String]$Stage = 'IisLogRetention')
      $Context = New-FakeStageContext -Extra $Extra -DryRun $DryRun -Log $script:Log
      $Context.StageName = $Stage
      $Context
    }
  }

  BeforeEach {
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:RunStart }
    Mock -CommandName Get-WsusSetupValue -MockWith { $script:Setup }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId '20261102-010000-aaaaaaaa' -Verbosity 'Information'
  }

  Context 'Find-WsusWebSite' {
    It 'finds the site <Case>' -ForEach @(
      @{ Case = 'by the WSUS installation path, whatever its name'; Iis = @{ SiteName = 'Renamed Updates' }; Setup = $True; SiteName = ''; Method = 'by the WSUS installation path'; Name = 'Renamed Updates' }
      @{ Case = 'by its remote-administration application when the installation path is not recorded'; Iis = @{ SiteName = 'Default Updates' }; Setup = $False; SiteName = ''; Method = 'by the site that hosts /ApiRemoting30'; Name = 'Default Updates' }
      @{ Case = 'by the configured name'; Iis = @{ SiteName = 'Updates' }; Setup = $True; SiteName = 'updates'; Method = 'by iisLogs.siteName'; Name = 'Updates' }
    ) {
      $Site = Find-WsusWebSite -Iis (New-FakeIisConfiguration @Iis) -Setup $(If ($Setup) { $script:Setup } Else { $Null }) -SiteName $SiteName

      $Site.Error | Should -Be ''
      $Site.Warning | Should -Be ''
      $Site.Name | Should -Be $Name
      $Site.Id | Should -Be '1234567'
      $Site.Method | Should -Be $Method
      $Site.AppPool | Should -Be 'WsusPool'
      $Site.HttpsPorts | Should -Be @(8531)
    }

    It 'falls back to the default name with a warning' {
      $Site = Find-WsusWebSite -Iis (New-FakeIisConfiguration -PhysicalPath 'D:\Elsewhere' -RemoteAdministration $False) -Setup $script:Setup

      $Site.Name | Should -Be 'WSUS Administration'
      $Site.Method | Should -Be 'by the default name WSUS Administration'
      $Site.Warning | Should -BeLike 'The WSUS website was found by its default name only*'
    }

    It 'reports a site it cannot find, and an ambiguous one' {
      $Missing = Find-WsusWebSite -Iis (New-FakeIisConfiguration -SiteName 'Other' -PhysicalPath 'D:\Elsewhere' -RemoteAdministration $False) -Setup $script:Setup
      $Twice = Find-WsusWebSite -Iis (New-FakeIisConfiguration -ExtraSites '<site name="Second" id="9"><application path="/"><virtualDirectory path="/" physicalPath="C:\Program Files\Update Services\WebServices\Other" /></application></site>') -Setup $script:Setup

      $Missing.Error | Should -Be 'the WSUS website was not found (by the default name WSUS Administration)'
      $Twice.Error | Should -Be 'the WSUS website is ambiguous (by the WSUS installation path): WSUS Administration, Second'
    }

    It 'takes the log folder from <Case>' -ForEach @(
      @{ Case = 'the site'; Iis = @{ LogDirectory = 'L:\IisLogs' }; Expected = 'L:\IisLogs' }
      @{ Case = 'the site defaults'; Iis = @{ DefaultLogDirectory = 'M:\Logs' }; Expected = 'M:\Logs' }
      @{ Case = 'the IIS default'; Iis = @{}; Expected = [System.Environment]::ExpandEnvironmentVariables('%SystemDrive%\inetpub\logs\LogFiles') }
    ) {
      (Find-WsusWebSite -Iis (New-FakeIisConfiguration @Iis) -Setup $script:Setup).LogFolder | Should -Be ([System.IO.Path]::Combine($Expected, 'W3SVC1234567'))
    }
  }

  Context 'Remove-IisLogFile' {
    It 'deletes only the old .log files directly in the WSUS log folder' {
      $script:IisRoot = New-Folder
      $Folder = Join-Path -Path $script:IisRoot -ChildPath 'W3SVC1234567'
      $Null = New-Item -ItemType Directory -Path (Join-Path -Path $Folder -ChildPath 'archive')
      $Null = New-File -Folder $Folder -Name 'u_ex260101.log' -AgeDays 300
      $Null = New-File -Folder $Folder -Name 'u_ex260601.log' -AgeDays 91
      $Null = New-File -Folder $Folder -Name 'u_ex261101.log' -AgeDays 1
      $Null = New-File -Folder $Folder -Name 'notes.txt' -AgeDays 300
      $Null = New-File -Folder $Folder -Name 'u_ex250101.logx' -AgeDays 300
      $Null = New-File -Folder (Join-Path -Path $Folder -ChildPath 'archive') -Name 'u_ex240101.log' -AgeDays 600
      Mock -CommandName Get-IisConfiguration -MockWith { New-FakeIisConfiguration -LogDirectory $script:IisRoot }

      $Result = Remove-IisLogFile -Context (New-HouseContext)

      $Result.Status | Should -Be 'Success'
      Get-Names -Folder $Folder | Should -Be @('notes.txt', 'u_ex250101.logx', 'u_ex261101.log')
      Test-Path -LiteralPath (Join-Path -Path $Folder -ChildPath 'archive/u_ex240101.log') | Should -BeTrue
      $Result.Counts['Deleted'] | Should -Be 2
      $Result.Counts['FreedBytes'] | Should -Be 200
      $Result.Message | Should -Be ('Deleted 2 IIS log file(s) older than 90 day(s) from {0}, 200 bytes reclaimed; 1 kept, 0 failed.' -f $Folder)
      (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'WSUS website WSUS Administration \(identifier 1234567\) found by the WSUS installation path'
    }

    It 'uses the configured folder, keeps everything at zero days, and deletes nothing in a dry run' {
      $Folder = New-Folder
      $Null = New-File -Folder $Folder -Name 'old.log' -AgeDays 300
      $Json = $Folder.Replace('\', '\\')

      $Dry = Remove-IisLogFile -Context (New-HouseContext -Extra (', "iisLogs": { "folder": "' + $Json + '" }') -DryRun $True)
      $Zero = Remove-IisLogFile -Context (New-HouseContext -Extra (', "iisLogs": { "folder": "' + $Json + '", "maxAgeDays": 0 }'))

      Get-Names -Folder $Folder | Should -Be @('old.log')
      $Dry.Items | Should -Be @('pending: old.log')
      $Dry.Message | Should -Be ('pending: 1 IIS log file(s) older than 90 day(s) would be deleted from {0}.' -f $Folder)
      $Zero.Message | Should -Be ('IIS log files in {0} are kept: iisLogs.maxAgeDays is 0.' -f $Folder)
    }

    It 'deletes nothing and ends in error when <Case>' -ForEach @(
      @{ Case = 'the IIS configuration cannot be read'; Iis = $Null; Message = 'nothing deleted: the IIS configuration could not be read' }
      @{ Case = 'the site is ambiguous'; Iis = @{ ExtraSites = '<site name="Second" id="9"><application path="/"><virtualDirectory path="/" physicalPath="C:\Program Files\Update Services\Other" /></application></site>' }; Message = 'nothing deleted: the WSUS website is ambiguous*' }
      @{ Case = 'the log folder does not exist'; Iis = @{ LogDirectory = 'Q:\Missing' }; Message = 'nothing deleted: the IIS log folder * does not exist' }
    ) {
      $script:CaseIis = $Iis
      Mock -CommandName Get-IisConfiguration -MockWith { If ($Null -eq $script:CaseIis) { Throw 'Could not find file applicationHost.config.' } Else { $Splat = $script:CaseIis; New-FakeIisConfiguration @Splat } }

      $Result = Remove-IisLogFile -Context (New-HouseContext)

      $Result.Status | Should -Be 'Error'
      $Result.Message | Should -BeLike $Message
      $Result.Notices[0].Severity | Should -Be 'Error'
    }

    It 'does nothing and suggests turning the stage off when IIS HTTP logging is not installed' {
      Mock -CommandName Get-IisConfiguration -MockWith { New-FakeIisConfiguration -HttpLogging $False }

      $Result = Remove-IisLogFile -Context (New-HouseContext)

      $Result.Status | Should -Be 'Success'
      $Result.Message | Should -Be 'skipped: the IIS HTTP logging feature is not installed'
      $Result.Notices[0].Severity | Should -Be 'Information'
    }

    It 'warns when it finds the site only by its default name' {
      $script:IisRoot = New-Folder
      $Null = New-Item -ItemType Directory -Path (Join-Path -Path $script:IisRoot -ChildPath 'W3SVC1234567')
      Mock -CommandName Get-IisConfiguration -MockWith { New-FakeIisConfiguration -LogDirectory $script:IisRoot -PhysicalPath 'D:\Elsewhere' -RemoteAdministration $False }

      $Result = Remove-IisLogFile -Context (New-HouseContext)

      $Result.Status | Should -Be 'Warning'
      $Result.Notices[0].Message | Should -BeLike 'The WSUS website was found by its default name only*'
    }

    It 'stops at the time budget' {
      $Folder = New-Folder
      $Null = New-File -Folder $Folder -Name 'a.log' -AgeDays 300
      $Null = New-File -Folder $Folder -Name 'b.log' -AgeDays 300
      Mock -CommandName Test-MaintenanceBudget -MockWith { $True }

      $Result = Remove-IisLogFile -Context (New-HouseContext -Extra (', "iisLogs": { "folder": "' + $Folder.Replace('\', '\\') + '" }'))

      $Result.Status | Should -Be 'Warning'
      Get-Names -Folder $Folder | Should -HaveCount 2
      $Result.Notices[0].Message | Should -Be 'Time budget reached after deleting 0 IIS log file(s); the rest are deleted on the next run.'
    }

    It 'reports a log file it cannot delete as a warning' -Skip:(-not $script:OnWindows) {
      $Folder = New-Folder
      $Path = New-File -Folder $Folder -Name 'locked.log' -AgeDays 300
      $Stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')

      Try {
        $Result = Remove-IisLogFile -Context (New-HouseContext -Extra (', "iisLogs": { "folder": "' + $Folder.Replace('\', '\\') + '" }'))
      } Finally {
        $Stream.Dispose()
      }

      $Result.Status | Should -Be 'Warning'
      $Result.Counts['Failed'] | Should -Be 1
    }
  }

  Context 'Remove-MaintenanceArtifact' {
    BeforeAll {
      Function script:New-Artifacts {
        Param ([System.String]$Folder, [System.String]$Extension, [System.Int32[]]$DaysAgo)
        ForEach ($Days In $DaysAgo) {
          $Id = '{0}-{1:x8}' -f $script:RunStart.AddDays(-$Days).ToString('yyyyMMdd-HHmmss'), $Days
          ForEach ($Each In $Extension.Split(',')) {
            $Null = New-File -Folder $Folder -Name ('WsusMaintenance-{0}.{1}' -f $Id, $Each)
          }
        }
      }

      Function script:New-ArtifactContext {
        Param ([System.String]$Logs, [System.String]$Reports, [System.String]$Summaries, [System.String]$Retention = '', [System.Boolean]$DryRun = $False)
        $Extra = ', "log": {{ "folder": "{0}" }}, "report": {{ "folder": "{1}" }}, "summary": {{ "folder": "{2}" }}' -f $Logs.Replace('\', '\\'), $Reports.Replace('\', '\\'), $Summaries.Replace('\', '\\')
        If ($Retention -ne '') {
          $Extra = $Extra + ', "retention": { ' + $Retention + ' }'
        }
        $Context = New-HouseContext -Extra $Extra -DryRun $DryRun -Stage 'ArtifactRetention'
        $Context.Log = [PSCustomObject]@{ Path = Join-Path -Path $Logs -ChildPath 'WsusMaintenance-20261102-010000-aaaaaaaa.log'; Folder = $Logs; Verbosity = 'Information'; Lines = 0 }
        $Context
      }
    }

    BeforeEach {
      Mock -CommandName Write-MaintenanceLog -MockWith { }
      $script:Defaults = New-Folder
      Mock -CommandName Resolve-MaintenancePath -MockWith { If ($Path -like '%ProgramData%*') { $script:Defaults } Else { $Path } }
    }

    It 'deletes the runs beyond the age and count limits, a report''s two files together, and nothing else' {
      $Logs = New-Folder
      $Reports = New-Folder
      $Summaries = New-Folder
      New-Artifacts -Folder $Logs -Extension 'log' -DaysAgo @(1, 2, 3, 100)
      New-Artifacts -Folder $Reports -Extension 'txt,html' -DaysAgo @(1, 2, 3)
      New-Artifacts -Folder $Summaries -Extension 'json' -DaysAgo @(1, 95)
      $Null = New-File -Folder $Logs -Name 'WsusMaintenance-20261102-010000-aaaaaaaa.log'
      $Null = New-File -Folder $Logs -Name 'other.log'
      $Null = New-File -Folder $Reports -Name 'WsusMaintenance-notes.txt'
      $Null = New-Item -ItemType Directory -Path (Join-Path -Path $Reports -ChildPath 'WsusMaintenance-20200101-000000-00000000.txt')
      New-Artifacts -Folder $script:Defaults -Extension 'log' -DaysAgo @(200)

      $Result = Remove-MaintenanceArtifact -Context (New-ArtifactContext -Logs $Logs -Reports $Reports -Summaries $Summaries -Retention '"reports": { "maxAgeDays": 0, "maxCount": 2 }')

      $Result.Status | Should -Be 'Success'
      @(Get-Names -Folder $Logs) | Should -HaveCount 5
      @(Get-Names -Folder $Logs) | Should -Contain 'WsusMaintenance-20261102-010000-aaaaaaaa.log'
      @(Get-Names -Folder $Logs) | Should -Contain 'other.log'
      @(Get-Names -Folder $Logs | Where-Object -FilterScript { $PSItem -like ('WsusMaintenance-{0}*' -f $script:RunStart.AddDays(-100).ToString('yyyyMMdd')) }) | Should -HaveCount 0
      @(Get-Names -Folder $Reports | Where-Object -FilterScript { $PSItem -like ('WsusMaintenance-{0}*' -f $script:RunStart.AddDays(-3).ToString('yyyyMMdd')) }) | Should -HaveCount 0
      @(Get-Names -Folder $Reports) | Should -HaveCount 5
      @(Get-Names -Folder $Summaries) | Should -HaveCount 1
      @(Get-Names -Folder $script:Defaults) | Should -HaveCount 0
      Test-Path -LiteralPath (Join-Path -Path $Reports -ChildPath 'WsusMaintenance-20200101-000000-00000000.txt') | Should -BeTrue
      $Result.Counts['logsDeleted'] | Should -Be 2
      $Result.Counts['reportsDeleted'] | Should -Be 2
      $Result.Counts['summariesDeleted'] | Should -Be 1
      $Result.Message | Should -Be 'Deleted 2 run log(s), 2 report file(s) and 1 summary file(s) beyond the retention; 0 failed.'
    }

    It 'never deletes the current run''s log or a run dated after the run start, which still count towards the limit' {
      $Logs = New-Folder
      $Null = New-File -Folder $Logs -Name 'WsusMaintenance-20261102-010000-aaaaaaaa.log'
      $Null = New-File -Folder $Logs -Name 'WsusMaintenance-20271231-000000-bbbbbbbb.log'
      New-Artifacts -Folder $Logs -Extension 'log' -DaysAgo @(1)

      $Result = Remove-MaintenanceArtifact -Context (New-ArtifactContext -Logs $Logs -Reports (New-Folder) -Summaries (New-Folder) -Retention '"logs": { "maxAgeDays": 0, "maxCount": 1 }')

      @(Get-Names -Folder $Logs) | Should -Be @('WsusMaintenance-20261102-010000-aaaaaaaa.log', 'WsusMaintenance-20271231-000000-bbbbbbbb.log')
      $Result.Counts['logsDeleted'] | Should -Be 1
    }

    It 'deletes nothing in a dry run and lists the files' {
      $Logs = New-Folder
      New-Artifacts -Folder $Logs -Extension 'log' -DaysAgo @(100)

      $Result = Remove-MaintenanceArtifact -Context (New-ArtifactContext -Logs $Logs -Reports (New-Folder) -Summaries (New-Folder) -DryRun $True)

      @(Get-Names -Folder $Logs) | Should -HaveCount 1
      $Result.Items[0] | Should -BeLike 'pending: *WsusMaintenance-*.log'
      $Result.Message | Should -Be 'pending: 1 artifact file(s) would be deleted.'
    }

    It 'reports an artifact it cannot delete as a warning' -Skip:(-not $script:OnWindows) {
      $Logs = New-Folder
      New-Artifacts -Folder $Logs -Extension 'log' -DaysAgo @(100)
      $Stream = [System.IO.File]::Open(([System.IO.Directory]::GetFiles($Logs)[0]), 'Open', 'Read', 'None')

      Try {
        $Result = Remove-MaintenanceArtifact -Context (New-ArtifactContext -Logs $Logs -Reports (New-Folder) -Summaries (New-Folder))
      } Finally {
        $Stream.Dispose()
      }

      $Result.Status | Should -Be 'Warning'
      $Result.Counts['Failed'] | Should -Be 1
    }
  }
}
