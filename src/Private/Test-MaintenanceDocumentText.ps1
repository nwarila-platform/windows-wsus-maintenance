#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceDocumentText.Expression' = '{0}: contains PowerShell expression syntax (a dollar sign followed by a parenthesis or brace); configuration values are data and are never evaluated.'
  'Test-MaintenanceDocumentText.Secret'     = '{0}: looks like a plain-text secret. Secrets are never written into the configuration document; a secret is referenced by name from the secret store.'
}

Function Test-MaintenanceDocumentText {
  <#
    .SYNOPSIS
        Scans a configuration value for embedded expressions and plain-text secrets.

    .DESCRIPTION
        Walks the value recursively. A string containing PowerShell expression syntax is
        refused, so a document carrying script text is rejected rather than evaluated. A
        key whose name marks it as a credential (password, passphrase, secret, token,
        API key, credential, private key) holding a non-empty string is refused as a
        plain-text secret. Returns every problem found.

    .PARAMETER Path
        Location of the value in the document, used in messages.

    .PARAMETER Value
        The value to scan.

    .EXAMPLE
        Test-MaintenanceDocumentText -Path 'report' -Value $Document.report

    .OUTPUTS
        [System.String[]]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancedocumenttext',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
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

  Write-Debug -Message:'[Test-MaintenanceDocumentText] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ChildPath = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [System.Int32]$Private:Index = 0
  [System.Object[]]$Private:Items = @()
  [System.String[]]$Private:Result = @()
  [System.String]$Private:SecretPattern = '(?i)(password|passphrase|secret|token|apikey|api_key|credential|privatekey|private_key)'

  $Errors = [System.Collections.Generic.List[System.String]]::new()

  If ($Value -is [System.String]) {
    If ($Value.Contains('$(') -or $Value.Contains('${')) {
      $Errors.Add(($Script:Message['Test-MaintenanceDocumentText.Expression'] -f $Path))
    }
  } ElseIf ($Value -is [System.Management.Automation.PSCustomObject]) {
    ForEach ($Property In $Value.PSObject.Properties) {
      If ([System.String]::IsNullOrEmpty($Path) -eq $True) {
        $ChildPath = $Property.Name
      } Else {
        $ChildPath = '{0}.{1}' -f $Path, $Property.Name
      }

      If (($Property.Name -match $SecretPattern) -and ($Property.Value -is [System.String]) -and ([System.String]::IsNullOrWhiteSpace($Property.Value) -eq $False)) {
        $Errors.Add(($Script:Message['Test-MaintenanceDocumentText.Secret'] -f $ChildPath))
      }

      ForEach ($ChildError In @(Test-MaintenanceDocumentText -Path:$ChildPath -Value:$Property.Value)) {
        $Errors.Add($ChildError)
      }
    }
  } ElseIf ($Value -is [System.Array]) {
    $Items = @($Value)
    For ($Index = 0; $Index -lt $Items.Count; $Index++) {
      ForEach ($ChildError In @(Test-MaintenanceDocumentText -Path:('{0}[{1}]' -f $Path, $Index) -Value:$Items[$Index])) {
        $Errors.Add($ChildError)
      }
    }
  }

  [System.String[]]$Result = $Errors.ToArray()
  $Result
  Write-Debug -Message:'[Test-MaintenanceDocumentText] Exiting'
}
