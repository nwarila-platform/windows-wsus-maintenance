#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'New-DeclineUnavailableResult.Notice'  = 'The update list could not be retrieved, so no decline policy acted in this run: {0} A common cause is memory exhaustion of the WsusPool application pool in IIS. The other stages still run.'
  'New-DeclineUnavailableResult.Summary' = 'no declines were made: the update list could not be retrieved ({0})'
}

Function New-DeclineUnavailableResult {
  <#
    .SYNOPSIS
        Builds the result of a decline policy that could not act because the update list was missing.

    .DESCRIPTION
        When the update list could not be retrieved, no decline policy acts. The first decline stage of
        the run raises one Error notice that says so and names memory exhaustion of the WSUS application
        pool in IIS as a common cause; every decline stage ends in error with zero declines, and the other
        stages still run.

    .PARAMETER Catalog
        The decline catalog of the run (Get-DeclineCatalog).

    .PARAMETER Stage
        Name of the decline stage.

    .EXAMPLE
        New-DeclineUnavailableResult -Catalog $Catalog -Stage 'SupersededDecline'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-declineunavailableresult',
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
    [ValidateNotNull()]
    [PSCustomObject]
    $Catalog,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Stage
  )

  Write-Debug -Message:'[New-DeclineUnavailableResult] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [PSCustomObject]$Private:Result = $Null

  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  If ($Catalog.ErrorReported -eq $False) {
    $Catalog.ErrorReported = $True
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['New-DeclineUnavailableResult.Notice'] -f $Catalog.Error) -Severity:'Error' -Stage:$Stage))
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Message:($Script:Message['New-DeclineUnavailableResult.Summary'] -f $Catalog.Error) -Notice:$Notices.ToArray() -Status:'Error'

  $Result
  Write-Debug -Message:'[New-DeclineUnavailableResult] Exiting'
}
