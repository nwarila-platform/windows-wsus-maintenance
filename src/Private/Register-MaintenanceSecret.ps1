#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Secret value(s) registered during the run. Protect-MaintenanceText removes every one of them
#   from any text before it is written anywhere.
[System.Collections.Generic.HashSet[System.String]]$Script:MaintenanceSecret = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)

Function Register-MaintenanceSecret {
  <#
    .SYNOPSIS
        Registers a secret value so that it is never written anywhere.

    .DESCRIPTION
        Every value registered here is replaced by a redaction marker in every log entry, report,
        summary and event message the run writes (Protect-MaintenanceText). Release one consumes no
        secrets; a feature that later reads one (for example a mail credential) registers it as soon as
        it is read.

    .PARAMETER Value
        The secret value. An empty value is ignored.

    .EXAMPLE
        Register-MaintenanceSecret -Value $Credential.GetNetworkCredential().Password

    .OUTPUTS
        [System.Void]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#register-maintenancesecret',
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
    [AllowEmptyString()]
    [System.String]
    $Value
  )

  Write-Debug -Message:'[Register-MaintenanceSecret] Entering'

  If ([System.String]::IsNullOrEmpty($Value) -eq $False) {
    $Null = $Script:MaintenanceSecret.Add($Value)
  }

  Write-Debug -Message:'[Register-MaintenanceSecret] Exiting'
}
