#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-DownloadSettingHealth.Item'   = 'download settings: {0} differ from this deployment''s expected values'
  'Test-DownloadSettingHealth.Notice' = 'WSUS download setting {0} is {1}; this deployment expects {2} (health.downloadSettings.{3}). Configuration management owns the setting; it was not changed.'
}

Function Test-DownloadSettingHealth {
  <#
    .SYNOPSIS
        Compares the WSUS download settings with the values this deployment expects.

    .DESCRIPTION
        Reads the server's download settings (IUpdateServer.GetConfiguration) and compares them with
        health.downloadSettings: express installation files (DownloadExpressPackages), download only
        when approved (DownloadUpdateBinariesAsNeeded) and files stored on this server
        (HostBinariesOnMicrosoftUpdate off). The expectations are per deployment: a downstream that
        stages content expects downloads only when approved, while a top-tier server that serves every
        update expects every update downloaded. Each setting that differs raises its own Warning notice.
        The settings belong to configuration management and are never changed.

    .PARAMETER Context
        The stage context.

    .PARAMETER Expected
        health.downloadSettings.

    .EXAMPLE
        Test-DownloadSettingHealth -Context $Context -Expected $Configuration.health.downloadSettings

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-downloadsettinghealth',
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
    $Context,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [System.Object]
    $Expected
  )

  Write-Debug -Message:'[Test-DownloadSettingHealth] Entering'

  # Initialize Variable(s)
  [PSCustomObject[]]$Private:Checks = @()
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [System.Object]$Private:ServerSettings = $Null
  [PSCustomObject]$Private:Result = $Null

  # https://learn.microsoft.com/previous-versions/windows/desktop/ms752728(v=vs.85)
  $ServerSettings = (Get-WsusConnection -Context:$Context).GetConfiguration()
  $Checks = @(
    [PSCustomObject]@{ Name = 'DownloadExpressPackages'; Key = 'expressFiles'; Current = [System.Boolean]$ServerSettings.DownloadExpressPackages; Expected = [System.Boolean]$Expected.expressFiles }
    [PSCustomObject]@{ Name = 'DownloadUpdateBinariesAsNeeded'; Key = 'downloadOnlyWhenApproved'; Current = [System.Boolean]$ServerSettings.DownloadUpdateBinariesAsNeeded; Expected = [System.Boolean]$Expected.downloadOnlyWhenApproved }
    [PSCustomObject]@{ Name = 'HostBinariesOnMicrosoftUpdate'; Key = 'storeFilesLocally'; Current = [System.Boolean]$ServerSettings.HostBinariesOnMicrosoftUpdate; Expected = -not [System.Boolean]$Expected.storeFilesLocally }
  )

  ForEach ($Check In $Checks) {
    If ($Check.Current -ne $Check.Expected) {
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-DownloadSettingHealth.Notice'] -f $Check.Name, $Check.Current, $Check.Expected, $Check.Key) -Severity:'Warning' -Stage:'HealthChecks'))
    }
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]($Script:Message['Test-DownloadSettingHealth.Item'] -f $Notices.Count)
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-DownloadSettingHealth] Exiting'
}
