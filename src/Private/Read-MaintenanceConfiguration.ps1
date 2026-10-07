#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Read-MaintenanceConfiguration.Empty'      = "Configuration document '{0}' is empty."
  'Read-MaintenanceConfiguration.Missing'    = "Configuration document '{0}' does not exist."
  'Read-MaintenanceConfiguration.NotJson'    = "Configuration document '{0}' is not valid JSON: {1}"
  'Read-MaintenanceConfiguration.NotObject'  = "Configuration document '{0}' must contain one JSON object at the top level."
  'Read-MaintenanceConfiguration.Unreadable' = "Configuration document '{0}' could not be read: {1}"
}

Function Read-MaintenanceConfiguration {
  <#
    .SYNOPSIS
        Reads and parses the configuration document.

    .DESCRIPTION
        Reads one JSON document and parses it as data. The document is never executed or
        expanded: JSON carries no code, and nothing downstream evaluates its strings. A
        missing, empty, unreadable or malformed document, or one whose top level is not a
        JSON object, is a configuration error.

    .PARAMETER Path
        Path of the configuration document.

    .EXAMPLE
        Read-MaintenanceConfiguration -Path 'C:\ProgramData\NWarila\WsusMaintenance\maintenance.json'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#read-maintenanceconfiguration',
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
    $Path
  )

  Write-Debug -Message:'[Read-MaintenanceConfiguration] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Document = $Null
  [System.String]$Private:DocumentText = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  If ((Test-Path -LiteralPath:$Path -PathType:'Leaf') -eq $False) {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::ObjectNotFound) `
      -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
      -IsFatal `
      -Message:($Script:Message['Read-MaintenanceConfiguration.Missing'] -f $Path) `
      -TargetObject:$Path
  }

  Try {
    $DocumentText = [System.String](Get-Content -LiteralPath:$Path -Raw -Encoding:'UTF8' -ErrorAction:'Stop')
  } Catch {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::ReadError) `
      -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
      -Exception:$PSItem.Exception `
      -IsFatal `
      -Message:($Script:Message['Read-MaintenanceConfiguration.Unreadable'] -f $Path, $PSItem.Exception.Message) `
      -TargetObject:$Path
  }

  If ([System.String]::IsNullOrWhiteSpace($DocumentText) -eq $True) {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::InvalidData) `
      -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
      -IsFatal `
      -Message:($Script:Message['Read-MaintenanceConfiguration.Empty'] -f $Path) `
      -TargetObject:$Path
  }

  Try {
    $Document = ConvertFrom-Json -InputObject:$DocumentText -ErrorAction:'Stop'
  } Catch {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::InvalidData) `
      -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
      -Exception:$PSItem.Exception `
      -IsFatal `
      -Message:($Script:Message['Read-MaintenanceConfiguration.NotJson'] -f $Path, $PSItem.Exception.Message) `
      -TargetObject:$Path
  }

  If (($Document -is [System.Management.Automation.PSCustomObject]) -eq $False) {
    New-ErrorRecord `
      -Category:([System.Management.Automation.ErrorCategory]::InvalidData) `
      -ErrorId:([MaintenanceExitCode]::ConfigurationInvalid) `
      -IsFatal `
      -Message:($Script:Message['Read-MaintenanceConfiguration.NotObject'] -f $Path) `
      -TargetObject:$Path
  }

  [PSCustomObject]$Result = $Document
  $Result
  Write-Debug -Message:'[Read-MaintenanceConfiguration] Exiting'
}
