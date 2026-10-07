#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'ConvertTo-StaleComputerText.Never' = 'never'
  'ConvertTo-StaleComputerText.Text'  = '{0} (last synchronized {1}, {2}, client {3})'
  'ConvertTo-StaleComputerText.Utc'   = '{0} UTC'
}

Function ConvertTo-StaleComputerText {
  <#
    .SYNOPSIS
        Describes a client computer for the stale-computer list.

    .DESCRIPTION
        Gives the fully qualified name, the last synchronization time in UTC (or "never"), the
        operating-system description and the client agent version of an IComputerTarget.

    .PARAMETER Computer
        The computer (IComputerTarget).

    .EXAMPLE
        ConvertTo-StaleComputerText -Computer $Computer

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-stalecomputertext',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
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
    $Computer
  )

  Write-Debug -Message:'[ConvertTo-StaleComputerText] Entering'

  # Initialize Variable(s)
  [System.String]$Private:LastSync = [System.String]::Empty
  [System.String]$Private:Result = [System.String]::Empty

  $LastSync = $Script:Message['ConvertTo-StaleComputerText.Never']
  If (($Computer.LastSyncTime -is [System.DateTime]) -and ($Computer.LastSyncTime -gt [System.DateTime]::MinValue)) {
    $LastSync = $Script:Message['ConvertTo-StaleComputerText.Utc'] -f $Computer.LastSyncTime.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
  }

  [System.String]$Result = $Script:Message['ConvertTo-StaleComputerText.Text'] -f $Computer.FullDomainName, $LastSync, $Computer.OSDescription, $Computer.ClientVersion

  $Result
  Write-Debug -Message:'[ConvertTo-StaleComputerText] Exiting'
}
