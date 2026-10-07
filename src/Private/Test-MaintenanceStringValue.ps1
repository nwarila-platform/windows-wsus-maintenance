#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceStringValue.Allowed' = '{0}: must be one of {1} (got {2}).'
  'Test-MaintenanceStringValue.Pattern' = '{0}: has an invalid format (got {1}).'
  'Test-MaintenanceStringValue.String'  = '{0}: must be a non-empty string (got {1}).'
}

Function Test-MaintenanceStringValue {
  <#
    .SYNOPSIS
        Validates one text configuration value.

    .DESCRIPTION
        Requires a non-empty string; when allowed values are given the match is exact and
        case-sensitive, and when a pattern is given the whole value must match it.
        Returns every problem found.

    .PARAMETER AllowedValues
        The exact values permitted, or none for free text.

    .PARAMETER Path
        Location of the value in the document, used in messages.

    .PARAMETER Pattern
        Regular expression the value must match, or empty for none.

    .PARAMETER Value
        The value to validate.

    .EXAMPLE
        Test-MaintenanceStringValue -AllowedValues @('Replace', 'Append') -Path 'backup.sameDay' -Value 'Replace'

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancestringvalue',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [AllowNull()]
    [System.String[]]
    $AllowedValues = @(),

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
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [AllowNull()]
    [System.String]
    $Pattern = '',

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

  Write-Debug -Message:'[Test-MaintenanceStringValue] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.String[]]$Private:Result = @()

  $Errors = [System.Collections.Generic.List[System.String]]::new()

  If ((($Value -is [System.String]) -eq $False) -or ([System.String]::IsNullOrWhiteSpace($Value) -eq $True)) {
    $Errors.Add(($Script:Message['Test-MaintenanceStringValue.String'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
  } ElseIf ((@($AllowedValues).Count -gt 0) -and (@($AllowedValues) -cnotcontains $Value)) {
    $Errors.Add(($Script:Message['Test-MaintenanceStringValue.Allowed'] -f $Path, (@($AllowedValues) -join ', '), (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
  } ElseIf (([System.String]::IsNullOrEmpty($Pattern) -eq $False) -and ($Value -cnotmatch $Pattern)) {
    $Errors.Add(($Script:Message['Test-MaintenanceStringValue.Pattern'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceStringValue] Exiting'
}
