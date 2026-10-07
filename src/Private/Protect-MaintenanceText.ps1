#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Protect-MaintenanceText.Marker' = '[REDACTED]'
}

Function Protect-MaintenanceText {
  <#
    .SYNOPSIS
        Removes secrets from text before it is written anywhere.

    .DESCRIPTION
        Replaces every registered secret value (Register-MaintenanceSecret) with a redaction marker,
        then the value of any password in connection-string form (Password=...; Pwd=...) and the value
        of any JSON key whose name marks it as a credential (password, passphrase, secret, token, API
        key, credential, private key). Every writer of the log, the reports, the summary and the event
        messages passes its text through this function.

    .PARAMETER Text
        Text to protect.

    .EXAMPLE
        Protect-MaintenanceText -Text $Line

    .OUTPUTS
        [System.String]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#protect-maintenancetext',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [AllowNull()]
    [System.String]
    $Text
  )

  Write-Debug -Message:'[Protect-MaintenanceText] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ConnectionPattern = '(?i)(?<key>\b(?:password|pwd)\s*=\s*)(?:"[^"]*"|''[^'']*''|[^;\r\n]*)'
  [System.String]$Private:JsonPattern = '(?i)(?<key>"[^"]*(?:password|passphrase|secret|token|apikey|api_key|credential|privatekey|private_key)[^"]*"\s*:\s*)"(?:[^"\\]|\\.)*"'
  [System.String[]]$Private:Secrets = @()
  [System.String]$Private:Result = [System.String]::Empty

  [System.String]$Result = [System.String]$Text

  If ([System.String]::IsNullOrEmpty($Result) -eq $False) {
    # The longest value goes first, so a secret that contains another is removed whole.
    $Secrets = [System.String[]]@($Script:MaintenanceSecret | Sort-Object -Property:Length -Descending)
    ForEach ($Secret In $Secrets) {
      $Result = $Result.Replace($Secret, $Script:Message['Protect-MaintenanceText.Marker'])
    }

    $Result = [System.Text.RegularExpressions.Regex]::Replace($Result, $ConnectionPattern, ('${key}' + $Script:Message['Protect-MaintenanceText.Marker']))
    $Result = [System.Text.RegularExpressions.Regex]::Replace($Result, $JsonPattern, ('${key}"' + $Script:Message['Protect-MaintenanceText.Marker'] + '"'))
  }

  $Result
  Write-Debug -Message:'[Protect-MaintenanceText] Exiting'
}
