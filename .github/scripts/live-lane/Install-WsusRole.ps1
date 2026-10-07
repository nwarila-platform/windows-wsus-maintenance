#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
  .SYNOPSIS
      Installs the WSUS role on the lane's SQL Server Express instance.

  .DESCRIPTION
      1. Installs the WSUS services with the SQL Server database option and the management tools
         (which carry the administration API): Install-WindowsFeature
         (https://learn.microsoft.com/powershell/module/servermanager/install-windowsfeature) with
         UpdateServices-Services and UpdateServices-DB, as the WSUS team documents for a SQL
         Server database
         (https://learn.microsoft.com/archive/blogs/wsus/configuring-wsus-6-x-for-network-load-balancing-nlb)
         and -IncludeManagementTools as in
         https://learn.microsoft.com/windows-server/administration/windows-server-update-services/deploy/1-install-the-wsus-server-role.
      2. Runs the post-installation tasks against the named instance:
         WsusUtil.exe postinstall SQL_INSTANCE_NAME="<computer>\<instance>" CONTENT_DIR=<folder>
         (https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/wsus-configure-shared-database,
         "Run post-installation tasks"; a local content folder as in step 1 of the WSUS deployment
         guide above).
      3. Records the WSUS setup values the script discovers (SQLServerName, SQLDatabaseName,
         UsingSSL, PortNumber, TargetDir, ContentDir; the same article lists them).
      4. Sends one request to the WSUS website and flushes the HTTP.sys log buffer
         (netsh http flush logbuffer,
         https://learn.microsoft.com/windows-server/networking/technologies/netsh/netsh-http), so
         that the site's IIS log folder exists as it does on any server that has served clients.

  .PARAMETER ContentPath
      WSUS content folder.

  .PARAMETER InstanceName
      SQL Server instance name.
#>
[CmdletBinding()]
Param (
  [Parameter(Mandatory = $True)][System.String]$ContentPath,
  [Parameter(Mandatory = $True)][System.String]$InstanceName
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'LiveLane.Common.ps1')

Write-LaneNote -Text ''
Write-LaneNote -Text '## WSUS role'
$Feature = Install-WindowsFeature -Name 'UpdateServices-Services', 'UpdateServices-DB' -IncludeManagementTools
Assert-LaneCondition -Condition ($Feature.Success -eq $True) -Message ('the WSUS role and its SQL Server database option are installed (restart needed: {0})' -f $Feature.RestartNeeded)
Assert-LaneCondition -Condition ([System.String]$Feature.RestartNeeded -ne 'Yes') -Message 'the role needs no restart, which a hosted runner cannot do'

$Null = New-Item -ItemType Directory -Path $ContentPath -Force
$WsusUtil = Join-Path -Path $env:ProgramFiles -ChildPath 'Update Services\Tools\WsusUtil.exe'
$Instance = '{0}\{1}' -f $env:COMPUTERNAME, $InstanceName
& $WsusUtil postinstall ('SQL_INSTANCE_NAME="{0}"' -f $Instance) ('CONTENT_DIR={0}' -f $ContentPath)
$PostInstallExit = $LASTEXITCODE
$PostInstallLog = @(Get-ChildItem -Path (Join-Path -Path $env:TEMP -ChildPath 'WSUS_PostInstall_*.log') -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending) | Select-Object -First 1
If ($Null -ne $PostInstallLog) {
  Get-Content -LiteralPath $PostInstallLog.FullName | Select-Object -Last 30 | ForEach-Object -Process { Write-Information -MessageData $PSItem -InformationAction Continue }
}

Assert-LaneCondition -Condition ($PostInstallExit -eq 0) -Message ('WsusUtil postinstall completed against {0} (exit code {1})' -f $Instance, $PostInstallExit)
Assert-LaneCondition -Condition ((Get-Service -Name 'WsusService').Status -eq 'Running') -Message 'the WSUS service is running'

$Setup = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup'
ForEach ($Name In @('SqlServerName', 'SqlDatabaseName', 'UsingSSL', 'PortNumber', 'TargetDir', 'ContentDir')) {
  $Value = $Null
  If ($Null -ne $Setup.PSObject.Properties[$Name]) {
    $Value = $Setup.$Name
  }

  Write-LaneNote -Text ('- WSUS setup value {0}: `{1}`' -f $Name, $Value)
}

Assert-LaneCondition -Condition ([System.String]$Setup.SqlServerName -ieq $Instance) -Message ('WSUS setup records SqlServerName {0}' -f $Instance)

# Any response proves the site is up; the request is logged.
$Port = [System.Int32]$Setup.PortNumber
Try {
  $Null = Invoke-WebRequest -Uri ('http://localhost:{0}/selfupdate/wuident.cab' -f $Port) -UseBasicParsing -Method Head
} Catch {
  Write-LaneNote -Text ('- the WSUS website answered: {0}' -f $PSItem.Exception.Message)
}

& netsh.exe http flush logbuffer
Write-LaneNote -Text ('- IIS log folders: {0}' -f (@(Get-ChildItem -Path (Join-Path -Path $env:SystemDrive -ChildPath 'inetpub\logs\LogFiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object -Process { $PSItem.Name }) -join ', '))
