#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenancePathAccess {
  <#
    .SYNOPSIS
        Reads the owner and the access rules of a file or folder.

    .DESCRIPTION
        A seam around Get-Acl, so that tests can replace it. Returns the owner and every access rule,
        explicit and inherited, with the security identifier, the account name (the identifier itself
        when it cannot be translated), the rights as their numeric value and whether the rule allows or
        denies; or null when the path does not exist. Nothing is changed.

    .PARAMETER Path
        File or folder to read.

    .EXAMPLE
        Get-MaintenancePathAccess -Path 'C:\ProgramData\NWarila\WsusMaintenance\Logs'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancepathaccess',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Path
  )

  Write-Debug -Message:'[Get-MaintenancePathAccess] Entering'

  # Initialize Variable(s)
  [System.Object]$Private:Acl = $Null
  [System.Security.Principal.SecurityIdentifier]$Private:Owner = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Rules = $Null
  [PSCustomObject]$Private:Result = $Null

  If ((Test-Path -LiteralPath:$Path) -eq $True) {
    $Acl = Get-Acl -LiteralPath:$Path
    $Rules = [System.Collections.Generic.List[PSCustomObject]]::new()
    ForEach ($Rule In $Acl.GetAccessRules($True, $True, [System.Security.Principal.SecurityIdentifier])) {
      $Rules.Add(
        [PSCustomObject]@{
          Sid    = [System.String]$Rule.IdentityReference.Value
          Name   = ConvertTo-MaintenanceAccountName -Sid:([System.Security.Principal.SecurityIdentifier]$Rule.IdentityReference)
          Rights = [System.Int32]$Rule.FileSystemRights
          Allow  = [System.Boolean]($Rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow)
        }
      )
    }

    $Owner = $Acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    [PSCustomObject]$Result = [PSCustomObject]@{
      OwnerSid  = [System.String]$Owner.Value
      OwnerName = ConvertTo-MaintenanceAccountName -Sid:$Owner
      Rules     = [PSCustomObject[]]$Rules.ToArray()
    }
  }

  $Result
  Write-Debug -Message:'[Get-MaintenancePathAccess] Exiting'
}
