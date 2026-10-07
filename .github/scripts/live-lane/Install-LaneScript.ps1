#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Installs the built script as the deployment does.

  .DESCRIPTION
      1. Creates the installation folder and the configuration folder with an access control list
         that only SYSTEM and Administrators can change: icacls /inheritance:r and
         /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F
         (https://learn.microsoft.com/windows-server/administration/windows-commands/icacls).
      2. Copies the built script into the installation folder and writes the configuration
         document; the data folders are left for the script to create.
      3. Registers the event source in the Application log: New-EventLog
         (https://learn.microsoft.com/powershell/module/microsoft.powershell.management/new-eventlog?view=powershell-5.1).
      4. Gives SYSTEM a login and makes it the owner of SUSDB, as the deployment does: CREATE LOGIN
         ... FROM WINDOWS (https://learn.microsoft.com/sql/t-sql/statements/create-login-transact-sql)
         and ALTER AUTHORIZATION ON DATABASE::SUSDB
         (https://learn.microsoft.com/sql/t-sql/statements/alter-authorization-transact-sql).

  .PARAMETER BackupPath
      Backup destination written into the configuration document. It must not exist yet, so that
      the script creates it protected.

  .PARAMETER BuiltScript
      Path of the built Invoke-WsusMaintenance.ps1.
#>
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $True)][System.String]$BackupPath,
  [Parameter(Mandatory = $True)][System.String]$BuiltScript
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'LiveLane.Common.ps1')

Write-LaneNote -Text ''
Write-LaneNote -Text '## Installation'
ForEach ($Folder In @($Script:LaneInstallFolder, $Script:LaneDataFolder)) {
  $Null = New-Item -ItemType Directory -Path $Folder -Force
  & icacls.exe $Folder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
  Assert-LaneCondition -Condition ($LASTEXITCODE -eq 0) -Message ('{0} is protected for SYSTEM and Administrators' -f $Folder)
}

Copy-Item -LiteralPath $BuiltScript -Destination $Script:LaneScriptPath -Force
Assert-LaneCondition -Condition ((Get-FileHash -LiteralPath $Script:LaneScriptPath).Hash -eq (Get-FileHash -LiteralPath $BuiltScript).Hash) -Message ('the built script is installed at {0}' -f $Script:LaneScriptPath)

# No TLS on this lane (the replica proof covers it), so the TLS and certificate checks are off.
$Configuration = [ordered]@{
  schemaVersion = 1
  backup        = [ordered]@{ destination = $BackupPath }
  health        = [ordered]@{
    tls               = [ordered]@{ enabled = $False }
    certificateExpiry = [ordered]@{ enabled = $False }
  }
}
[System.IO.File]::WriteAllText($Script:LaneConfigPath, (ConvertTo-Json -InputObject $Configuration -Depth 8), [System.Text.UTF8Encoding]::new($False))
Write-LaneNote -Text ('- configuration document: `{0}`' -f ((Get-Content -LiteralPath $Script:LaneConfigPath -Raw) -replace '\s+', ' '))

If ([System.Diagnostics.EventLog]::SourceExists($Script:LaneEventSource) -eq $False) {
  New-EventLog -LogName 'Application' -Source $Script:LaneEventSource
}

Assert-LaneCondition -Condition ([System.Diagnostics.EventLog]::LogNameFromSourceName($Script:LaneEventSource, '.') -eq 'Application') -Message 'the event source is registered in the Application log'

$Null = Invoke-LaneSql -Query @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'NT AUTHORITY\SYSTEM')
  CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS;
ALTER AUTHORIZATION ON DATABASE::SUSDB TO [NT AUTHORITY\SYSTEM];
"@
$Owner = @(Invoke-LaneSql -Query "SELECT SUSER_SNAME(owner_sid) AS Owner, IS_SRVROLEMEMBER(N'sysadmin', N'NT AUTHORITY\SYSTEM') AS SystemIsSysadmin FROM sys.databases WHERE name = N'SUSDB'")[0]
Assert-LaneCondition -Condition ([System.String]$Owner.Owner -eq 'NT AUTHORITY\SYSTEM') -Message 'SYSTEM owns SUSDB'
Write-LaneNote -Text ('- SYSTEM is a sysadmin: {0} (expected 0: only the owner rights are granted)' -f $Owner.SystemIsSysadmin)
Assert-LaneCondition -Condition (-not (Test-Path -LiteralPath $BackupPath)) -Message ('the backup folder {0} does not exist yet, so the script creates it' -f $BackupPath)
