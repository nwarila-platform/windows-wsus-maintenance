#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-WsusTlsHealth.InUse'    = 'TLS: in use'
  'Test-WsusTlsHealth.Missing'  = 'not recorded'
  'Test-WsusTlsHealth.NoSetup'  = 'the WSUS setup values could not be read'
  'Test-WsusTlsHealth.NotInUse' = 'TLS: not in use'
  'Test-WsusTlsHealth.Notice'   = 'WSUS does not use TLS (UsingSSL is {0}). Microsoft recommends configuring TLS as the first step after installation.'
}

Function Test-WsusTlsHealth {
  <#
    .SYNOPSIS
        Checks that WSUS uses TLS.

    .DESCRIPTION
        Reads whether WSUS setup recorded TLS for the WSUS web services (the UsingSSL value) and raises a
        Warning notice when it did not: Microsoft recommends configuring TLS as the first step after
        installation. Throws when the WSUS setup values cannot be read.

    .PARAMETER Setup
        The WSUS setup values (Get-WsusSetupValue).

    .EXAMPLE
        Test-WsusTlsHealth -Setup (Get-WsusSetupValue)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-wsustlshealth',
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
    [AllowNull()]
    [System.Object]
    $Setup
  )

  Write-Debug -Message:'[Test-WsusTlsHealth] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Item = [System.String]::Empty
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [System.String]$Private:Value = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  If ($Null -eq $Setup) {
    Throw $Script:Message['Test-WsusTlsHealth.NoSetup']
  }

  # https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/windows-server-update-services-best-practices
  $Value = [System.String](Get-MaintenancePropertyValue -InputObject:$Setup -Name:'UsingSSL' -Default:'')
  If ($Value -eq '1') {
    $Item = $Script:Message['Test-WsusTlsHealth.InUse']
  } Else {
    $Item = $Script:Message['Test-WsusTlsHealth.NotInUse']
    $Notices.Add((New-MaintenanceNotice -Link:'https://learn.microsoft.com/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus#25-secure-wsus-with-the-secure-sockets-layer-protocol' -Message:($Script:Message['Test-WsusTlsHealth.Notice'] -f $(If ($Value -eq '') { $Script:Message['Test-WsusTlsHealth.Missing'] } Else { $Value })) -Severity:'Warning' -Stage:'HealthChecks'))
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]$Item
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-WsusTlsHealth] Exiting'
}
