#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-AppPoolHealth.Deviation'    = 'Application pool {0}: {1} is {2}; expected {3}, as Microsoft recommends for WSUS.'
  'Test-AppPoolHealth.Item'         = 'application pool {0}: {1} setting(s) differ from the expected values'
  'Test-AppPoolHealth.NotFound'     = 'The application pool {0} of the WSUS website is not in the IIS configuration.'
  'Test-AppPoolHealth.NotFoundItem' = 'application pool {0}: not found'
}

Function Test-AppPoolHealth {
  <#
    .SYNOPSIS
        Compares the WSUS application-pool settings with the expected values.

    .DESCRIPTION
        Reads the application pool of the WSUS website from the IIS configuration (falling back to the
        pool defaults, then to the IIS defaults, for a setting the pool does not set) and compares queue
        length, idle time-out, pinging, private and virtual memory limits and the regular recycling
        interval with health.appPool, whose defaults are Microsoft's recommendations for WsusPool. Each
        setting that differs raises its own Warning notice with the current and expected values. A pool
        that is not in the configuration raises a Warning notice.

    .PARAMETER Expected
        health.appPool.

    .PARAMETER Iis
        The IIS configuration.

    .PARAMETER PoolName
        Name of the WSUS application pool.

    .EXAMPLE
        Test-AppPoolHealth -Expected $Configuration.health.appPool -Iis (Get-IisConfiguration) -PoolName 'WsusPool'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-apppoolhealth',
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
    [System.Object]
    $Expected,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [System.Xml.XmlDocument]
    $Iis,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $PoolName
  )

  Write-Debug -Message:'[Test-AppPoolHealth] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Current = [System.String]::Empty
  [System.Xml.XmlNode]$Private:Defaults = $Null
  [System.Int32]$Private:Deviations = 0
  [System.String]$Private:Item = [System.String]::Empty
  [System.Xml.XmlNode]$Private:Node = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [System.Xml.XmlNode]$Private:Pool = $Null
  [System.String]$Private:Raw = [System.String]::Empty
  [PSCustomObject[]]$Private:Settings = @()
  [PSCustomObject]$Private:Result = $Null

  # https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/windows-server-update-services-best-practices
  ForEach ($Node In @($Iis.SelectNodes('/configuration/system.applicationHost/applicationPools/add'))) {
    If ([System.String]::Equals($Node.GetAttribute('name'), $PoolName, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
      $Pool = $Node
    }
  }

  If ($Null -eq $Pool) {
    $Item = $Script:Message['Test-AppPoolHealth.NotFoundItem'] -f $PoolName
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-AppPoolHealth.NotFound'] -f $PoolName) -Severity:'Warning' -Stage:'HealthChecks'))
  } Else {
    $Defaults = $Iis.SelectSingleNode('/configuration/system.applicationHost/applicationPools/applicationPoolDefaults')
    $Settings = @(
      [PSCustomObject]@{ Name = 'queue length'; Path = '@queueLength'; Fallback = '1000'; Kind = 'Number'; Expected = [System.String]$Expected.queueLength }
      [PSCustomObject]@{ Name = 'idle time-out (minutes)'; Path = 'processModel/@idleTimeout'; Fallback = '00:20:00'; Kind = 'Minutes'; Expected = [System.String]$Expected.idleTimeoutMinutes }
      [PSCustomObject]@{ Name = 'pinging enabled'; Path = 'processModel/@pingingEnabled'; Fallback = 'true'; Kind = 'Boolean'; Expected = ([System.String]$Expected.pingingEnabled).ToLowerInvariant() }
      [PSCustomObject]@{ Name = 'private memory limit (KB)'; Path = 'recycling/periodicRestart/@privateMemory'; Fallback = '0'; Kind = 'Number'; Expected = [System.String]$Expected.privateMemoryLimitKb }
      [PSCustomObject]@{ Name = 'virtual memory limit (KB)'; Path = 'recycling/periodicRestart/@memory'; Fallback = '0'; Kind = 'Number'; Expected = [System.String]$Expected.virtualMemoryLimitKb }
      [PSCustomObject]@{ Name = 'regular recycling interval (minutes)'; Path = 'recycling/periodicRestart/@time'; Fallback = '1.05:00:00'; Kind = 'Minutes'; Expected = [System.String]$Expected.regularRecyclingMinutes }
    )

    ForEach ($Setting In $Settings) {
      $Node = $Pool.SelectSingleNode($Setting.Path)
      If (($Null -eq $Node) -and ($Null -ne $Defaults)) {
        $Node = $Defaults.SelectSingleNode($Setting.Path)
      }

      If ($Null -ne $Node) {
        $Raw = [System.String]$Node.Value
      } Else {
        $Raw = $Setting.Fallback
      }

      If ($Setting.Kind -eq 'Minutes') {
        $Current = [System.String][System.Int64][System.Math]::Floor([System.TimeSpan]::Parse($Raw, [System.Globalization.CultureInfo]::InvariantCulture).TotalMinutes)
      } Else {
        $Current = $Raw.ToLowerInvariant()
      }

      If ($Current -ne $Setting.Expected) {
        $Deviations++
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-AppPoolHealth.Deviation'] -f $PoolName, $Setting.Name, $Current, $Setting.Expected) -Severity:'Warning' -Stage:'HealthChecks'))
      }
    }

    $Item = $Script:Message['Test-AppPoolHealth.Item'] -f $PoolName, $Deviations
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]$Item
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-AppPoolHealth] Exiting'
}
