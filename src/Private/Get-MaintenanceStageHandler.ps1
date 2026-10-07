#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Get-MaintenanceStageHandler {
  <#
    .SYNOPSIS
        Returns the script block that carries out a stage, if this build has one.

    .DESCRIPTION
        Each stage milestone registers its handler here. A handler takes one -Context
        parameter (stage name, dry-run flag, configuration, deadline, run start, run log) and
        returns an outcome with an optional Status (Success, Warning or Error), Counts,
        Items, Message and Notices. A stage that works item by item logs its progress with
        Write-MaintenanceProgress. A stage with no handler yet is reported as not available,
        which does not affect the run status.

    .PARAMETER Name
        Stage name.

    .EXAMPLE
        Get-MaintenanceStageHandler -Name 'Reindex'

    .OUTPUTS
        [System.Management.Automation.ScriptBlock]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-maintenancestagehandler',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Name
  )

  Write-Debug -Message:'[Get-MaintenanceStageHandler] Entering'

  # Initialize Variable(s)
  [System.Collections.Hashtable]$Private:Handlers = @{}
  [System.Management.Automation.ScriptBlock]$Private:Result = $Null

  If ($Handlers.ContainsKey($Name) -eq $True) {
    [System.Management.Automation.ScriptBlock]$Result = $Handlers[$Name]
    $Result
  }

  Write-Debug -Message:'[Get-MaintenanceStageHandler] Exiting'
}
