#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-DeclineCatalog {
  <#
    .SYNOPSIS
        Returns the undeclined updates every decline policy of the run evaluates.

    .DESCRIPTION
        Retrieves the updates that are not declined once per run (Get-WsusUpdateRecord) and keeps them
        with the server facts of the run, so that every decline policy evaluates the same list and the
        update list is read from WSUS only once. The catalog also records which updates the run has
        already declined (or, in a dry run, would decline), so that a later policy does not count them
        again, and whether the retrieval failure has been reported.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Get-DeclineCatalog -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-declinecatalog',
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
    $Context
  )

  Write-Debug -Message:'[Get-DeclineCatalog] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Retrieval = $Null
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'DeclineCatalog' -Default:$Null
  If ($Null -eq $Result) {
    $Retrieval = Get-WsusUpdateRecord -Context:$Context
    [PSCustomObject]$Result = [PSCustomObject]@{
      Records       = $Retrieval.Records
      Claimed       = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
      Error         = $Retrieval.Error
      LanguageError = $Retrieval.LanguageError
      Language      = $Retrieval.Language
      ErrorReported = $False
    }
    $Context.Server | Add-Member -Force -MemberType:'NoteProperty' -Name:'DeclineCatalog' -Value:$Result
  }

  $Result
  Write-Debug -Message:'[Get-DeclineCatalog] Exiting'
}
