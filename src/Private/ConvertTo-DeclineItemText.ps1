#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'ConvertTo-DeclineItemText.NoArticle' = 'no Knowledge Base article'
  'ConvertTo-DeclineItemText.Text'      = '{0} ({1}, created {2})'
}

Function ConvertTo-DeclineItemText {
  <#
    .SYNOPSIS
        Describes an update for a decline or deletion list.

    .DESCRIPTION
        Gives the title, the Knowledge Base references and the revision creation date of a decline
        record, for example "2026-01 Cumulative Update (KB5034441, created 2026-01-09)".

    .PARAMETER Record
        The decline record.

    .EXAMPLE
        ConvertTo-DeclineItemText -Record $Record

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-declineitemtext',
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
    [PSCustomObject]
    $Record
  )

  Write-Debug -Message:'[ConvertTo-DeclineItemText] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Articles = [System.String]::Empty
  [System.String]$Private:Result = [System.String]::Empty

  $Articles = $Script:Message['ConvertTo-DeclineItemText.NoArticle']
  If (@($Record.KnowledgeBaseArticles).Count -gt 0) {
    $Articles = (@($Record.KnowledgeBaseArticles) | ForEach-Object -Process:({ 'KB{0}' -f $PSItem })) -join ', '
  }

  [System.String]$Result = $Script:Message['ConvertTo-DeclineItemText.Text'] -f $Record.Title, $Articles, $Record.CreationDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

  $Result
  Write-Debug -Message:'[ConvertTo-DeclineItemText] Exiting'
}
