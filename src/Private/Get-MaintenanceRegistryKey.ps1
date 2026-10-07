#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceRegistryKey {
  <#
    .SYNOPSIS
        Reads one registry key under HKEY_LOCAL_MACHINE in a given registry view.

    .DESCRIPTION
        A seam around Microsoft.Win32.RegistryKey, so that tests can replace it. Opens the key read-only
        in the 64-bit or 32-bit registry view and returns the names of its subkeys and its values, or null
        when the key does not exist. Nothing is written.

    .PARAMETER Path
        Key path under HKEY_LOCAL_MACHINE.

    .PARAMETER View
        Registry view.

    .EXAMPLE
        Get-MaintenanceRegistryKey -Path 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -View 'Registry32'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenanceregistrykey',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Path,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Registry64', 'Registry32')]
    [System.String]
    $View = 'Registry64'
  )

  Write-Debug -Message:'[Get-MaintenanceRegistryKey] Entering'

  # Initialize Variable(s)
  [Microsoft.Win32.RegistryKey]$Private:Base = $Null
  [Microsoft.Win32.RegistryKey]$Private:Key = $Null
  [System.Collections.Hashtable]$Private:Values = $Null
  [PSCustomObject]$Private:Result = $Null

  $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]$View)
  Try {
    $Key = $Base.OpenSubKey($Path, $False)
    If ($Null -ne $Key) {
      Try {
        $Values = @{}
        ForEach ($Name In $Key.GetValueNames()) {
          $Values[$Name] = $Key.GetValue($Name)
        }

        [PSCustomObject]$Result = [PSCustomObject]@{
          SubKeys = [System.String[]]$Key.GetSubKeyNames()
          Values  = $Values
        }
      } Finally {
        $Key.Dispose()
      }
    }
  } Finally {
    $Base.Dispose()
  }

  $Result
  Write-Debug -Message:'[Get-MaintenanceRegistryKey] Exiting'
}
