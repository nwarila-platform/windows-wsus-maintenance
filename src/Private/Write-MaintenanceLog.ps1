#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Write-MaintenanceLog {
  <#
    .SYNOPSIS
        Appends one entry to the run log.

    .DESCRIPTION
        Writes a single line: the local time with its offset, the level, the run identifier, the stage
        (when there is one) and the message, with line breaks folded so every entry stays on one line
        and carries the run identifier. Entries below the log's verbosity are skipped, and every line
        passes through Protect-MaintenanceText. Writing never stops the run: an entry that cannot be
        written is counted in the log's WriteErrors. Without a usable log nothing is written.

    .PARAMETER Level
        Entry level.

    .PARAMETER Log
        The run log from New-MaintenanceLog, or null.

    .PARAMETER Message
        Entry text.

    .PARAMETER Stage
        Stage the entry belongs to, if any.

    .EXAMPLE
        Write-MaintenanceLog -Log $Log -Level 'Information' -Stage 'Reindex' -Message 'Stage started.'

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#write-maintenancelog',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [System.String]
    $Level,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Log,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Message,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Stage = ''
  )

  Write-Debug -Message:'[Write-MaintenanceLog] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Flat = [System.String]::Empty
  [System.Collections.Hashtable]$Private:Levels = @{ Error = 1; Warning = 2; Information = 3; Verbose = 4; Debug = 5 }
  [System.String]$Private:Line = [System.String]::Empty
  [System.String]$Private:Prefix = [System.String]::Empty

  If (($Null -ne $Log) -and ([System.String]::IsNullOrEmpty($Log.Path) -eq $False) -and ($Levels[$Level] -le $Log.Threshold)) {
    If ([System.String]::IsNullOrEmpty($Stage) -eq $False) {
      $Prefix = '{0}: ' -f $Stage
    }

    $Flat = [System.Text.RegularExpressions.Regex]::Replace($Message, '\r\n|\r|\n', ' / ')
    $Line = Protect-MaintenanceText -Text:('{0} {1} [{2}] {3}{4}' -f (Get-MaintenanceTime).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz', [System.Globalization.CultureInfo]::InvariantCulture), $Level.PadRight(11), $Log.RunId, $Prefix, $Flat)

    Try {
      [System.IO.File]::AppendAllText($Log.Path, ($Line + "`r`n"), [System.Text.UTF8Encoding]::new($False))
    } Catch {
      $Log.WriteErrors = $Log.WriteErrors + 1
    }
  }

  Write-Debug -Message:'[Write-MaintenanceLog] Exiting'
}
