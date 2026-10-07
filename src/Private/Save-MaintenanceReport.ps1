#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Save-MaintenanceReport.Failed' = "The report file '{0}' could not be written: {1}"
}

Function Save-MaintenanceReport {
  <#
    .SYNOPSIS
        Saves the rendered report files of one run.

    .DESCRIPTION
        Writes one file per configured format into the report folder, named after the run identifier
        (WsusMaintenance-<run identifier>.txt and .html). The content is written as given:
        New-MaintenanceReport has already passed every text in it through
        Protect-MaintenanceText. A folder that Resolve-MaintenanceOutputFolder could not
        make usable arrives empty, and nothing is written. A file that cannot be written is reported
        in Errors; the run carries on.

    .PARAMETER Folder
        Ready report folder, or empty when none is usable.

    .PARAMETER Format
        Formats to save: Text, Html.

    .PARAMETER Html
        HTML rendering.

    .PARAMETER RunId
        Run identifier.

    .PARAMETER Text
        Plain-text rendering.

    .EXAMPLE
        Save-MaintenanceReport -Folder $Output.ReportFolder -Format @('Text', 'Html') -Text $Text -Html $Html -RunId $RunId

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#save-maintenancereport',
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
    [AllowEmptyString()]
    [System.String]
    $Folder,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Format,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Html,

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
    [AllowEmptyString()]
    [System.String]
    $Text
  )

  Write-Debug -Message:'[Save-MaintenanceReport] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Content = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.String]$Private:Path = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Paths = $Null
  [PSCustomObject]$Private:Result = $Null

  $Paths = [System.Collections.Generic.List[System.String]]::new()
  $Errors = [System.Collections.Generic.List[System.String]]::new()

  If ([System.String]::IsNullOrEmpty($Folder) -eq $False) {
    ForEach ($Name In @($Format)) {
      If ($Name -eq 'Html') {
        $Path = [System.IO.Path]::Combine($Folder, ('WsusMaintenance-{0}.html' -f $RunId))
        $Content = $Html
      } Else {
        $Path = [System.IO.Path]::Combine($Folder, ('WsusMaintenance-{0}.txt' -f $RunId))
        $Content = $Text
      }

      Try {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($False))
        $Paths.Add($Path)
      } Catch {
        $Errors.Add(($Script:Message['Save-MaintenanceReport.Failed'] -f $Path, $PSItem.Exception.GetBaseException().Message))
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Paths  = [System.String[]]$Paths.ToArray()
    Errors = [System.String[]]$Errors.ToArray()
  }

  $Result
  Write-Debug -Message:'[Save-MaintenanceReport] Exiting'
}
