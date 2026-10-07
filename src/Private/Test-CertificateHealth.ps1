#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-CertificateHealth.Expired'       = 'The certificate {0} bound to {1} expired on {2}. Clients can no longer reach WSUS over TLS.'
  'Test-CertificateHealth.Expiring'      = 'The certificate {0} bound to {1} expires in {2} day(s), on {3} (within the {4}-day warning tier). Renew it.'
  'Test-CertificateHealth.Item'          = 'certificate on {0}: {1}, expires {2} ({3} day(s))'
  'Test-CertificateHealth.Missing'       = 'The certificate {0} bound to {1} is not in the local-machine store {2}.'
  'Test-CertificateHealth.MissingItem'   = 'certificate on {0}: not in its store'
  'Test-CertificateHealth.NoBinding'     = 'No certificate is bound in HTTP.sys to port {0}, which the WSUS website uses for https.'
  'Test-CertificateHealth.NoBindingItem' = 'certificate on port {0}: none bound'
  'Test-CertificateHealth.NoHttps'       = 'certificate: the WSUS website has no https binding'
}

Function Test-CertificateHealth {
  <#
    .SYNOPSIS
        Checks the expiry of the certificate bound to each WSUS TLS port.

    .DESCRIPTION
        For each https port of the WSUS website, reads the certificate HTTP.sys binds to it (the
        SslBindingInfo and SslSniBindingInfo registrations), finds the certificate in its local-machine
        store and counts the days until it expires. An expired certificate raises an Error notice, one
        within the smallest warning tier a High notice, and one within another tier a Warning notice
        naming the tier; a port without a bound certificate, or a bound certificate missing from its
        store, raises a Warning notice. Without an https binding the check reports nothing, because the
        TLS check covers it.

    .PARAMETER Now
        The current time in UTC.

    .PARAMETER Port
        Ports of the https bindings of the WSUS website.

    .PARAMETER WarningDays
        Warning tiers in days, strictly descending.

    .EXAMPLE
        Test-CertificateHealth -Now ([System.DateTime]::UtcNow) -Port @(8531) -WarningDays @(60, 30, 14, 7)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-certificatehealth',
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
    [System.DateTime]
    $Now,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.Int32[]]
    $Port,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNull()]
    [System.Int32[]]
    $WarningDays
  )

  Write-Debug -Message:'[Test-CertificateHealth] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Binding = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Bindings = $Null
  [PSCustomObject]$Private:Certificate = $Null
  [System.Int32]$Private:Days = 0
  [System.String]$Private:Expiry = [System.String]::Empty
  [PSCustomObject]$Private:Key = $Null
  [System.Collections.Generic.List[System.String]]$Private:Lines = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [System.Int32]$Private:Smallest = 0
  [System.Int32]$Private:Tier = 0
  [PSCustomObject]$Private:Result = $Null

  $Lines = [System.Collections.Generic.List[System.String]]::new()
  $Smallest = [System.Int32](@($WarningDays | Sort-Object)[0])
  ForEach ($Each In $Port) {
    $Bindings = [System.Collections.Generic.List[PSCustomObject]]::new()
    ForEach ($Root In @('SYSTEM\CurrentControlSet\Services\HTTP\Parameters\SslBindingInfo', 'SYSTEM\CurrentControlSet\Services\HTTP\Parameters\SslSniBindingInfo')) {
      $Key = Get-MaintenanceRegistryKey -Path:$Root
      ForEach ($Name In @(Get-MaintenancePropertyValue -InputObject:$Key -Name:'SubKeys' -Default:@())) {
        If ([System.String]$Name -like ('*:{0}' -f $Each)) {
          $Binding = Get-MaintenanceRegistryKey -Path:('{0}\{1}' -f $Root, $Name)
          If (($Null -ne $Binding) -and ($Binding.Values['SslCertHash'] -is [System.Byte[]])) {
            $Bindings.Add([PSCustomObject]@{ Name = [System.String]$Name; Thumbprint = [System.BitConverter]::ToString($Binding.Values['SslCertHash']).Replace('-', ''); Store = [System.String]$(If ([System.String]::IsNullOrEmpty([System.String]$Binding.Values['SslCertStoreName']) -eq $True) { 'My' } Else { $Binding.Values['SslCertStoreName'] }) })
          }
        }
      }
    }

    If ($Bindings.Count -eq 0) {
      $Lines.Add(($Script:Message['Test-CertificateHealth.NoBindingItem'] -f $Each))
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-CertificateHealth.NoBinding'] -f $Each) -Severity:'Warning' -Stage:'HealthChecks'))
      Continue
    }

    ForEach ($Binding In $Bindings) {
      $Certificate = Get-MaintenanceCertificate -StoreName:$Binding.Store -Thumbprint:$Binding.Thumbprint
      If ($Null -eq $Certificate) {
        $Lines.Add(($Script:Message['Test-CertificateHealth.MissingItem'] -f $Binding.Name))
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-CertificateHealth.Missing'] -f $Binding.Thumbprint, $Binding.Name, $Binding.Store) -Severity:'Warning' -Stage:'HealthChecks'))
        Continue
      }

      $Days = [System.Int32][System.Math]::Floor(($Certificate.NotAfter - $Now).TotalDays)
      $Expiry = $Certificate.NotAfter.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
      $Lines.Add(($Script:Message['Test-CertificateHealth.Item'] -f $Binding.Name, $Certificate.Subject, $Expiry, $Days))
      If ($Days -lt 0) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-CertificateHealth.Expired'] -f $Certificate.Subject, $Binding.Name, $Expiry) -Severity:'Error' -Stage:'HealthChecks'))
      } ElseIf ($Days -le $Smallest) {
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-CertificateHealth.Expiring'] -f $Certificate.Subject, $Binding.Name, $Days, $Expiry, $Smallest) -Severity:'High' -Stage:'HealthChecks'))
      } Else {
        $Tier = 0
        ForEach ($Limit In $WarningDays) {
          If ($Days -le $Limit) {
            $Tier = $Limit
          }
        }

        If ($Tier -gt 0) {
          $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Test-CertificateHealth.Expiring'] -f $Certificate.Subject, $Binding.Name, $Days, $Expiry, $Tier) -Severity:'Warning' -Stage:'HealthChecks'))
        }
      }
    }
  }

  If ($Lines.Count -eq 0) {
    $Lines.Add($Script:Message['Test-CertificateHealth.NoHttps'])
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]($Lines -join '; ')
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-CertificateHealth] Exiting'
}
