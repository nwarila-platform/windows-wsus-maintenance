#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-MaintenanceInstallation {
  <#
    .SYNOPSIS
        Checks that nobody but the trusted principals can change the running script.

    .DESCRIPTION
        Examines the folder that holds the running script (Get-MaintenanceScriptPath) and the script
        file itself with Test-MaintenancePathProtection, trusting SYSTEM, Administrators and the run
        identity. The run does not execute code from a location that other principals can change, so a
        writer found here stops the run; there is no override. Returns the script path, whether it is
        safe, the writers found and the reason the check could not be made, which is empty when it
        could.

    .EXAMPLE
        Test-MaintenanceInstallation

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceinstallation',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param ()

  Write-Debug -Message:'[Test-MaintenanceInstallation] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.String]$Private:ScriptPath = [System.String]::Empty
  [System.String[]]$Private:Trusted = @()
  [System.Collections.Generic.List[System.String]]$Private:Writers = $Null
  [PSCustomObject]$Private:Result = $Null

  $Writers = [System.Collections.Generic.List[System.String]]::new()
  $ScriptPath = Get-MaintenanceScriptPath
  Try {
    $Trusted = Get-MaintenanceTrustedSid
    ForEach ($Target In @([System.IO.Path]::GetDirectoryName($ScriptPath), $ScriptPath)) {
      ForEach ($Writer In (Test-MaintenancePathProtection -Path:$Target -TrustedSid:$Trusted).Writers) {
        If ($Writers.Contains($Writer) -eq $False) {
          $Writers.Add($Writer)
        }
      }
    }
  } Catch {
    $ErrorText = $PSItem.Exception.GetBaseException().Message
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path    = [System.String]$ScriptPath
    Safe    = [System.Boolean](($Writers.Count -eq 0) -and ([System.String]::IsNullOrEmpty($ErrorText) -eq $True))
    Writers = [System.String[]]$Writers.ToArray()
    Error   = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Test-MaintenanceInstallation] Exiting'
}
