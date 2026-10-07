# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Stand-ins for the WSUS administration interface and SQL Server, so that discovery, the
# synchronization guard and the database helpers run on any platform. Each mirrors only the
# members the script uses.

Function New-FakeUpdateServer {
  Param (
    [System.Boolean]$IsReplica = $False,
    [System.Boolean]$SyncFromMicrosoftUpdate = $True,
    [System.String[]]$Statuses = @('NotProcessing'),
    [System.Boolean]$SynchronizeAutomatically = $True,
    [System.String]$UpstreamName = 'upstream.example',
    [System.Int32]$UpstreamPort = 8531,
    [System.Boolean]$UpstreamUseSsl = $True,
    [System.Boolean]$ConfigurationFails = $False,
    [System.Boolean]$StartFails = $False,
    [System.Boolean]$SaveFails = $False
  )

  $State = [PSCustomObject]@{
    Statuses           = [System.Collections.Generic.Queue[System.String]]::new([System.String[]]$Statuses)
    StopCalls          = 0
    StartCalls         = 0
    Saves              = 0
    StartFails         = $StartFails
    SaveFails          = $SaveFails
    ConfigurationFails = $ConfigurationFails
  }

  $Subscription = [PSCustomObject]@{ SynchronizeAutomatically = $SynchronizeAutomatically; State = $State }
  $Subscription | Add-Member -MemberType ScriptMethod -Name GetSynchronizationStatus -Value {
    If ($this.State.Statuses.Count -gt 1) { $this.State.Statuses.Dequeue() } Else { $this.State.Statuses.Peek() }
  }
  $Subscription | Add-Member -MemberType ScriptMethod -Name StopSynchronization -Value { $this.State.StopCalls++ }
  $Subscription | Add-Member -MemberType ScriptMethod -Name StartSynchronization -Value {
    If ($this.State.StartFails) { Throw 'The synchronization could not be started.' }
    $this.State.StartCalls++
  }
  $Subscription | Add-Member -MemberType ScriptMethod -Name Save -Value {
    If ($this.State.SaveFails) { Throw 'The subscription could not be saved.' }
    $this.State.Saves++
  }

  $Configuration = [PSCustomObject]@{
    IsReplicaServer              = $IsReplica
    SyncFromMicrosoftUpdate      = $SyncFromMicrosoftUpdate
    UpstreamWsusServerName       = $UpstreamName
    UpstreamWsusServerPortNumber = $UpstreamPort
    UpstreamWsusServerUseSsl     = $UpstreamUseSsl
  }

  $Server = [PSCustomObject]@{
    Name                             = 'wsus01.example'
    PortNumber                       = 8531
    IsConnectionSecureForApiRemoting = $True
    Version                          = [System.Version]'10.0.20348.2700'
    PreferredCulture                 = ''
    Subscription                     = $Subscription
    Configuration                    = $Configuration
    State                            = $State
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetSubscription -Value { $this.Subscription }
  $Server | Add-Member -MemberType ScriptMethod -Name GetConfiguration -Value {
    If ($this.State.ConfigurationFails) { Throw 'The configuration could not be read.' }
    $this.Configuration
  }
  $Server
}

Function New-FakeDataReader {
  Param ([System.Object[]]$Rows = @())

  $Reader = [PSCustomObject]@{ Rows = @($Rows); Position = -1; Disposed = 0 }
  $Reader | Add-Member -MemberType ScriptProperty -Name FieldCount -Value { @($this.Rows[$this.Position].PSObject.Properties).Count }
  $Reader | Add-Member -MemberType ScriptMethod -Name Read -Value { $this.Position++; $this.Position -lt @($this.Rows).Count }
  $Reader | Add-Member -MemberType ScriptMethod -Name GetName -Value { Param ($Index) @($this.Rows[$this.Position].PSObject.Properties)[$Index].Name }
  $Reader | Add-Member -MemberType ScriptMethod -Name GetValue -Value { Param ($Index) @($this.Rows[$this.Position].PSObject.Properties)[$Index].Value }
  $Reader | Add-Member -MemberType ScriptMethod -Name IsDBNull -Value { Param ($Index) $Null -eq @($this.Rows[$this.Position].PSObject.Properties)[$Index].Value }
  $Reader | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }
  $Reader
}

# A responder answers each command: it receives the command text, the parameter values (keys
#   with their @ prefix) and whether the command is a non-query, and returns rows, a count of
#   rows affected, or throws. Without one, every query returns -Rows and every non-query
#   returns -Affected.
Function New-FakeSqlConnection {
  Param (
    [System.Object[]]$Rows = @(),
    [System.Int32]$Affected = 0,
    [System.String[]]$InfoMessages = @(),
    [System.String]$Failure = '',
    [System.Management.Automation.ScriptBlock]$Responder = $Null
  )

  $Connection = [PSCustomObject]@{
    Rows         = @($Rows)
    Affected     = $Affected
    InfoMessages = @($InfoMessages)
    Failure      = $Failure
    Responder    = $Responder
    Handlers     = [System.Collections.Generic.List[System.Object]]::new()
    Commands     = [System.Collections.Generic.List[System.Object]]::new()
    Disposed     = 0
  }
  $Connection | Add-Member -MemberType ScriptMethod -Name add_InfoMessage -Value { Param ($Handler) $this.Handlers.Add($Handler) }
  $Connection | Add-Member -MemberType ScriptMethod -Name remove_InfoMessage -Value { Param ($Handler) $Null = $this.Handlers.Remove($Handler) }
  $Connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed++ }
  $Connection | Add-Member -MemberType ScriptMethod -Name CreateCommand -Value {
    $Owner = $this
    $Parameters = [PSCustomObject]@{ Values = [ordered]@{} }
    $Parameters | Add-Member -MemberType ScriptMethod -Name AddWithValue -Value { Param ($Name, $Value) $this.Values[$Name] = $Value; $Value }
    $Command = [PSCustomObject]@{ CommandText = ''; CommandTimeout = 30; Parameters = $Parameters; Owner = $Owner }
    $Command | Add-Member -MemberType ScriptMethod -Name Raise -Value {
      ForEach ($Text In $this.Owner.InfoMessages) {
        ForEach ($Handler In @($this.Owner.Handlers)) { & $Handler $this.Owner ([PSCustomObject]@{ Message = $Text }) }
      }
      If (-not [System.String]::IsNullOrEmpty($this.Owner.Failure)) { Throw $this.Owner.Failure }
    }
    $Command | Add-Member -MemberType ScriptMethod -Name ExecuteReader -Value {
      $this.Raise()
      If ($Null -ne $this.Owner.Responder) {
        New-FakeDataReader -Rows @(& $this.Owner.Responder $this.CommandText $this.Parameters.Values $False)
      } Else {
        New-FakeDataReader -Rows $this.Owner.Rows
      }
    }
    $Command | Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Value {
      $this.Raise()
      If ($Null -ne $this.Owner.Responder) {
        & $this.Owner.Responder $this.CommandText $this.Parameters.Values $True
      } Else {
        $this.Owner.Affected
      }
    }
    $this.Commands.Add($Command)
    $Command
  }
  $Connection
}

Function New-PermissionRow {
  Param (
    [System.Int32]$IsSysadmin = 0,
    [System.Int32]$IsDatabaseOwner = 1,
    [System.Object]$CanBackup = 1,
    [System.Object]$CanAlterPropertyTable = 1,
    [System.Object]$CanAlterSupersedenceTable = 1,
    [System.Object]$CanAlterDeleteProcedure = 1,
    [System.Object]$CanExecuteObsoleteProcedure = 1,
    [System.Object]$CanExecuteDeleteProcedure = 1,
    [System.Object]$CanDeleteEvents = 1
  )

  [PSCustomObject]@{
    LoginName                   = 'NT AUTHORITY\SYSTEM'
    IsSysadmin                  = $IsSysadmin
    IsDatabaseOwner             = $IsDatabaseOwner
    CanBackup                   = $CanBackup
    CanAlterPropertyTable       = $CanAlterPropertyTable
    CanAlterSupersedenceTable   = $CanAlterSupersedenceTable
    CanAlterDeleteProcedure     = $CanAlterDeleteProcedure
    CanExecuteObsoleteProcedure = $CanExecuteObsoleteProcedure
    CanExecuteDeleteProcedure   = $CanExecuteDeleteProcedure
    CanDeleteEvents             = $CanDeleteEvents
  }
}

Function Get-FakeCommandText {
  Param ($Connection)
  @($Connection.Commands | ForEach-Object -Process { $PSItem.CommandText })
}

# A stage context as Invoke-MaintenanceRun builds it, around a stand-in SUSDB connection.
Function New-FakeStageContext {
  Param (
    $Database,
    [System.String]$Extra = '',
    [System.Boolean]$DryRun = $False,
    [System.String]$Tier = 'Autonomous',
    $Permission = $Null,
    $Deadline = $Null,
    [System.Boolean]$RemoveCustomIndexes = $False,
    $Log = $Null
  )

  $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\Backups" }' + $Extra + ' }'
  [PSCustomObject]@{
    StageName           = 'Stage'
    DryRun              = $DryRun
    Configuration       = ConvertTo-MaintenanceEffectiveConfiguration -Document ($Json | ConvertFrom-Json)
    Deadline            = $Deadline
    RunStart            = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)
    Log                 = $Log
    Server              = [PSCustomObject]@{
      Tier                  = $Tier
      Database              = $Database
      CommandTimeoutSeconds = 0
      Permission            = $Permission
      Environment           = [PSCustomObject]@{ DatabaseName = 'SUSDB' }
    }
    RemoveCustomIndexes = $RemoveCustomIndexes
  }
}

# Answers every query the upkeep stages make on a healthy, already maintained SUSDB: the fix
#   and the custom indexes are in place, nothing is obsolete, fragmented or old, and a full
#   backup finished recently. A backup command writes a small file where it was told to.
#   -Permission replaces the permission row; -PermissionFailure makes that query fail.
Function New-UpkeepResponder {
  Param (
    $Permission = (New-PermissionRow),
    [System.String]$PermissionFailure = ''
  )

  {
    Param ($Text, $Parameters, $NonQuery)
    If ($NonQuery) {
      If ($Text -like 'BACKUP DATABASE*') {
        [System.IO.File]::WriteAllText($Parameters['@path'], 'backup')
      }
      0
    } ElseIf ($Text -match 'HAS_PERMS_BY_NAME') {
      If ($PermissionFailure -ne '') { Throw $PermissionFailure }
      $Permission
    } ElseIf ($Text -match 'SERVERPROPERTY') {
      [PSCustomObject]@{ Edition = 'Standard Edition (64-bit)'; ReservedBytes = [System.Int64]1048576 }
    } ElseIf ($Text -match 'OBJECT_DEFINITION') {
      [PSCustomObject]@{ Definition = "CREATE PROCEDURE dbo.spDeleteUpdate @localUpdateID int AS`nDECLARE @revisionList TABLE(RevisionID INT PRIMARY KEY)`nRETURN(0)" }
    } ElseIf ($Text -match 'sys\.extended_properties') {
      [PSCustomObject]@{ TableExists = 1; IndexExists = 1; CreatedByScript = 1 }
    } ElseIf ($Text -match 'COL_LENGTH') {
      [PSCustomObject]@{ Length = 8 }
    } ElseIf ($Text -match 'COUNT_BIG') {
      [PSCustomObject]@{ Total = [System.Int64]0 }
    } ElseIf ($Text -match 'msdb') {
      [PSCustomObject]@{ Fresh = 1; LastFinish = [System.DateTime]::new(2026, 11, 2, 0, 30, 0) }
    }
  }.GetNewClosure()
}
