#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceCertificate {
  <#
    .SYNOPSIS
        Finds a certificate in a local-machine certificate store.

    .DESCRIPTION
        A seam around System.Security.Cryptography.X509Certificates.X509Store, so that tests can replace
        it. Opens the store read-only and returns the subject, expiry and thumbprint of the certificate
        with the given thumbprint, or null when it is not there.

    .PARAMETER StoreName
        Store name, for example My.

    .PARAMETER Thumbprint
        Certificate thumbprint.

    .EXAMPLE
        Get-MaintenanceCertificate -StoreName 'My' -Thumbprint $Thumbprint

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancecertificate',
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
    $StoreName,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Thumbprint
  )

  Write-Debug -Message:'[Get-MaintenanceCertificate] Entering'

  # Initialize Variable(s)
  [System.Security.Cryptography.X509Certificates.X509Store]$Private:Store = $Null
  [PSCustomObject]$Private:Result = $Null

  $Store = [System.Security.Cryptography.X509Certificates.X509Store]::new($StoreName, [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
  Try {
    $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]'ReadOnly, OpenExistingOnly')
    ForEach ($Certificate In $Store.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $Thumbprint, $False)) {
      [PSCustomObject]$Result = [PSCustomObject]@{
        Subject    = [System.String]$Certificate.Subject
        NotAfter   = $Certificate.NotAfter.ToUniversalTime()
        Thumbprint = [System.String]$Certificate.Thumbprint
      }
    }
  } Finally {
    $Store.Close()
  }

  $Result
  Write-Debug -Message:'[Get-MaintenanceCertificate] Exiting'
}
