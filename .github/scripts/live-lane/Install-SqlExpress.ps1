#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Installs a named instance of SQL Server 2022 Express for the live lane.

  .DESCRIPTION
      1. Downloads the SQL Server 2022 Express installer from the link Microsoft publishes
         (https://go.microsoft.com/fwlink/?linkid=2215160, listed under "Installation media" in
         https://learn.microsoft.com/sql/database-engine/configure-windows/sql-server-express-localdb)
         and checks it against its pinned SHA-256.
      2. Uses that installer, which only downloads the real setup package, to download the Express
         Core media (SQLEXPR_x64_ENU.exe), and checks that against its pinned SHA-256. Microsoft
         describes this two-step flow for unattended installs: download the media with the
         installer, extract it, then run setup.exe
         (https://techcommunity.microsoft.com/discussions/sql_server/2019-express-silent-install/1115671).
         The installer's switches (/ACTION=Download /MEDIAPATH /MEDIATYPE=Core /QUIET) are its own
         and are not documented on Microsoft Learn; they are checked by the first lane run.
      3. Extracts the package with /q /x:<folder>: the compressed Express package passes its
         parameters to setup.exe and extracts with /x
         (https://learn.microsoft.com/archive/blogs/sqlexpress/configuring-sql-express-during-installation).
      4. Runs setup.exe quietly with the Database Engine only, as documented in
         https://learn.microsoft.com/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt:
         /Q /ACTION=Install /FEATURES=SQLENGINE /INSTANCENAME, /SQLSYSADMINACCOUNTS (the runner's
         own account only, so that SYSTEM is not a sysadmin and must be made the SUSDB owner as
         the deployment does), /IACCEPTSQLSERVERLICENSETERMS, /SUPPRESSPRIVACYSTATEMENTNOTICE and
         /UPDATEENABLED=False. The service runs as its virtual account, NT SERVICE\MSSQL$<instance>
         (https://learn.microsoft.com/sql/database-engine/configure-windows/configure-windows-service-accounts-and-permissions).

  .PARAMETER BootstrapperSha256
      Pinned SHA-256 of the installer; empty until recorded.

  .PARAMETER BootstrapperUrl
      Download link of the installer.

  .PARAMETER InstanceName
      SQL Server instance name.

  .PARAMETER MediaSha256
      Pinned SHA-256 of SQLEXPR_x64_ENU.exe; empty until recorded.

  .PARAMETER RecordPins
      Print the SHA-256 of both downloads instead of requiring the pins.

  .PARAMETER WorkPath
      Folder for the downloads and the extracted media.
#>
[CmdletBinding()]
Param (
  [AllowEmptyString()][System.String]$BootstrapperSha256 = '',
  [Parameter(Mandatory = $True)][System.String]$BootstrapperUrl,
  [Parameter(Mandatory = $True)][System.String]$InstanceName,
  [AllowEmptyString()][System.String]$MediaSha256 = '',
  [System.Management.Automation.SwitchParameter]$RecordPins,
  [Parameter(Mandatory = $True)][System.String]$WorkPath
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'LiveLane.Common.ps1')

Write-LaneNote -Text '## SQL Server 2022 Express'
$Null = New-Item -ItemType Directory -Path $WorkPath -Force
$Bootstrapper = Join-Path -Path $WorkPath -ChildPath 'SQL2022-SSEI-Expr.exe'
$MediaPath = Join-Path -Path $WorkPath -ChildPath 'media'
$SetupPath = Join-Path -Path $WorkPath -ChildPath 'setup'

# Invoke-WebRequest: https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/invoke-webrequest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $BootstrapperUrl -OutFile $Bootstrapper -UseBasicParsing
Assert-LanePin -Path $Bootstrapper -Expected $BootstrapperSha256 -Record $RecordPins.IsPresent

$Download = Start-Process -FilePath $Bootstrapper -ArgumentList @('/ACTION=Download', ('/MEDIAPATH="{0}"' -f $MediaPath), '/MEDIATYPE=Core', '/QUIET') -Wait -PassThru
Assert-LaneCondition -Condition ($Download.ExitCode -eq 0) -Message ('the installer downloaded the Express Core media (exit code {0})' -f $Download.ExitCode)
$Package = @(Get-ChildItem -LiteralPath $MediaPath -Filter 'SQLEXPR*.exe' -File -Recurse) | Select-Object -First 1
Assert-LaneCondition -Condition ($Null -ne $Package) -Message 'the Express Core package is in the media folder'
Assert-LanePin -Path $Package.FullName -Expected $MediaSha256 -Record $RecordPins.IsPresent

$Extract = Start-Process -FilePath $Package.FullName -ArgumentList @('/q', ('/x:"{0}"' -f $SetupPath)) -Wait -PassThru
Assert-LaneCondition -Condition (($Extract.ExitCode -eq 0) -and (Test-Path -LiteralPath (Join-Path -Path $SetupPath -ChildPath 'setup.exe'))) -Message ('the package extracted setup.exe (exit code {0})' -f $Extract.ExitCode)

$Administrator = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$SetupArguments = @(
  '/Q',
  '/ACTION=Install',
  '/FEATURES=SQLENGINE',
  ('/INSTANCENAME={0}' -f $InstanceName),
  ('/SQLSYSADMINACCOUNTS="{0}"' -f $Administrator),
  '/IACCEPTSQLSERVERLICENSETERMS',
  '/SUPPRESSPRIVACYSTATEMENTNOTICE',
  '/UPDATEENABLED=False',
  '/INDICATEPROGRESS'
)
$Setup = Start-Process -FilePath (Join-Path -Path $SetupPath -ChildPath 'setup.exe') -ArgumentList $SetupArguments -Wait -PassThru -NoNewWindow
$SummaryFile = @(Get-ChildItem -Path 'C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\Summary.txt' -ErrorAction SilentlyContinue) | Select-Object -First 1
If ($Null -ne $SummaryFile) {
  Get-Content -LiteralPath $SummaryFile.FullName | Select-Object -First 40 | ForEach-Object -Process { Write-Information -MessageData $PSItem -InformationAction Continue }
}

# 3010 means a restart is recommended; the service is checked either way.
Assert-LaneCondition -Condition (@(0, 3010) -contains $Setup.ExitCode) -Message ('SQL Server setup completed (exit code {0})' -f $Setup.ExitCode)
$Service = Get-Service -Name ('MSSQL${0}' -f $InstanceName)
Assert-LaneCondition -Condition ($Service.Status -eq 'Running') -Message ('the service MSSQL${0} is running' -f $InstanceName)
$Version = @(Invoke-LaneSql -Query "SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS Version, CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS Edition")[0]
Write-LaneNote -Text ('- SQL Server {0}, {1}' -f $Version.Version, $Version.Edition)
