#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'New-WsusAdministrationObject.Missing' = 'The WSUS administration API type Microsoft.UpdateServices.Administration.{0} is not available; it is loaded when the run connects to WSUS.'
}

Function New-WsusAdministrationObject {
  <#
    .SYNOPSIS
        Creates a scope object of the WSUS administration API.

    .DESCRIPTION
        A seam around the scope classes of Microsoft.UpdateServices.Administration (CleanupScope,
        ComputerTargetScope and UpdateScope), so that tests can replace them on computers without
        WSUS. The API assembly is loaded when the run connects to WSUS; without it the function
        throws.

    .PARAMETER TypeName
        Name of the class in Microsoft.UpdateServices.Administration.

    .EXAMPLE
        New-WsusAdministrationObject -TypeName 'CleanupScope'

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-wsusadministrationobject',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Object])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('CleanupScope', 'ComputerTargetScope', 'UpdateScope')]
    [System.String]
    $TypeName
  )

  Write-Debug -Message:'[New-WsusAdministrationObject] Entering'

  # Initialize Variable(s)
  [System.Type]$Private:Type = $Null
  [System.Object]$Private:Result = $Null

  $Type = ('Microsoft.UpdateServices.Administration.{0}' -f $TypeName) -as [System.Type]
  If ($Null -eq $Type) {
    Throw ($Script:Message['New-WsusAdministrationObject.Missing'] -f $TypeName)
  }

  [System.Object]$Result = [System.Activator]::CreateInstance($Type)

  $Result
  Write-Debug -Message:'[New-WsusAdministrationObject] Exiting'
}
