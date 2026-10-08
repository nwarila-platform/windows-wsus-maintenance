#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-BackupGate.NoneRecent' = 'no backup in this run and none recorded in the last {0} hour(s)'
  'Test-BackupGate.Off'        = 'gate off'
  'Test-BackupGate.Recent'     = 'last full backup finished {0}'
  'Test-BackupGate.ThisRun'    = 'backup made by this run'
  'Test-BackupGate.Unreadable' = 'no backup in this run, and the backup history could not be read: {0}'
}

Function Test-BackupGate {
  <#
    .SYNOPSIS
        Decides whether stages that alter SUSDB may run, given the backup state.

    .DESCRIPTION
        With backup.gate Off the gate is always open. Otherwise it is open when the Backup stage of this
        run created a backup (or, in a dry run, would create one), or when msdb records a full backup of
        the database that finished within backup.freshnessHours. When msdb cannot be read the gate stays
        closed unless this run made a backup, and Detail says why. The caller skips the gated stages
        when the gate is Required and closed, and only warns when it is Advisory.

    .PARAMETER Configuration
        Effective configuration.

    .PARAMETER Log
        The run log, or null.

    .PARAMETER Outcome
        Stage outcomes of this run so far.

    .PARAMETER Server
        Server facts from discovery, or null.

    .EXAMPLE
        Test-BackupGate -Configuration $Effective -Outcome $Outcomes -Server $Server -Log $Log

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-backupgate',
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
    $Configuration,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Log = $Null,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [PSCustomObject[]]
    $Outcome = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [PSCustomObject]
    $Server = $Null
  )

  Write-Debug -Message:'[Test-BackupGate] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Created = 0
  [System.Object]$Private:Database = $Null
  [System.String]$Private:Detail = [System.String]::Empty
  [System.String]$Private:FreshnessQuery = 'SELECT CASE WHEN MAX(backup_finish_date) >= DATEADD(HOUR, -@hours, GETDATE()) THEN 1 ELSE 0 END AS Fresh, MAX(backup_finish_date) AS LastFinish FROM msdb.dbo.backupset WHERE database_name = @database AND type = ''D'''
  [System.Object]$Private:Row = $Null
  [System.Boolean]$Private:Satisfied = $False
  [PSCustomObject]$Private:Result = $Null

  If ($Configuration.backup.gate -eq 'Off') {
    $Satisfied = $True
    $Detail = $Script:Message['Test-BackupGate.Off']
  } Else {
    ForEach ($Item In @($Outcome)) {
      If (($Null -ne $Item) -and ($Item.Name -eq 'Backup')) {
        $Created = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Item.Counts -Name:'Created' -Default:0)
        If ($Item.Counts -is [System.Collections.IDictionary]) {
          $Created = [System.Int32]$Item.Counts['Created'] + [System.Int32]$Item.Counts['WouldCreate']
        }

        If ($Created -gt 0) {
          $Satisfied = $True
          $Detail = $Script:Message['Test-BackupGate.ThisRun']
        }
      }
    }

    $Database = Get-MaintenancePropertyValue -InputObject:$Server -Name:'Database' -Default:$Null
    If (($Satisfied -eq $False) -and ($Null -ne $Database)) {
      Try {
        $Row = @(Invoke-SusdbCommand -CommandText:$FreshnessQuery -Connection:$Database -Log:$Log -Parameter:@{ database = [System.String]$Server.Environment.DatabaseName; hours = [System.Int32]$Configuration.backup.freshnessHours } -TimeoutSeconds:([System.Int32](Get-MaintenancePropertyValue -InputObject:$Server -Name:'CommandTimeoutSeconds' -Default:0))) | Select-Object -First:1
        If (($Null -ne $Row) -and ($Row.Fresh -eq 1)) {
          $Satisfied = $True
          $Detail = $Script:Message['Test-BackupGate.Recent'] -f ([System.DateTime]$Row.LastFinish).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        } Else {
          $Detail = $Script:Message['Test-BackupGate.NoneRecent'] -f $Configuration.backup.freshnessHours
        }
      } Catch {
        $Detail = $Script:Message['Test-BackupGate.Unreadable'] -f $PSItem.Exception.Message
      }
    } ElseIf ($Satisfied -eq $False) {
      $Detail = $Script:Message['Test-BackupGate.NoneRecent'] -f $Configuration.backup.freshnessHours
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Satisfied = [System.Boolean]$Satisfied
    Mode      = [System.String]$Configuration.backup.gate
    Detail    = [System.String]$Detail
  }

  $Result
  Write-Debug -Message:'[Test-BackupGate] Exiting'
}
