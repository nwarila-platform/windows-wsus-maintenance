#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-MaintenanceDependency.IisConfiguration' = 'the IIS configuration (applicationHost.config)'
  'Test-MaintenanceDependency.Missing'          = 'missing'
  'Test-MaintenanceDependency.Present'          = 'present'
  'Test-MaintenanceDependency.SqlClient'        = 'the SQL Server client (System.Data.SqlClient)'
  'Test-MaintenanceDependency.Unchecked'        = 'not checked ({0})'
  'Test-MaintenanceDependency.WsusApi'          = 'the WSUS administration API (Microsoft.UpdateServices.Administration)'
}

Function Test-MaintenanceDependency {
  <#
    .SYNOPSIS
        Checks that every dependency of the script is present before anything is changed.

    .DESCRIPTION
        Looks for each component the script uses (Test-MaintenanceDependencyPresent) and returns a
        summary for the run log (REQ-093). The script brings everything else with it and never
        downloads or installs anything, so a missing component only limits what the run can do:

        - the WSUS administration API and the SQL Server client are needed by the whole run, so a
          missing one is returned in Blocking and the run stops as a failed precondition;
        - the IIS configuration is needed by IIS log retention when iisLogs.folder does not name the
          folder, so a missing one makes that stage unavailable (in Unavailable, by stage name).

        A check that fails counts as a missing component, with the reason.

    .PARAMETER Configuration
        Effective configuration.

    .EXAMPLE
        Test-MaintenanceDependency -Configuration $Effective

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-maintenancedependency',
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
    [ValidateNotNull()]
    [PSCustomObject]
    $Configuration
  )

  Write-Debug -Message:'[Test-MaintenanceDependency] Entering'

  # Initialize Variable(s)
  [System.Collections.Generic.List[System.String]]$Private:Blocking = $Null
  [PSCustomObject[]]$Private:Catalogue = @()
  [System.String[]]$Private:IisStages = @()
  [System.String]$Private:Label = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Parts = $Null
  [System.Boolean]$Private:Present = $False
  [System.String]$Private:State = [System.String]::Empty
  [System.Collections.Hashtable]$Private:Unavailable = $Null
  [PSCustomObject]$Private:Result = $Null

  $Parts = [System.Collections.Generic.List[System.String]]::new()
  $Blocking = [System.Collections.Generic.List[System.String]]::new()
  $Unavailable = @{}
  $IisStages = @()
  If ([System.String]::IsNullOrEmpty([System.String](Get-MaintenancePropertyValue -InputObject:$Configuration.iisLogs -Name:'folder' -Default:''))) {
    $IisStages = @('IisLogRetention')
  }

  $Catalogue = @(
    [PSCustomObject]@{ Name = 'WsusApi'; WholeRun = $True; Stages = [System.String[]]@() }
    [PSCustomObject]@{ Name = 'SqlClient'; WholeRun = $True; Stages = [System.String[]]@() }
    [PSCustomObject]@{ Name = 'IisConfiguration'; WholeRun = $False; Stages = [System.String[]]$IisStages }
  )

  ForEach ($Dependency In $Catalogue) {
    $Label = $Script:Message[('Test-MaintenanceDependency.{0}' -f $Dependency.Name)]
    Try {
      $Present = Test-MaintenanceDependencyPresent -Name:$Dependency.Name
      $State = $(If ($Present -eq $True) { $Script:Message['Test-MaintenanceDependency.Present'] } Else { $Script:Message['Test-MaintenanceDependency.Missing'] })
    } Catch {
      $Present = $False
      $State = $Script:Message['Test-MaintenanceDependency.Unchecked'] -f $PSItem.Exception.GetBaseException().Message
    }

    $Parts.Add(('{0} {1}' -f $Label, $State))
    If ($Present -eq $False) {
      If ($Dependency.WholeRun -eq $True) {
        $Blocking.Add($Label)
      }

      ForEach ($StageName In $Dependency.Stages) {
        $Unavailable[$StageName] = $Label
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Summary     = [System.String]($Parts -join '; ')
    Blocking    = [System.String[]]$Blocking.ToArray()
    Unavailable = $Unavailable
  }

  $Result
  Write-Debug -Message:'[Test-MaintenanceDependency] Exiting'
}
