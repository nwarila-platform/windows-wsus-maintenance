#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Shared helpers of the live lane (.github/workflows/live-lane.yaml): notes for the job summary,
# assertions, pinned downloads, T-SQL against the lane's SQL Server Express instance, and runs of
# the installed script as SYSTEM through a scheduled task. Dot-source this file.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Script:LaneInstallFolder = 'C:\ProgramData\NWarila\bin'
$Script:LaneScriptPath = [System.IO.Path]::Combine($Script:LaneInstallFolder, 'Invoke-WsusMaintenance.ps1')
$Script:LaneDataFolder = 'C:\ProgramData\NWarila\WsusMaintenance'
$Script:LaneConfigPath = [System.IO.Path]::Combine($Script:LaneDataFolder, 'maintenance.json')
$Script:LaneTaskName = 'Invoke-WsusMaintenance live lane'
$Script:LaneEventSource = 'Invoke-WsusMaintenance'

Function Write-LaneNote {
  Param ([Parameter(Mandatory = $True)][AllowEmptyString()][System.String]$Text)

  Write-Information -MessageData $Text -InformationAction Continue
  If ([System.String]::IsNullOrEmpty($env:GITHUB_STEP_SUMMARY) -eq $False) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $Text -Encoding UTF8
  }
}

Function Assert-LaneCondition {
  Param (
    [Parameter(Mandatory = $True)][System.Boolean]$Condition,
    [Parameter(Mandatory = $True)][System.String]$Message
  )

  If ($Condition -eq $False) {
    Write-LaneNote -Text ('- FAILED: {0}' -f $Message)
    Throw ('Live lane assertion failed: {0}' -f $Message)
  }

  Write-LaneNote -Text ('- passed: {0}' -f $Message)
}

# A download is used only when its SHA-256 matches the value pinned in the workflow. With
#   -Record the hash is printed instead, so that a first run can record the pin.
#   Get-FileHash: https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/get-filehash
Function Assert-LanePin {
  Param (
    [Parameter(Mandatory = $True)][System.String]$Path,
    [Parameter(Mandatory = $True)][AllowEmptyString()][System.String]$Expected,
    [System.Boolean]$Record = $False
  )

  $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  $Name = Split-Path -Path $Path -Leaf
  If ($Record -eq $True) {
    Write-LaneNote -Text ('- SHA-256 of {0} to pin: `{1}`' -f $Name, $Actual)
  } ElseIf ([System.String]::IsNullOrWhiteSpace($Expected) -eq $True) {
    Throw ('No SHA-256 pin is recorded for {0} (it is {1}). Run the workflow by hand with record-pins, then record the value in the workflow.' -f $Name, $Actual)
  } ElseIf ($Actual -ne $Expected.Trim().ToLowerInvariant()) {
    Throw ('SHA-256 mismatch for {0}: pinned {1}, downloaded {2}.' -f $Name, $Expected, $Actual)
  } Else {
    Write-LaneNote -Text ('- passed: {0} matches its pinned SHA-256' -f $Name)
  }
}

# Runs one T-SQL batch against the lane's instance with Windows authentication, through the
#   SQL Server client of the .NET Framework, and returns the rows as objects.
#   https://learn.microsoft.com/dotnet/api/system.data.sqlclient.sqlconnection
Function Invoke-LaneSql {
  Param (
    [Parameter(Mandatory = $True)][System.String]$Query,
    [System.String]$Database = 'master'
  )

  $Builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
  $Builder['Data Source'] = '{0}\{1}' -f $env:COMPUTERNAME, $env:SQL_INSTANCE
  $Builder['Initial Catalog'] = $Database
  $Builder['Integrated Security'] = $True
  $Builder['Connect Timeout'] = 60
  $Connection = [System.Data.SqlClient.SqlConnection]::new($Builder.ConnectionString)
  Try {
    $Connection.Open()
    $Command = $Connection.CreateCommand()
    $Command.CommandText = $Query
    $Command.CommandTimeout = 0
    $Reader = $Command.ExecuteReader()
    Try {
      Do {
        While ($Reader.Read() -eq $True) {
          $Row = [ordered]@{}
          For ($Index = 0; $Index -lt $Reader.FieldCount; $Index++) {
            $Row[$Reader.GetName($Index)] = $(If ($Reader.IsDBNull($Index)) { $Null } Else { $Reader.GetValue($Index) })
          }
          [PSCustomObject]$Row
        }
      } While ($Reader.NextResult() -eq $True)
    } Finally {
      $Reader.Dispose()
    }
  } Finally {
    $Connection.Dispose()
  }
}

# Runs the installed script once as SYSTEM through a scheduled task, as the deployment does, and
#   waits for it to finish. Returns the exit code Task Scheduler recorded, the start time, and the
#   summary the run wrote (null when it wrote none). With -NoWait it returns once the run started.
#   New-ScheduledTaskAction, New-ScheduledTaskPrincipal (SYSTEM, service account logon, highest
#   run level), New-ScheduledTaskSettingsSet, Register-ScheduledTask, Start-ScheduledTask and
#   Get-ScheduledTaskInfo: https://learn.microsoft.com/powershell/module/scheduledtasks/
#   powershell.exe -File: https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_powershell_exe
Function Invoke-LaneTask {
  Param (
    [System.String[]]$Argument = @(),
    [System.String]$ScriptPath = $Script:LaneScriptPath,
    [System.Int32]$TimeoutMinutes = 90,
    [System.Management.Automation.SwitchParameter]$NoWait
  )

  $Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ConfigPath "{1}" {2}' -f $ScriptPath, $Script:LaneConfigPath, ($Argument -join ' ')
  $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $Arguments.Trim()
  $Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
  $Null = Register-ScheduledTask -TaskName $Script:LaneTaskName -Action $Action -Principal $Principal -Settings $Settings -Force

  $Before = (Get-ScheduledTaskInfo -TaskName $Script:LaneTaskName).LastRunTime
  $StartedAt = Get-Date
  Start-ScheduledTask -TaskName $Script:LaneTaskName
  $Deadline = $StartedAt.AddMinutes($TimeoutMinutes)

  # The task has started once its last run time moves.
  Do {
    Start-Sleep -Milliseconds 200
    $Info = Get-ScheduledTaskInfo -TaskName $Script:LaneTaskName
  } While (($Info.LastRunTime -eq $Before) -and ((Get-Date) -lt $Deadline))

  If ($NoWait.IsPresent -eq $False) {
    Do {
      Start-Sleep -Seconds 2
      $State = [System.String](Get-ScheduledTask -TaskName $Script:LaneTaskName).State
    } While (($State -eq 'Running') -and ((Get-Date) -lt $Deadline))

    If ($State -eq 'Running') {
      Stop-ScheduledTask -TaskName $Script:LaneTaskName
      Throw ('The run did not finish within {0} minutes: {1}' -f $TimeoutMinutes, $Arguments)
    }
  }

  [PSCustomObject]@{
    Arguments = $Arguments
    StartedAt = $StartedAt
    ExitCode  = $(If ($NoWait.IsPresent) { $Null } Else { [System.Int32](Get-ScheduledTaskInfo -TaskName $Script:LaneTaskName).LastTaskResult })
    Summary   = $(If ($NoWait.IsPresent) { $Null } Else { Get-LaneSummary -Since $StartedAt })
  }
}

# The newest summary written since a run started, parsed, with its path; null when none.
Function Get-LaneSummary {
  Param ([Parameter(Mandatory = $True)][System.DateTime]$Since)

  $Folder = [System.IO.Path]::Combine($Script:LaneDataFolder, 'Summaries')
  $File = @(Get-ChildItem -LiteralPath $Folder -Filter 'WsusMaintenance-*.json' -File -ErrorAction SilentlyContinue |
      Where-Object -FilterScript { $PSItem.LastWriteTime -ge $Since.AddSeconds(-2) } |
      Sort-Object -Property LastWriteTime -Descending) | Select-Object -First 1
  If ($Null -ne $File) {
    $Summary = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
    $Summary | Add-Member -NotePropertyName Path -NotePropertyValue $File.FullName
    $Summary
  }
}

# The newest run log written since a run started, or null.
Function Get-LaneLog {
  Param ([Parameter(Mandatory = $True)][System.DateTime]$Since)

  $Folder = [System.IO.Path]::Combine($Script:LaneDataFolder, 'Logs')
  @(Get-ChildItem -LiteralPath $Folder -Filter 'WsusMaintenance-*.log' -File -ErrorAction SilentlyContinue |
      Where-Object -FilterScript { $PSItem.CreationTime -ge $Since.AddSeconds(-2) } |
      Sort-Object -Property CreationTime -Descending) | Select-Object -First 1
}

Function Get-LaneStage {
  Param (
    [Parameter(Mandatory = $True)]$Summary,
    [Parameter(Mandatory = $True)][System.String]$Name
  )

  @($Summary.stages | Where-Object -FilterScript { $PSItem.name -eq $Name })[0]
}

# The identifiers of the events the script wrote since a run started, oldest first.
#   Get-WinEvent: https://learn.microsoft.com/powershell/module/microsoft.powershell.diagnostics/get-winevent
Function Get-LaneEventId {
  Param ([Parameter(Mandatory = $True)][System.DateTime]$Since)

  @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = $Script:LaneEventSource; StartTime = $Since.AddSeconds(-2) } -ErrorAction SilentlyContinue |
      Sort-Object -Property RecordId | ForEach-Object -Process { [System.Int32]$PSItem.Id })
}

# Checks what every completed run must show: the exit code Task Scheduler recorded matches the
#   summary, it is one of the expected codes, and no stage ended in error.
Function Assert-LaneRun {
  Param (
    [Parameter(Mandatory = $True)]$Run,
    [Parameter(Mandatory = $True)][System.String]$Label,
    [System.Int32[]]$ExpectedExitCode = @(0, 2)
  )

  Write-LaneNote -Text ''
  Write-LaneNote -Text ('### {0}' -f $Label)
  Write-LaneNote -Text ('Arguments: `{0}`; exit code {1}.' -f $Run.Arguments, $Run.ExitCode)
  Assert-LaneCondition -Condition ($ExpectedExitCode -contains $Run.ExitCode) -Message ('{0}: exit code {1} is one of {2}' -f $Label, $Run.ExitCode, ($ExpectedExitCode -join ', '))
  Assert-LaneCondition -Condition ($Null -ne $Run.Summary) -Message ('{0}: a summary was written' -f $Label)
  Assert-LaneCondition -Condition ([System.Int32]$Run.Summary.exitCode -eq $Run.ExitCode) -Message ('{0}: the summary records the same exit code as Task Scheduler' -f $Label)
  $Failed = @($Run.Summary.stages | Where-Object -FilterScript { $PSItem.status -eq 'Error' } | ForEach-Object -Process { '{0} ({1})' -f $PSItem.name, $PSItem.errorMessage })
  Assert-LaneCondition -Condition ($Failed.Count -eq 0) -Message ('{0}: no stage ended in error{1}' -f $Label, $(If ($Failed.Count -gt 0) { ': ' + ($Failed -join '; ') } Else { '' }))
  ForEach ($Notice In @($Run.Summary.notices)) {
    Write-LaneNote -Text ('  - notice {0}: {1}' -f $Notice.severity, $Notice.message)
  }
}
