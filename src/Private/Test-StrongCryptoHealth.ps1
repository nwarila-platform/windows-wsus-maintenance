#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-StrongCryptoHealth.Absent' = 'absent'
  'Test-StrongCryptoHealth.NotSet' = 'strong cryptography: {0} value(s) not set'
  'Test-StrongCryptoHealth.Notice' = 'The .NET Framework strong-cryptography values are not all set to 1: {0}.'
  'Test-StrongCryptoHealth.Set'    = 'strong cryptography: set in both registry views'
  'Test-StrongCryptoHealth.Value'  = '{0} ({1}) is {2}'
}

Function Test-StrongCryptoHealth {
  <#
    .SYNOPSIS
        Checks the .NET Framework strong-cryptography registry values in both registry views.

    .DESCRIPTION
        Reads SchUseStrongCrypto and SystemDefaultTlsVersions under
        SOFTWARE\Microsoft\.NETFramework\v4.0.30319 in the 64-bit and the 32-bit registry views, which
        Microsoft's TLS guidance for the .NET Framework sets to 1, and raises one Warning notice listing
        every value that is missing or not 1.

    .EXAMPLE
        Test-StrongCryptoHealth

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-strongcryptohealth',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param ()

  Write-Debug -Message:'[Test-StrongCryptoHealth] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Item = [System.String]::Empty
  [PSCustomObject]$Private:Key = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [System.Object]$Private:Value = $Null
  [System.Collections.Generic.List[System.String]]$Private:Wrong = $Null
  [PSCustomObject]$Private:Result = $Null

  # https://learn.microsoft.com/dotnet/framework/network-programming/tls
  $Wrong = [System.Collections.Generic.List[System.String]]::new()
  ForEach ($View In @('Registry64', 'Registry32')) {
    $Key = Get-MaintenanceRegistryKey -Path:'SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -View:$View
    ForEach ($Name In @('SchUseStrongCrypto', 'SystemDefaultTlsVersions')) {
      $Value = $Null
      If ($Null -ne $Key) {
        $Value = $Key.Values[$Name]
      }

      If ([System.String]$Value -ne '1') {
        $Wrong.Add(($Script:Message['Test-StrongCryptoHealth.Value'] -f $Name, $View, $(If ($Null -eq $Value) { $Script:Message['Test-StrongCryptoHealth.Absent'] } Else { $Value })))
      }
    }
  }

  If ($Wrong.Count -eq 0) {
    $Item = $Script:Message['Test-StrongCryptoHealth.Set']
  } Else {
    $Item = $Script:Message['Test-StrongCryptoHealth.NotSet'] -f $Wrong.Count
    $Notices.Add((New-MaintenanceNotice -Link:'https://learn.microsoft.com/dotnet/framework/network-programming/tls' -Message:($Script:Message['Test-StrongCryptoHealth.Notice'] -f ($Wrong -join '; ')) -Severity:'Warning' -Stage:'HealthChecks'))
  }
  [PSCustomObject]$Result = [PSCustomObject]@{
    Item    = [System.String]$Item
    Notices = [PSCustomObject[]]$Notices.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-StrongCryptoHealth] Exiting'
}
