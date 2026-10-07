#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceIntegerValue.Integer' = '{0}: must be a whole number (got {1}).'
  'Test-MaintenanceIntegerValue.Range'   = '{0}: must be from {1} to {2} (got {3}).'
}

Function Test-MaintenanceIntegerValue {
  <#
    .SYNOPSIS
        Validates one whole-number configuration value.

    .DESCRIPTION
        Accepts only JSON whole numbers (never booleans, fractions or quoted digits) and
        checks the inclusive range. Returns every problem found.

    .PARAMETER Maximum
        Inclusive upper bound, or null for none.

    .PARAMETER Minimum
        Inclusive lower bound, or null for none.

    .PARAMETER Path
        Location of the value in the document, used in messages.

    .PARAMETER Value
        The value to validate.

    .EXAMPLE
        Test-MaintenanceIntegerValue -Minimum 1 -Maximum 600 -Path 'run.connectionTimeoutSeconds' -Value 601

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenanceintegervalue',
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
    [AllowNull()]
    [System.Object]
    $Maximum = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $Minimum = $Null,

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
    [AllowNull()]
    [System.Object]
    $Value
  )

  Write-Debug -Message:'[Test-MaintenanceIntegerValue] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.Boolean]$Private:IsInteger = $False
  [System.String]$Private:LowerText = [System.String]::Empty
  [System.String[]]$Private:Result = @()
  [System.String]$Private:UpperText = [System.String]::Empty

  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $IsInteger = (
    ($Value -is [System.Int32]) -or
    ($Value -is [System.Int64]) -or
    ($Value -is [System.Int16]) -or
    ($Value -is [System.Byte]) -or
    ($Value -is [System.SByte]) -or
    ($Value -is [System.UInt16]) -or
    ($Value -is [System.UInt32])
  )

  If ($IsInteger -eq $False) {
    $Errors.Add(($Script:Message['Test-MaintenanceIntegerValue.Integer'] -f $Path, (ConvertTo-MaintenanceDisplayValue -Value:$Value)))
  } ElseIf ((($Null -ne $Minimum) -and ($Value -lt $Minimum)) -or (($Null -ne $Maximum) -and ($Value -gt $Maximum))) {
    $LowerText = If ($Null -eq $Minimum) { 'any' } Else { [System.String]$Minimum }
    $UpperText = If ($Null -eq $Maximum) { 'any' } Else { [System.String]$Maximum }
    $Errors.Add(($Script:Message['Test-MaintenanceIntegerValue.Range'] -f $Path, $LowerText, $UpperText, $Value))
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceIntegerValue] Exiting'
}
