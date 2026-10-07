#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-HealthCheck.Blocked'    = 'Health checks {0} could not run: {1}.'
  'Invoke-HealthCheck.Failed'     = 'Health check {0} could not run: {1}'
  'Invoke-HealthCheck.NoIis'      = 'the IIS configuration could not be read ({0})'
  'Invoke-HealthCheck.NotRunItem' = '{0}: could not run'
  'Invoke-HealthCheck.Summary'    = 'Ran {0} health check(s): {1} finding(s), {2} check(s) could not run.'
}

Function Invoke-HealthCheck {
  <#
    .SYNOPSIS
        Runs the read-only health checks.

    .DESCRIPTION
        Runs each enabled check of health in turn: TLS in use, the expiry of the certificate bound to
        each WSUS TLS port, the .NET strong-cryptography values, the WSUS application-pool settings, the
        download settings against this deployment's expectations, the count of superseded updates that
        are not declined, and the processor count of a virtual machine. Each deviation raises its own
        notice with the current and the expected value, and each check adds one line to the items. A check
        that fails raises one notice for itself and the others still run; when the IIS configuration or
        the WSUS website cannot be read, one notice names the checks that depend on it. Nothing is ever
        changed.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Invoke-HealthCheck -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-healthcheck',
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
    $Context
  )

  Write-Debug -Message:'[Invoke-HealthCheck] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Blocked = [System.Collections.Generic.List[System.String]]::new()
  [PSCustomObject[]]$Private:Checks = @()
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Xml.XmlDocument]$Private:Iis = $Null
  [System.String]$Private:IisError = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Outcome = $Null
  [System.Object]$Private:Settings = $Null
  [PSCustomObject]$Private:Site = $Null
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Settings = $Context.Configuration.health
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  $Counts['Checks'] = [System.Int64]0
  $Counts['Findings'] = [System.Int64]0
  $Counts['NotRun'] = [System.Int64]0

  If (($Settings.certificateExpiry.enabled -eq $True) -or ($Settings.appPool.enabled -eq $True)) {
    Try {
      $Iis = Get-IisConfiguration
      $Site = Find-WsusWebSite -Iis:$Iis -Setup:(Get-WsusSetupValue) -SiteName:([System.String]$Context.Configuration.iisLogs.siteName)
      If ([System.String]::IsNullOrEmpty($Site.Error) -eq $False) {
        $IisError = $Site.Error
      }
    } Catch {
      $IisError = $Script:Message['Invoke-HealthCheck.NoIis'] -f $PSItem.Exception.GetBaseException().Message
    }
  }

  $Checks = @(
    [PSCustomObject]@{ Name = 'tls'; Label = 'TLS'; NeedsIis = $False }
    [PSCustomObject]@{ Name = 'certificateExpiry'; Label = 'certificate expiry'; NeedsIis = $True }
    [PSCustomObject]@{ Name = 'strongCrypto'; Label = 'strong cryptography'; NeedsIis = $False }
    [PSCustomObject]@{ Name = 'appPool'; Label = 'application pool'; NeedsIis = $True }
    [PSCustomObject]@{ Name = 'downloadSettings'; Label = 'download settings'; NeedsIis = $False }
    [PSCustomObject]@{ Name = 'supersededCount'; Label = 'superseded updates'; NeedsIis = $False }
    [PSCustomObject]@{ Name = 'processorCount'; Label = 'processors'; NeedsIis = $False }
  )

  ForEach ($Check In $Checks) {
    If ($Settings.($Check.Name).enabled -ne $True) {
      Continue
    }

    $Counts['Checks'] = $Counts['Checks'] + 1
    If (($Check.NeedsIis -eq $True) -and ([System.String]::IsNullOrEmpty($IisError) -eq $False)) {
      $Blocked.Add($Check.Label)
      $Items.Add(($Script:Message['Invoke-HealthCheck.NotRunItem'] -f $Check.Label))
      Continue
    }

    Try {
      Switch ($Check.Name) {
        'tls' { $Outcome = Test-WsusTlsHealth -Setup:(Get-WsusSetupValue) }
        'certificateExpiry' { $Outcome = Test-CertificateHealth -Now:$Context.RunStart.ToUniversalTime() -Port:$Site.HttpsPorts -WarningDays:([System.Int32[]]@($Settings.certificateExpiry.warningDays)) }
        'strongCrypto' { $Outcome = Test-StrongCryptoHealth }
        'appPool' { $Outcome = Test-AppPoolHealth -Expected:$Settings.appPool -Iis:$Iis -PoolName:$Site.AppPool }
        'downloadSettings' { $Outcome = Test-DownloadSettingHealth -Context:$Context -Expected:$Settings.downloadSettings }
        'supersededCount' { $Outcome = Test-SupersededCountHealth -Context:$Context -Threshold:([System.Int32]$Settings.supersededCount.threshold) }
        Default { $Outcome = Test-ProcessorHealth -Minimum:([System.Int32]$Settings.processorCount.minimum) }
      }

      $Items.Add($Outcome.Item)
      ForEach ($Notice In @($Outcome.Notices)) {
        $Notices.Add($Notice)
        $Counts['Findings'] = $Counts['Findings'] + 1
      }
    } Catch {
      $Counts['NotRun'] = $Counts['NotRun'] + 1
      $Items.Add(($Script:Message['Invoke-HealthCheck.NotRunItem'] -f $Check.Label))
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-HealthCheck.Failed'] -f $Check.Label, $PSItem.Exception.GetBaseException().Message) -Severity:'Warning' -Stage:$Context.StageName))
    }
  }

  If ($Blocked.Count -gt 0) {
    $Counts['NotRun'] = $Counts['NotRun'] + $Blocked.Count
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Invoke-HealthCheck.Blocked'] -f ($Blocked -join ', '), $IisError) -Severity:'Warning' -Stage:$Context.StageName))
  }

  If ($Notices.Count -gt 0) {
    $Status = 'Warning'
  }

  $Summary = $Script:Message['Invoke-HealthCheck.Summary'] -f $Counts['Checks'], $Counts['Findings'], $Counts['NotRun']
  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:$Items.ToArray() -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Invoke-HealthCheck] Exiting'
}
