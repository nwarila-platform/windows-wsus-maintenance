#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-WsusEnvironment.BadDatabase'     = "The SUSDB database name '{0}' is not a valid database name."
  'Get-WsusEnvironment.BadInstance'     = "'{0}' is not a SQL Server instance name this release can connect to (HOST or HOST\INSTANCE)."
  'Get-WsusEnvironment.Build'           = 'Windows build {0}'
  'Get-WsusEnvironment.DescribeLocal'   = "SQL Server on this server, instance {0}, database {1} (from {2})"
  'Get-WsusEnvironment.DescribeRemote'  = "SQL Server on another server, instance {0}, database {1} (from {2})"
  'Get-WsusEnvironment.DescribeUnknown' = "not determined (instance '{0}')"
  'Get-WsusEnvironment.DescribeWid'     = "Windows Internal Database ({0}), database {1}"
  'Get-WsusEnvironment.NoDatabase'      = 'WSUS setup records no database name (SqlDatabaseName) and discovery.databaseName is not set.'
  'Get-WsusEnvironment.NoInstance'      = 'WSUS setup records no SQL Server instance (SqlServerName) and discovery.sqlInstance is not set.'
  'Get-WsusEnvironment.NotInstalled'    = 'WSUS is not installed on this server: the registry key HKLM\SOFTWARE\Microsoft\Update Services\Server\Setup does not exist.'
  'Get-WsusEnvironment.OldWindows'      = '{0} (build {1}) is not supported; this release supports Windows Server 2019, 2022 and 2025.'
  'Get-WsusEnvironment.Remote'          = "SUSDB is on the remote SQL Server '{0}'; this release supports SUSDB on SQL Server on the WSUS server only."
  'Get-WsusEnvironment.Wid'             = "SUSDB is on Windows Internal Database ('{0}'); this release supports SUSDB on SQL Server on the WSUS server only."
}

Function Get-WsusEnvironment {
  <#
    .SYNOPSIS
        Discovers where SUSDB lives and whether this server is a supported combination.

    .DESCRIPTION
        Takes the SQL Server instance and database name from the values WSUS setup records in the
        registry, unless discovery.sqlInstance or discovery.databaseName overrides them, and classifies
        the database: an instance name carrying ##WID or ##SSEE is Windows Internal Database; any other
        valid name is SQL Server, local when its host is this computer (by name, fully qualified name,
        "." or localhost) and remote otherwise. Every unsupported combination becomes a problem that
        names it: WSUS not installed, Windows Server 2016 or older, a value that is neither recorded nor
        configured, an instance or database name that is not valid, Windows Internal Database, and
        remote SQL Server. The caller stops the run with the precondition-failure code when there is
        any problem.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER OperatingSystem
        Result of Get-MaintenanceOperatingSystem.

    .PARAMETER Setup
        Result of Get-WsusSetupValue; null when WSUS is not installed.

    .EXAMPLE
        Get-WsusEnvironment -Configuration $Effective -OperatingSystem (Get-MaintenanceOperatingSystem) -Setup (Get-WsusSetupValue)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-wsusenvironment',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $Configuration,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [PSCustomObject]
    $OperatingSystem,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Setup
  )

  Write-Debug -Message:'[Get-WsusEnvironment] Entering'

  # Initialize Variable(s)
  [System.String]$Private:DatabaseLocation = [System.String]::Empty
  [System.String]$Private:DatabaseName = [System.String]::Empty
  [System.String]$Private:DatabasePattern = '^[A-Za-z_][A-Za-z0-9_]{0,127}$'
  [System.String]$Private:DatabaseType = 'Unknown'
  [System.String]$Private:Description = [System.String]::Empty
  [System.String]$Private:HostPart = [System.String]::Empty
  [System.String]$Private:InstancePattern = '^[A-Za-z0-9._-]{1,253}(?:\\[A-Za-z_][A-Za-z0-9_$#]{0,15})?$'
  [System.String]$Private:InstanceSource = [System.String]::Empty
  [System.String]$Private:OperatingSystemName = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Problems = $Null
  [System.String]$Private:SqlServerName = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Problems = [System.Collections.Generic.List[System.String]]::new()

  Switch ($OperatingSystem.Build) {
    14393 { $OperatingSystemName = 'Windows Server 2016' }
    17763 { $OperatingSystemName = 'Windows Server 2019' }
    20348 { $OperatingSystemName = 'Windows Server 2022' }
    26100 { $OperatingSystemName = 'Windows Server 2025' }
    Default { $OperatingSystemName = $Script:Message['Get-WsusEnvironment.Build'] -f $OperatingSystem.Build }
  }

  If ($OperatingSystem.Build -lt 17763) {
    $Problems.Add(($Script:Message['Get-WsusEnvironment.OldWindows'] -f $OperatingSystemName, $OperatingSystem.Build))
  }

  If ($Null -eq $Setup) {
    $Problems.Add($Script:Message['Get-WsusEnvironment.NotInstalled'])
  }

  If ($Null -ne $Configuration.discovery.sqlInstance) {
    $SqlServerName = [System.String]$Configuration.discovery.sqlInstance
    $InstanceSource = 'configuration'
  } Else {
    $SqlServerName = [System.String](Get-MaintenancePropertyValue -InputObject:$Setup -Name:'SqlServerName' -Default:'')
    $InstanceSource = 'WSUS setup'
  }

  If ($Null -ne $Configuration.discovery.databaseName) {
    $DatabaseName = [System.String]$Configuration.discovery.databaseName
  } Else {
    $DatabaseName = [System.String](Get-MaintenancePropertyValue -InputObject:$Setup -Name:'SqlDatabaseName' -Default:'')
  }

  If ([System.String]::IsNullOrWhiteSpace($SqlServerName) -eq $True) {
    If ($Null -ne $Setup) {
      $Problems.Add($Script:Message['Get-WsusEnvironment.NoInstance'])
    }
  } ElseIf ($SqlServerName -match '##(?:WID|SSEE)') {
    $DatabaseType = 'WindowsInternalDatabase'
    $Problems.Add(($Script:Message['Get-WsusEnvironment.Wid'] -f $SqlServerName))
  } ElseIf ($SqlServerName -notmatch $InstancePattern) {
    $Problems.Add(($Script:Message['Get-WsusEnvironment.BadInstance'] -f $SqlServerName))
  } Else {
    $DatabaseType = 'SqlServer'
    $HostPart = ($SqlServerName -split '\\', 2)[0]
    If ((@('.', 'localhost', '127.0.0.1') -contains $HostPart) -or ($HostPart -ieq [System.Environment]::MachineName) -or ($HostPart -ilike ('{0}.*' -f [System.Environment]::MachineName))) {
      $DatabaseLocation = 'Local'
    } Else {
      $DatabaseLocation = 'Remote'
      $Problems.Add(($Script:Message['Get-WsusEnvironment.Remote'] -f $SqlServerName))
    }
  }

  If ([System.String]::IsNullOrWhiteSpace($DatabaseName) -eq $True) {
    If ($Null -ne $Setup) {
      $Problems.Add($Script:Message['Get-WsusEnvironment.NoDatabase'])
    }
  } ElseIf ($DatabaseName -notmatch $DatabasePattern) {
    $Problems.Add(($Script:Message['Get-WsusEnvironment.BadDatabase'] -f $DatabaseName))
  }

  Switch ($DatabaseType) {
    'WindowsInternalDatabase' { $Description = $Script:Message['Get-WsusEnvironment.DescribeWid'] -f $SqlServerName, $DatabaseName }
    'SqlServer' {
      If ($DatabaseLocation -eq 'Local') {
        $Description = $Script:Message['Get-WsusEnvironment.DescribeLocal'] -f $SqlServerName, $DatabaseName, $InstanceSource
      } Else {
        $Description = $Script:Message['Get-WsusEnvironment.DescribeRemote'] -f $SqlServerName, $DatabaseName, $InstanceSource
      }
    }
    Default { $Description = $Script:Message['Get-WsusEnvironment.DescribeUnknown'] -f $SqlServerName }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    OperatingSystem  = [System.String]$OperatingSystemName
    Build            = [System.Int32]$OperatingSystem.Build
    SqlServerName    = [System.String]$SqlServerName
    DatabaseName     = [System.String]$DatabaseName
    DatabaseType     = [System.String]$DatabaseType
    DatabaseLocation = [System.String]$DatabaseLocation
    Description      = [System.String]$Description
    Problems         = [System.String[]]$Problems.ToArray()
  }

  $Result
  Write-Debug -Message:'[Get-WsusEnvironment] Exiting'
}
