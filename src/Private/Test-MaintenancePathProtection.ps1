#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenancePathProtection.Owner' = '{0} (owner)'
}

Function Test-MaintenancePathProtection {
  <#
    .SYNOPSIS
        Finds the principals other than the trusted ones that can change a file or folder.

    .DESCRIPTION
        Reads the owner and the access rules of the path (Get-MaintenancePathAccess) and lists every
        principal outside the trusted set that is the owner (who can always change the permissions) or
        that an allow rule, explicit or inherited, gives any right to change it or its contents: write
        data, append data, write attributes or extended attributes, delete, delete child items, change
        permissions, take ownership, or generic write or all. Besides the given identifiers, service
        identities (S-1-5-80-, for example TrustedInstaller and the SQL Server service), CREATOR OWNER
        and OWNER RIGHTS are trusted, since they stand for a service or for the owner, which is checked
        itself. A path that does not exist has no writers.

    .PARAMETER Path
        File or folder to check.

    .PARAMETER TrustedSid
        Security identifiers that may change it (Get-MaintenanceTrustedSid).

    .EXAMPLE
        Test-MaintenancePathProtection -Path 'C:\ProgramData\NWarila\bin' -TrustedSid (Get-MaintenanceTrustedSid)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancepathprotection',
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
    $Path,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $TrustedSid
  )

  Write-Debug -Message:'[Test-MaintenancePathProtection] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Access = $Null
  [System.Boolean]$Private:Trusted = $False
  # WriteData 0x2, AppendData 0x4, WriteExtendedAttributes 0x10, DeleteSubdirectoriesAndFiles 0x40,
  #   WriteAttributes 0x100, Delete 0x10000, ChangePermissions 0x40000, TakeOwnership 0x80000,
  #   GENERIC_ALL 0x10000000 and GENERIC_WRITE 0x40000000:
  #   https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.filesystemrights
  [System.Int32]$Private:WriteRights = 0x500D0156
  [System.Collections.Generic.List[System.String]]$Private:Writers = $Null
  [PSCustomObject]$Private:Result = $Null

  $Access = Get-MaintenancePathAccess -Path:$Path
  $Writers = [System.Collections.Generic.List[System.String]]::new()
  If ($Null -ne $Access) {
    If ((($TrustedSid -contains $Access.OwnerSid) -or ($Access.OwnerSid -like 'S-1-5-80-*')) -eq $False) {
      $Writers.Add(($Script:Message['Test-MaintenancePathProtection.Owner'] -f $Access.OwnerName))
    }

    ForEach ($Rule In @($Access.Rules)) {
      $Trusted = ($TrustedSid -contains $Rule.Sid) -or ($Rule.Sid -like 'S-1-5-80-*') -or ($Rule.Sid -eq 'S-1-3-0') -or ($Rule.Sid -eq 'S-1-3-4')
      If (($Rule.Allow -eq $True) -and (($Rule.Rights -band $WriteRights) -ne 0) -and ($Trusted -eq $False) -and ($Writers.Contains($Rule.Name) -eq $False)) {
        $Writers.Add($Rule.Name)
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Exists     = [System.Boolean]($Null -ne $Access)
    Permissive = [System.Boolean]($Writers.Count -gt 0)
    Writers    = [System.String[]]$Writers.ToArray()
  }

  $Result
  Write-Debug -Message:'[Test-MaintenancePathProtection] Exiting'
}
