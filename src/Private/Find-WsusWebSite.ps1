#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Find-WsusWebSite.Ambiguous'     = 'the WSUS website is ambiguous ({0}): {1}'
  'Find-WsusWebSite.ByApplication' = 'by the site that hosts /ApiRemoting30'
  'Find-WsusWebSite.ByDefault'     = 'by the default name WSUS Administration'
  'Find-WsusWebSite.ByName'        = 'by iisLogs.siteName'
  'Find-WsusWebSite.ByPath'        = 'by the WSUS installation path'
  'Find-WsusWebSite.Fallback'      = 'The WSUS website was found by its default name only: neither the WSUS installation path nor the remote-administration application matched a site. Set iisLogs.siteName if this is not the WSUS site.'
  'Find-WsusWebSite.NotFound'      = 'the WSUS website was not found ({0})'
}

Function Find-WsusWebSite {
  <#
    .SYNOPSIS
        Identifies the IIS website that hosts WSUS, whatever its name.

    .DESCRIPTION
        Finds the WSUS website in the IIS configuration without relying on its display name: an
        explicit iisLogs.siteName wins; otherwise the site whose root physical path lies under the WSUS
        installation folder WSUS setup recorded (TargetDir); otherwise the site that hosts the WSUS
        remote-administration application (/ApiRemoting30); otherwise the default name WSUS
        Administration, with a warning. More than one match is ambiguous and is an error. Returns the
        site's name, identifier, how it was found, the folder of its IIS log files (its own log
        directory, or the site defaults, plus W3SVC and the site identifier), the application pool of
        its root application, and the ports of its https bindings.

    .PARAMETER Iis
        The IIS configuration (Get-IisConfiguration).

    .PARAMETER Setup
        The WSUS setup values (Get-WsusSetupValue).

    .PARAMETER SiteName
        Explicit site name, or empty to detect it.

    .EXAMPLE
        Find-WsusWebSite -Iis (Get-IisConfiguration) -Setup (Get-WsusSetupValue)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#find-wsuswebsite',
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
    [System.Xml.XmlDocument]
    $Iis,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Setup = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $SiteName = ''
  )

  Write-Debug -Message:'[Find-WsusWebSite] Entering'

  # Initialize Variable(s)
  [System.Xml.XmlNode]$Private:Directory = $Null
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Collections.Generic.List[System.Xml.XmlElement]]$Private:Found = $Null
  [System.String]$Private:Id = [System.String]::Empty
  [System.String]$Private:LogDirectory = [System.String]::Empty
  [System.String]$Private:LogFolder = [System.String]::Empty
  [System.String]$Private:Method = [System.String]::Empty
  [System.String]$Private:Name = [System.String]::Empty
  [System.Xml.XmlNode]$Private:Node = $Null
  [System.String[]]$Private:Parts = @()
  [System.String]$Private:Pool = 'WsusPool'
  [System.Collections.Generic.List[System.Int32]]$Private:Ports = [System.Collections.Generic.List[System.Int32]]::new()
  [System.String]$Private:Root = [System.String]::Empty
  [System.Xml.XmlElement]$Private:Site = $Null
  [System.Object[]]$Private:Sites = @()
  [System.String]$Private:TargetDir = [System.String]::Empty
  [System.String]$Private:Warning = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Sites = @($Iis.SelectNodes('/configuration/system.applicationHost/sites/site'))
  $TargetDir = [System.String](Get-MaintenancePropertyValue -InputObject:$Setup -Name:'TargetDir' -Default:'')
  $Found = [System.Collections.Generic.List[System.Xml.XmlElement]]::new()

  If ([System.String]::IsNullOrEmpty($SiteName) -eq $False) {
    $Method = $Script:Message['Find-WsusWebSite.ByName']
    ForEach ($Site In $Sites) {
      If ([System.String]::Equals($Site.GetAttribute('name'), $SiteName, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
        $Found.Add($Site)
      }
    }
  } Else {
    If ([System.String]::IsNullOrEmpty($TargetDir) -eq $False) {
      $Method = $Script:Message['Find-WsusWebSite.ByPath']
      $Root = [System.Environment]::ExpandEnvironmentVariables($TargetDir).TrimEnd('\') + '\'
      ForEach ($Site In $Sites) {
        $Directory = $Site.SelectSingleNode("application[@path='/']/virtualDirectory[@path='/']")
        If (($Null -ne $Directory) -and ([System.Environment]::ExpandEnvironmentVariables($Directory.GetAttribute('physicalPath')).TrimEnd('\') + '\').StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
          $Found.Add($Site)
        }
      }
    }

    If ($Found.Count -eq 0) {
      $Method = $Script:Message['Find-WsusWebSite.ByApplication']
      ForEach ($Site In $Sites) {
        If ($Null -ne $Site.SelectSingleNode("application[translate(@path, 'APIREMOTING', 'apiremoting')='/apiremoting30']")) {
          $Found.Add($Site)
        }
      }
    }

    If ($Found.Count -eq 0) {
      $Method = $Script:Message['Find-WsusWebSite.ByDefault']
      $Warning = $Script:Message['Find-WsusWebSite.Fallback']
      ForEach ($Site In $Sites) {
        If ([System.String]::Equals($Site.GetAttribute('name'), 'WSUS Administration', [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
          $Found.Add($Site)
        }
      }
    }
  }

  If ($Found.Count -eq 0) {
    $ErrorText = $Script:Message['Find-WsusWebSite.NotFound'] -f $Method
  } ElseIf ($Found.Count -gt 1) {
    $ErrorText = $Script:Message['Find-WsusWebSite.Ambiguous'] -f $Method, (@($Found | ForEach-Object -Process:({ $PSItem.GetAttribute('name') })) -join ', ')
  } Else {
    $Site = $Found[0]
    $Name = $Site.GetAttribute('name')
    $Id = $Site.GetAttribute('id')
    $Node = $Site.SelectSingleNode('logFile/@directory')
    If ($Null -ne $Node) {
      $LogDirectory = [System.String]$Node.Value
    }

    If ([System.String]::IsNullOrEmpty($LogDirectory) -eq $True) {
      $Node = $Iis.SelectSingleNode('/configuration/system.applicationHost/sites/siteDefaults/logFile/@directory')
      If ($Null -ne $Node) {
        $LogDirectory = $Node.Value
      } Else {
        $LogDirectory = '%SystemDrive%\inetpub\logs\LogFiles'
      }
    }

    $LogFolder = [System.IO.Path]::Combine([System.Environment]::ExpandEnvironmentVariables($LogDirectory), ('W3SVC{0}' -f $Id))
    $Node = $Site.SelectSingleNode("application[@path='/']/@applicationPool")
    If ($Null -ne $Node) {
      $Pool = $Node.Value
    } Else {
      $Node = $Iis.SelectSingleNode('/configuration/system.applicationHost/applicationDefaults/@applicationPool')
      If ($Null -ne $Node) {
        $Pool = $Node.Value
      }
    }

    ForEach ($Binding In @($Site.SelectNodes("bindings/binding[@protocol='https']"))) {
      $Parts = $Binding.GetAttribute('bindingInformation').Split(':')
      If ($Parts.Count -ge 2) {
        $Ports.Add([System.Int32]$Parts[1])
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Name       = [System.String]$Name
    Id         = [System.String]$Id
    Method     = [System.String]$Method
    LogFolder  = [System.String]$LogFolder
    AppPool    = [System.String]$Pool
    HttpsPorts = [System.Int32[]]$Ports.ToArray()
    Warning    = [System.String]$Warning
    Error      = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Find-WsusWebSite] Exiting'
}
