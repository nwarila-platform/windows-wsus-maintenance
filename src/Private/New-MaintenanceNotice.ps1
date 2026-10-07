#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-MaintenanceNotice {
  <#
    .SYNOPSIS
        Creates a notice: a condition that needs attention.

    .DESCRIPTION
        Severities, in order: Information, Warning, High, Error. High marks something that
        needs attention without being an error (for example a guard breach); it raises the
        run status to Warning. Error raises it to Error. A notice may carry a link to
        further reading and a suggested command; the HTML report renders them as a hyperlink
        and as preformatted text.

    .PARAMETER Command
        Suggested command, if any.

    .PARAMETER Link
        Address of further reading, if any.

    .PARAMETER Message
        What happened and, where it helps, what to do.

    .PARAMETER Severity
        Information, Warning, High or Error.

    .PARAMETER Stage
        Stage the notice belongs to, if any.

    .EXAMPLE
        New-MaintenanceNotice -Severity 'Warning' -Message 'Time budget reached.'

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-maintenancenotice',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Command = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Link = '',

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Message,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateSet('Information', 'Warning', 'High', 'Error')]
    [System.String]
    $Severity,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Stage = ''
  )

  Write-Debug -Message:'[New-MaintenanceNotice] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Result = $Null

  [PSCustomObject]$Result = [PSCustomObject]@{
    Severity = [System.String]$Severity
    Message  = [System.String]$Message
    Stage    = [System.String]$Stage
    Link     = [System.String]$Link
    Command  = [System.String]$Command
    RaisedAt = Get-MaintenanceTime
  }
  $Result.PSTypeNames.Insert(0, 'WsusMaintenance.Notice')

  $Result
  Write-Debug -Message:'[New-MaintenanceNotice] Exiting'
}
