#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Test-SusdbPermission.AllPresent'        = 'login {0}, {1}; every stage has the permissions it needs'
  'Test-SusdbPermission.AlterIndexTables'  = 'ALTER on dbo.tbLocalizedPropertyForRevision and dbo.tbRevisionSupersedesUpdate'
  'Test-SusdbPermission.AlterProcedure'    = 'ALTER on dbo.spDeleteUpdate'
  'Test-SusdbPermission.Backup'            = 'BACKUP DATABASE'
  'Test-SusdbPermission.DeleteSyncHistory' = 'DELETE on dbo.tbEventInstance'
  'Test-SusdbPermission.ExecuteDelete'     = 'EXECUTE on dbo.spDeleteUpdate'
  'Test-SusdbPermission.ExecuteObsolete'   = 'EXECUTE on dbo.spGetObsoleteUpdatesToCleanup'
  'Test-SusdbPermission.Neither'           = 'neither database owner nor sysadmin'
  'Test-SusdbPermission.NoRow'             = 'the permission query returned no row'
  'Test-SusdbPermission.NotChecked'        = 'not checked: {0}'
  'Test-SusdbPermission.Owner'             = 'database owner'
  'Test-SusdbPermission.OwnerOrSysadmin'   = 'database owner or sysadmin'
  'Test-SusdbPermission.Shortfall'         = '{0} (for {1})'
  'Test-SusdbPermission.SomeMissing'       = 'login {0}, {1}; missing: {2}'
  'Test-SusdbPermission.Sysadmin'          = 'sysadmin'
}

Function Test-SusdbPermission {
  <#
    .SYNOPSIS
        Checks, before any work, which database permissions each stage has.

    .DESCRIPTION
        Asks SQL Server for the effective permissions of the run identity in SUSDB
        (HAS_PERMS_BY_NAME, IS_SRVROLEMEMBER) and maps them to the stages that need them: BACKUP DATABASE
        for Backup; ALTER on dbo.tbLocalizedPropertyForRevision and dbo.tbRevisionSupersedesUpdate (to
        create the custom indexes) for CustomIndexes; ALTER on dbo.spDeleteUpdate for DeleteUpdateFix;
        EXECUTE on dbo.spGetObsoleteUpdatesToCleanup and dbo.spDeleteUpdate for ObsoleteUpdates; EXECUTE
        on dbo.spDeleteUpdate for DeclinedDeletion; DELETE on dbo.tbEventInstance for SyncHistory; and
        database owner or sysadmin (which sp_updatestats requires) for Reindex. A stage with a missing
        permission is skipped with a notice before any work starts. The script never grants permissions
        or changes ownership. When the permissions cannot be queried, Checked is false and no stage is
        skipped for permissions; each then reports its own failure.

    .PARAMETER Connection
        Open SUSDB connection.

    .PARAMETER Log
        The run log, or null.

    .PARAMETER TimeoutSeconds
        Client-side command time-out; zero means none.

    .EXAMPLE
        Test-SusdbPermission -Connection $Connection.Database -Log $Log

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-susdbpermission',
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
    [System.Object]
    $Connection,

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
    [ValidateRange(0, 2147483647)]
    [System.Int32]
    $TimeoutSeconds = 0
  )

  Write-Debug -Message:'[Test-SusdbPermission] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Checked = $False
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Collections.Hashtable]$Private:Granted = $Null
  [System.Collections.Generic.List[System.String]]$Private:Missing = $Null
  [System.Collections.Hashtable]$Private:MissingByStage = $Null
  [System.String]$Private:Query = @(
    'SELECT',
    '  SUSER_SNAME() AS LoginName,',
    '  IS_SRVROLEMEMBER(N''sysadmin'') AS IsSysadmin,',
    '  CASE WHEN USER_NAME() = N''dbo'' THEN 1 ELSE 0 END AS IsDatabaseOwner,',
    '  HAS_PERMS_BY_NAME(DB_NAME(), N''DATABASE'', N''BACKUP DATABASE'') AS CanBackup,',
    '  HAS_PERMS_BY_NAME(N''dbo.tbLocalizedPropertyForRevision'', N''OBJECT'', N''ALTER'') AS CanAlterPropertyTable,',
    '  HAS_PERMS_BY_NAME(N''dbo.tbRevisionSupersedesUpdate'', N''OBJECT'', N''ALTER'') AS CanAlterSupersedenceTable,',
    '  HAS_PERMS_BY_NAME(N''dbo.spDeleteUpdate'', N''OBJECT'', N''ALTER'') AS CanAlterDeleteProcedure,',
    '  HAS_PERMS_BY_NAME(N''dbo.spGetObsoleteUpdatesToCleanup'', N''OBJECT'', N''EXECUTE'') AS CanExecuteObsoleteProcedure,',
    '  HAS_PERMS_BY_NAME(N''dbo.spDeleteUpdate'', N''OBJECT'', N''EXECUTE'') AS CanExecuteDeleteProcedure,',
    '  HAS_PERMS_BY_NAME(N''dbo.tbEventInstance'', N''OBJECT'', N''DELETE'') AS CanDeleteEvents'
  ) -join [System.Environment]::NewLine
  [System.Collections.Specialized.OrderedDictionary]$Private:Required = [ordered]@{ Backup = @('Backup'); CustomIndexes = @('AlterIndexTables'); DeleteUpdateFix = @('AlterProcedure'); DeclinedDeletion = @('ExecuteDelete'); ObsoleteUpdates = @('ExecuteObsolete', 'ExecuteDelete'); SyncHistory = @('DeleteSyncHistory'); Reindex = @('OwnerOrSysadmin') }
  [System.Object]$Private:Row = $Null
  [System.Collections.Generic.List[System.String]]$Private:Shortfalls = $Null
  [System.String]$Private:Standing = [System.String]::Empty
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $MissingByStage = @{}
  $Shortfalls = [System.Collections.Generic.List[System.String]]::new()

  Try {
    $Row = @(Invoke-SusdbCommand -CommandText:$Query -Connection:$Connection -Log:$Log -TimeoutSeconds:$TimeoutSeconds) | Select-Object -First:1
    If ($Null -eq $Row) {
      Throw $Script:Message['Test-SusdbPermission.NoRow']
    }

    $Granted = @{
      Backup            = [System.Boolean]($Row.CanBackup -eq 1)
      AlterIndexTables  = [System.Boolean](($Row.CanAlterPropertyTable -eq 1) -and ($Row.CanAlterSupersedenceTable -eq 1))
      AlterProcedure    = [System.Boolean]($Row.CanAlterDeleteProcedure -eq 1)
      ExecuteObsolete   = [System.Boolean]($Row.CanExecuteObsoleteProcedure -eq 1)
      ExecuteDelete     = [System.Boolean]($Row.CanExecuteDeleteProcedure -eq 1)
      DeleteSyncHistory = [System.Boolean]($Row.CanDeleteEvents -eq 1)
      OwnerOrSysadmin   = [System.Boolean](($Row.IsDatabaseOwner -eq 1) -or ($Row.IsSysadmin -eq 1))
    }

    ForEach ($Stage In $Required.Keys) {
      $Missing = [System.Collections.Generic.List[System.String]]::new()
      ForEach ($Capability In $Required[$Stage]) {
        If ($Granted[$Capability] -eq $False) {
          $Missing.Add($Script:Message[('Test-SusdbPermission.{0}' -f $Capability)])
        }
      }

      If ($Missing.Count -gt 0) {
        $MissingByStage[$Stage] = [System.String[]]$Missing.ToArray()
        $Shortfalls.Add(($Script:Message['Test-SusdbPermission.Shortfall'] -f ($Missing -join ', '), $Stage))
      }
    }

    If ($Row.IsSysadmin -eq 1) {
      $Standing = $Script:Message['Test-SusdbPermission.Sysadmin']
    } ElseIf ($Row.IsDatabaseOwner -eq 1) {
      $Standing = $Script:Message['Test-SusdbPermission.Owner']
    } Else {
      $Standing = $Script:Message['Test-SusdbPermission.Neither']
    }

    If ($Shortfalls.Count -eq 0) {
      $Summary = $Script:Message['Test-SusdbPermission.AllPresent'] -f $Row.LoginName, $Standing
    } Else {
      $Summary = $Script:Message['Test-SusdbPermission.SomeMissing'] -f $Row.LoginName, $Standing, ($Shortfalls -join '; ')
    }

    $Checked = $True
  } Catch {
    $ErrorText = $PSItem.Exception.GetBaseException().Message
    $Summary = $Script:Message['Test-SusdbPermission.NotChecked'] -f $ErrorText
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Checked        = [System.Boolean]$Checked
    MissingByStage = $MissingByStage
    Summary        = [System.String]$Summary
    Error          = [System.String]$ErrorText
  }

  $Result
  Write-Debug -Message:'[Test-SusdbPermission] Exiting'
}
