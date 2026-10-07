#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function New-SusdbMessageHandler {
  <#
    .SYNOPSIS
        Creates the handler that collects the messages a database command prints.

    .DESCRIPTION
        SQL Server returns PRINT output and informational messages through the connection's
        InfoMessage event. The handler adds each message to the collector, which is emptied
        first and which Invoke-SusdbCommand writes to the run log once the command has finished.
        The handler is a closure over the collector, because it runs outside the scope of the
        command.

    .PARAMETER Collector
        List that receives each message.

    .EXAMPLE
        New-SusdbMessageHandler -Collector $Messages

    .OUTPUTS
        [System.Management.Automation.ScriptBlock]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#new-susdbmessagehandler',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.ScriptBlock])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[System.String]]
    $Collector
  )

  Write-Debug -Message:'[New-SusdbMessageHandler] Entering'

  # Initialize Variable(s)
  [System.Management.Automation.ScriptBlock]$Private:Result = $Null

  # The collector starts empty; the handler receives the connection and the message arguments.
  $Collector.Clear()
  [System.Management.Automation.ScriptBlock]$Result = {
    $Collector.Add(('{0}' -f $args[1].Message))
  }.GetNewClosure()

  $Result
  Write-Debug -Message:'[New-SusdbMessageHandler] Exiting'
}
