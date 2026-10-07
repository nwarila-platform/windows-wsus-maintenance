#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenancePathValue.Path' = '{0}: must be an absolute Windows path (drive, UNC, or one leading %VARIABLE%) without wildcards or .. segments (got {1}).'
}

Function Test-MaintenancePathValue {
  <#
    .SYNOPSIS
        Validates one folder-path configuration value.

    .DESCRIPTION
        A path must be absolute: drive-rooted (E:\Backups), UNC (\\server\share\folder),
        or rooted at one environment variable that is expanded at run time
        (%ProgramData%\NWarila). Wildcards, invalid file-name characters and .. segments
        are refused, because several stages delete files beneath these folders.

    .PARAMETER Path
        Location of the value in the document, used in messages.

    .PARAMETER Pattern
        Regular expression an acceptable path must match (the catalogue's path pattern).

    .PARAMETER Value
        The value to validate.

    .EXAMPLE
        Test-MaintenancePathValue -Path 'backup.destination' -Pattern $Rule.Pattern -Value 'H:\SUSDB'

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancepathvalue',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
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
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Pattern,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Value
  )

  Write-Debug -Message:'[Test-MaintenancePathValue] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.String[]]$Private:Result = @()

  $Errors = [System.Collections.Generic.List[System.String]]::new()

  If (
    (($Value -is [System.String]) -eq $False) -or
    ($Value -notmatch $Pattern) -or
    ($Value -match '(^|\\)\.\.(\\|$)')
  ) {
    $Errors.Add(($Script:Message['Test-MaintenancePathValue.Path'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenancePathValue] Exiting'
}
