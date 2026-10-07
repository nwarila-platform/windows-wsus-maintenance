#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-BackupDestinationSpace {
  <#
    .SYNOPSIS
        Returns the free space of the volume holding the backup folder.

    .DESCRIPTION
        A seam around System.IO.DriveInfo, so that tests can replace it. Returns the free bytes
        available to the caller on the volume of the given path. Throws when the free space cannot be
        read, for example for a UNC path.

    .PARAMETER Path
        Backup folder, already expanded.

    .EXAMPLE
        Get-BackupDestinationSpace -Path 'H:\SUSDB'

    .OUTPUTS
        [System.Int64]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-backupdestinationspace',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Int64])]
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

  Write-Debug -Message:'[Get-BackupDestinationSpace] Entering'

  # Initialize Variable(s)
  [System.Int64]$Private:Result = 0

  [System.Int64]$Result = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($Path)).AvailableFreeSpace

  $Result
  Write-Debug -Message:'[Get-BackupDestinationSpace] Exiting'
}
