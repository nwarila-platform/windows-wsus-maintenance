#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'New-MaintenanceLog.Unwritable' = "The log folder '{0}' cannot be written: {1}"
}

Function New-MaintenanceLog {
  <#
    .SYNOPSIS
        Creates the run log file.

    .DESCRIPTION
        Makes sure the log folder can be written and creates the run's log file, named after the run
        identifier. The returned log carries the path, the run identifier, the verbosity threshold and
        a count of entries that could not be written. When the folder or the file cannot be written,
        Path is empty and Error explains why; the caller then aborts the run with the
        precondition-failure code, as a run without a log must not change anything.

    .PARAMETER Folder
        Configured log folder.

    .PARAMETER RunId
        Run identifier.

    .PARAMETER Verbosity
        Lowest level written.

    .EXAMPLE
        New-MaintenanceLog -Folder $Setting.LogFolder -RunId $RunId -Verbosity 'Information'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancelog',
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
    $Folder,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $RunId,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [System.String]
    $Verbosity
  )

  Write-Debug -Message:'[New-MaintenanceLog] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Collections.Hashtable]$Private:Levels = @{ Error = 1; Warning = 2; Information = 3; Verbose = 4; Debug = 5 }
  [System.String]$Private:Path = [System.String]::Empty
  [PSCustomObject]$Private:Ready = $Null
  [PSCustomObject]$Private:Result = $Null

  $Ready = Initialize-MaintenanceFolder -Path:$Folder

  If ([System.String]::IsNullOrEmpty($Ready.Error) -eq $True) {
    Try {
      $Path = [System.IO.Path]::Combine($Ready.Path, ('WsusMaintenance-{0}.log' -f $RunId))
      [System.IO.File]::WriteAllText($Path, [System.String]::Empty, [System.Text.UTF8Encoding]::new($False))
    } Catch {
      $Path = [System.String]::Empty
      $ErrorText = $Script:Message['New-MaintenanceLog.Unwritable'] -f $Ready.Path, $PSItem.Exception.GetBaseException().Message
    }
  } Else {
    $ErrorText = $Script:Message['New-MaintenanceLog.Unwritable'] -f $Ready.Path, $Ready.Error
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path        = [System.String]$Path
    RunId       = [System.String]$RunId
    Verbosity   = [System.String]$Verbosity
    Threshold   = [System.Int32]$Levels[$Verbosity]
    WriteErrors = [System.Int32]0
    Error       = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[New-MaintenanceLog] Exiting'
}
