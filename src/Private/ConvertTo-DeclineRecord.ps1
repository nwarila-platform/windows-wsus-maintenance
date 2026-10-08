#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-DeclineRecord {
  <#
    .SYNOPSIS
        Reads the attributes the decline policies use from one update.

    .DESCRIPTION
        Copies the attributes of an IUpdate that the decline policies, the rules, the approval stages
        and the report use into a plain record: the update identifier and revision number, title,
        legacy name, Knowledge Base article numbers (without a KB prefix), product and product family
        titles, classification title, update source, revision creation and arrival dates, the
        superseded, supersedes-others, approved, declined and expired states, and the update itself
        for the decline and approval calls. Reading every attribute once, while the evaluation
        language is in effect, keeps later evaluation independent of the connection.

    .PARAMETER Update
        The update (IUpdate).

    .EXAMPLE
        ConvertTo-DeclineRecord -Update $Update

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-declinerecord',
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
    [System.Object]
    $Update
  )

  Write-Debug -Message:'[ConvertTo-DeclineRecord] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Articles = [System.Collections.Generic.List[System.String]]::new()
  [PSCustomObject]$Private:Result = $Null

  ForEach ($Article In @($Update.KnowledgebaseArticles)) {
    If ([System.String]::IsNullOrWhiteSpace([System.String]$Article) -eq $False) {
      $Articles.Add(([System.String]$Article -replace '(?i)^\s*KB', '').Trim())
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Id                    = [System.String]$Update.Id.UpdateId
    Revision              = [System.Int32]$Update.Id.RevisionNumber
    Title                 = [System.String]$Update.Title
    LegacyName            = [System.String]$Update.LegacyName
    KnowledgeBaseArticles = [System.String[]]$Articles.ToArray()
    ProductTitles         = [System.String[]]@($Update.ProductTitles | Where-Object -FilterScript:({ $Null -ne $PSItem }))
    ProductFamilyTitles   = [System.String[]]@($Update.ProductFamilyTitles | Where-Object -FilterScript:({ $Null -ne $PSItem }))
    ClassificationTitle   = [System.String]$Update.UpdateClassificationTitle
    UpdateSource          = [System.String]$Update.UpdateSource
    CreationDate          = [System.DateTime]$Update.CreationDate
    ArrivalDate           = [System.DateTime]$Update.ArrivalDate
    IsSuperseded          = [System.Boolean]$Update.IsSuperseded
    SupersedesOthers      = [System.Boolean]$Update.HasSupersededUpdates
    IsApproved            = [System.Boolean]$Update.IsApproved
    IsDeclined            = [System.Boolean]$Update.IsDeclined
    IsExpired             = [System.Boolean]([System.String]$Update.PublicationState -eq 'Expired')
    Update                = $Update
  }

  $Result
  Write-Debug -Message:'[ConvertTo-DeclineRecord] Exiting'
}
