#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-SqlIdentifier {
  <#
    .SYNOPSIS
        Quotes a name as a SQL Server identifier.

    .DESCRIPTION
        Encloses the name in square brackets and doubles any closing bracket inside it, as QUOTENAME
        does, so a name can be placed in a statement where SQL Server does not accept a parameter (an
        index, table or database name). Names reaching this function have already been validated.

    .PARAMETER Name
        Name to quote.

    .EXAMPLE
        ConvertTo-SqlIdentifier -Name 'tbRevisionSupersedesUpdate'

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-sqlidentifier',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Name
  )

  Write-Debug -Message:'[ConvertTo-SqlIdentifier] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = '[{0}]' -f $Name.Replace(']', ']]')

  $Result
  Write-Debug -Message:'[ConvertTo-SqlIdentifier] Exiting'
}
