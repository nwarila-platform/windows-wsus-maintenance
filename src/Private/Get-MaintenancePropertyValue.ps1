#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenancePropertyValue {
  <#
    .SYNOPSIS
        Reads a property that an object may not have.

    .DESCRIPTION
        Returns the value of the named property, or the default when the object is null or has no
        such property. Stage handlers and notices are plain objects whose optional members may be
        missing, and reading a missing member directly fails under strict mode.

    .PARAMETER Default
        Value returned when the property is missing.

    .PARAMETER InputObject
        Object to read.

    .PARAMETER Name
        Property name.

    .EXAMPLE
        Get-MaintenancePropertyValue -InputObject $Notice -Name 'Link' -Default ''

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancepropertyvalue',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Object])]
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
    $Default = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $InputObject,

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

  Write-Debug -Message:'[Get-MaintenancePropertyValue] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Result = $Null

  [System.Object]$Result = $Default

  If (($Null -ne $InputObject) -and ($Null -ne $InputObject.PSObject.Properties[$Name])) {
    $Result = $InputObject.PSObject.Properties[$Name].Value
  }

  $Result
  Write-Debug -Message:'[Get-MaintenancePropertyValue] Exiting'
}
