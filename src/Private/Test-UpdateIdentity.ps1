#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-UpdateIdentity {
  <#
    .SYNOPSIS
        Tells whether an update is named in a list of Knowledge Base numbers and update identifiers.

    .DESCRIPTION
        Matches each entry against the update: an entry in the form of a GUID against the update
        identifier, and any other entry (with or without a KB prefix) against the Knowledge Base article
        numbers. Comparisons ignore case. Used for the never-decline list and the list of declined updates
        that are never deleted.

    .PARAMETER Identity
        Knowledge Base numbers and update GUIDs.

    .PARAMETER Record
        The decline record.

    .EXAMPLE
        Test-UpdateIdentity -Identity @('KB5034441') -Record $Record

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-updateidentity',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Identity,

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

  Write-Debug -Message:'[Test-UpdateIdentity] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Text = [System.String]::Empty
  [System.Boolean]$Private:Result = $False

  ForEach ($Entry In $Identity) {
    $Text = [System.String]$Entry
    If ([System.Text.RegularExpressions.Regex]::IsMatch($Text, '^[0-9A-Fa-f]{8}-') -eq $True) {
      If ([System.String]::Equals($Text, [System.String]$Record.Id, [System.StringComparison]::OrdinalIgnoreCase) -eq $True) {
        $Result = $True
      }
    } ElseIf (@($Record.KnowledgeBaseArticles) -contains ($Text -replace '(?i)^KB', '')) {
      $Result = $True
    }
  }

  [System.Boolean]$Result = $Result

  $Result
  Write-Debug -Message:'[Test-UpdateIdentity] Exiting'
}
