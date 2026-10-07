#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Initialize-MaintenanceFolder.NotRooted' = "'{0}' is not an absolute path on this host."
}

Function Initialize-MaintenanceFolder {
  <#
    .SYNOPSIS
        Makes sure a folder exists and can be written.

    .DESCRIPTION
        Expands environment variables in the path, creates the folder if it is missing, and writes and
        deletes a probe file to prove that the run identity can write to it. A path that is not
        absolute on this host (for example a Windows path on another platform, or an unexpanded
        variable) is refused without touching the file system. Returns the expanded path and the
        reason the folder cannot be used, which is empty when it can.

    .PARAMETER Path
        Configured folder; may start with one %VARIABLE%.

    .EXAMPLE
        Initialize-MaintenanceFolder -Path '%ProgramData%\NWarila\WsusMaintenance\Logs'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#initialize-maintenancefolder',
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

  Write-Debug -Message:'[Initialize-MaintenanceFolder] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.String]$Private:Probe = [System.String]::Empty
  [System.String]$Private:Resolved = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Resolved = Resolve-MaintenancePath -Path:$Path

  If ([System.IO.Path]::IsPathRooted($Resolved) -eq $False) {
    $ErrorText = $Script:Message['Initialize-MaintenanceFolder.NotRooted'] -f $Resolved
  } Else {
    Try {
      $Null = [System.IO.Directory]::CreateDirectory($Resolved)
      # A probe file proves the folder can be written, not just that it exists.
      $Probe = [System.IO.Path]::Combine($Resolved, ('.write-probe-{0}' -f [System.Guid]::NewGuid().ToString('N')))
      [System.IO.File]::WriteAllText($Probe, [System.String]::Empty)
      [System.IO.File]::Delete($Probe)
    } Catch {
      $ErrorText = $PSItem.Exception.GetBaseException().Message
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path  = [System.String]$Resolved
    Error = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Initialize-MaintenanceFolder] Exiting'
}
