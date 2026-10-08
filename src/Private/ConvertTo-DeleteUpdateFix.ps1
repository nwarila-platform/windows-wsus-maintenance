#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-DeleteUpdateFix {
  <#
    .SYNOPSIS
        Works out whether spDeleteUpdate carries Microsoft's fix, and the edited definition if not.

    .DESCRIPTION
        Microsoft's fix for the slow spDeleteUpdate procedure adds a primary key to the @revisionList
        table variable: DECLARE @revisionList TABLE(RevisionID INT PRIMARY KEY). This function looks for
        exactly that declaration in the live definition. With the primary key present the state is
        Applied. With exactly one declaration lacking it, and a CREATE PROCEDURE header, the state is
        Missing and Definition holds the live text with only two changes: PRIMARY KEY added to that
        declaration and CREATE turned into ALTER. Anything else (no declaration, several, or an
        unexpected header) is Unexpected, and the procedure must be left untouched.

    .PARAMETER Definition
        Live definition of dbo.spDeleteUpdate (OBJECT_DEFINITION).

    .EXAMPLE
        ConvertTo-DeleteUpdateFix -Definition $Definition

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#convertto-deleteupdatefix',
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
    $Definition
  )

  Write-Debug -Message:'[ConvertTo-DeleteUpdateFix] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Edited = [System.String]::Empty
  [System.Int32]$Private:FixedCount = 0
  [System.String]$Private:FixedPattern = '(?i)DECLARE\s+@revisionList\s+TABLE\s*\(\s*RevisionID\s+INT\s+PRIMARY\s+KEY\s*\)'
  [System.String]$Private:HeaderPattern = '(?is)^(?<lead>\s*(?:(?:--[^\n]*\n|/\*.*?\*/)\s*)*)CREATE\s+PROC(?:EDURE)?\b'
  [System.Int32]$Private:MissingCount = 0
  [System.String]$Private:MissingPattern = '(?i)(?<declaration>DECLARE\s+@revisionList\s+TABLE\s*\(\s*RevisionID\s+INT)(?<close>\s*\))'
  [System.String]$Private:State = 'Unexpected'
  [PSCustomObject]$Private:Result = $Null

  # The fix is the primary key Microsoft adds to @revisionList in spDeleteUpdate:
  #   https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/spdeleteupdate-slow-performance
  $FixedCount = [System.Text.RegularExpressions.Regex]::Matches($Definition, $FixedPattern).Count
  $MissingCount = [System.Text.RegularExpressions.Regex]::Matches($Definition, $MissingPattern).Count

  If (($FixedCount -eq 1) -and ($MissingCount -eq 0)) {
    $State = 'Applied'
  } ElseIf (($FixedCount -eq 0) -and ($MissingCount -eq 1) -and ([System.Text.RegularExpressions.Regex]::IsMatch($Definition, $HeaderPattern) -eq $True)) {
    $State = 'Missing'
    $Edited = [System.Text.RegularExpressions.Regex]::Replace($Definition, $MissingPattern, '${declaration} PRIMARY KEY${close}')
    $Edited = ([System.Text.RegularExpressions.Regex]::new($HeaderPattern)).Replace($Edited, '${lead}ALTER PROCEDURE', 1)
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    State      = [System.String]$State
    Definition = [System.String]$Edited
  }

  $Result
  Write-Debug -Message:'[ConvertTo-DeleteUpdateFix] Exiting'
}
