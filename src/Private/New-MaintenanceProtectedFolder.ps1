#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceProtectedFolder {
  <#
    .SYNOPSIS
        Creates one folder with a protected access control list.

    .DESCRIPTION
        A seam around the creation of a folder together with its security descriptor, so that tests can
        replace it. The folder is created with inheritance from its parent turned off and with full
        control, inherited by its files and sub-folders, for each given identity (a security identifier
        or an account name) and nobody else, in one step, so there is no moment at which it carries the
        parent's permissions. The parent folder must exist. Windows PowerShell uses
        Directory.CreateDirectory with a DirectorySecurity; PowerShell 7 uses
        FileSystemAclExtensions.Create:
        https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions.create

    .PARAMETER Identity
        Security identifiers or account names to grant full control.

    .PARAMETER Path
        Folder to create.

    .EXAMPLE
        New-MaintenanceProtectedFolder -Path 'C:\ProgramData\NWarila\WsusMaintenance' -Identity @('S-1-5-18', 'S-1-5-32-544')

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenanceprotectedfolder',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $Identity,

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

  Write-Debug -Message:'[New-MaintenanceProtectedFolder] Entering'

  # Initialize Variable(s)
  [System.Type]$Private:Extensions = $Null
  [System.Security.Principal.IdentityReference]$Private:Reference = $Null
  [System.Security.AccessControl.DirectorySecurity]$Private:Security = $Null

  $Security = [System.Security.AccessControl.DirectorySecurity]::new()
  $Security.SetAccessRuleProtection($True, $False)
  ForEach ($Name In $Identity) {
    If ($Name -match '^S-1-') {
      $Reference = [System.Security.Principal.SecurityIdentifier]::new($Name)
    } Else {
      $Reference = [System.Security.Principal.NTAccount]::new($Name)
    }

    $Security.AddAccessRule(
      [System.Security.AccessControl.FileSystemAccessRule]::new(
        $Reference,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
      )
    )
  }

  If ($PSVersionTable.PSEdition -eq 'Desktop') {
    $Null = [System.IO.Directory]::CreateDirectory($Path, $Security)
  } Else {
    $Extensions = 'System.IO.FileSystemAclExtensions' -as [System.Type]
    $Null = $Extensions::Create([System.IO.DirectoryInfo]::new($Path), $Security)
  }

  Write-Debug -Message:'[New-MaintenanceProtectedFolder] Exiting'
}
