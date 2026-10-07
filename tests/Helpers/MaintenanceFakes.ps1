# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Stand-ins for the WSUS administration interface and SQL Server, so that discovery, the
# synchronization guard and the database helpers run on any platform. Each mirrors only the
# members the script uses.

# Effective configurations by document text. Building one walks the whole configuration
#   catalogue, which costs about a second per call under breakpoint-based code coverage, so each
#   distinct document is built once per test file and every caller gets its own copy to change.
$script:FakeConfigurations = [System.Collections.Generic.Dictionary[System.String, System.Object]]::new([System.StringComparer]::Ordinal)

Function Copy-FakeObject {
  Param ($InputObject)

  If ($InputObject -is [System.Management.Automation.PSCustomObject]) {
    $Copy = [ordered]@{}
    ForEach ($Property In $InputObject.PSObject.Properties) {
      $Copy[$Property.Name] = Copy-FakeObject -InputObject $Property.Value
    }
    [PSCustomObject]$Copy
  } ElseIf ($InputObject -is [System.Array]) {
    $Copy = [System.Array]::CreateInstance($InputObject.GetType().GetElementType(), $InputObject.Length)
    For ($Index = 0; $Index -lt $InputObject.Length; $Index++) {
      $Copy[$Index] = Copy-FakeObject -InputObject $InputObject[$Index]
    }
    , $Copy
  } Else {
    $InputObject
  }
}

# The effective configuration of a configuration document given as JSON, as a fresh copy.
Function Get-FakeConfiguration {
  Param ([System.String]$Json)

  If ($script:FakeConfigurations.ContainsKey($Json) -eq $False) {
    $script:FakeConfigurations[$Json] = ConvertTo-MaintenanceEffectiveConfiguration -Document ($Json | ConvertFrom-Json)
  }

  Copy-FakeObject -InputObject $script:FakeConfigurations[$Json]
}

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
    [System.Boolean]$SaveFails = $False,
    [System.Object[]]$Computers = @(),
    [System.String[]]$Groups = @(),
    [System.Management.Automation.ScriptBlock]$Cleanup = $Null,
    [System.String[]]$FailingComputers = @(),
    [System.Object[]]$Updates = @(),
    [System.String[]]$FailingUpdates = @(),
    [System.String]$UpdatesFailure = '',
    [System.Boolean]$CultureFails = $False,
    [System.String]$SummariesFailure = '',
    [System.Boolean]$ExpressFiles = $False,
    [System.Boolean]$DownloadAll = $False,
    [System.Boolean]$FilesOnMicrosoftUpdate = $False
  )

  $State = [PSCustomObject]@{
    Statuses           = [System.Collections.Generic.Queue[System.String]]::new([System.String[]]$Statuses)
    StopCalls          = 0
    StartCalls         = 0
    Saves              = 0
    StartFails         = $StartFails
    SaveFails          = $SaveFails
    ConfigurationFails = $ConfigurationFails
    Cleanup            = $Cleanup
    CleanupScopes      = [System.Collections.Generic.List[System.Object]]::new()
    Computers          = [System.Collections.Generic.List[System.Object]]::new()
    Groups             = [System.Collections.Generic.List[System.Object]]::new()
    FailingComputers   = @($FailingComputers)
    Deleted            = [System.Collections.Generic.List[System.String]]::new()
    Added              = [System.Collections.Generic.List[System.String]]::new()
    Updates            = [System.Collections.Generic.List[System.Object]]::new()
    FailingUpdates     = @($FailingUpdates)
    UpdatesFailure     = $UpdatesFailure
    UpdateScopes       = [System.Collections.Generic.List[System.Object]]::new()
    DeclinedUpdates    = [System.Collections.Generic.List[System.String]]::new()
    DeletedUpdates     = [System.Collections.Generic.List[System.String]]::new()
    Culture            = ''
    CultureFails       = $CultureFails
    Cultures           = [System.Collections.Generic.List[System.String]]::new()
    SummariesFailure   = $SummariesFailure
    Approvals          = [System.Collections.Generic.List[System.Object]]::new()
    ApprovalLog        = [System.Collections.Generic.List[System.String]]::new()
    RemovedApprovals   = [System.Collections.Generic.List[System.String]]::new()
    Licences           = [System.Collections.Generic.List[System.String]]::new()
  }
  ForEach ($Update In $Updates) {
    $Update.Server = $State
    $State.Updates.Add($Update)
  }
  If ($Null -eq $State.Cleanup) {
    $State.Cleanup = { Param ($Scope) New-FakeCleanupResult -Scope $Scope }
  }

  ForEach ($Computer In $Computers) {
    $Computer | Add-Member -MemberType NoteProperty -Name State -Value $State -Force
    $State.Computers.Add($Computer)
  }

  ForEach ($GroupName In $Groups) {
    $Group = [PSCustomObject]@{ Name = $GroupName; Id = [System.Guid]::NewGuid().ToString(); Members = [System.Collections.Generic.List[System.Object]]::new(); State = $State }
    $Group | Add-Member -MemberType ScriptMethod -Name GetComputerTargets -Value { Param ($IncludeSubgroups) $this.Members.ToArray() }
    $Group | Add-Member -MemberType ScriptMethod -Name AddComputerTarget -Value {
      Param ($Target)
      If ($this.State.FailingComputers -contains $Target.FullDomainName) { Throw ('The computer {0} could not be added to the group.' -f $Target.FullDomainName) }
      $this.Members.Add($Target)
      $this.State.Added.Add(('{0}:{1}' -f $this.Name, $Target.FullDomainName))
    }
    $State.Groups.Add($Group)
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
    IsReplicaServer                = $IsReplica
    SyncFromMicrosoftUpdate        = $SyncFromMicrosoftUpdate
    UpstreamWsusServerName         = $UpstreamName
    UpstreamWsusServerPortNumber   = $UpstreamPort
    UpstreamWsusServerUseSsl       = $UpstreamUseSsl
    DownloadExpressPackages        = $ExpressFiles
    DownloadUpdateBinariesAsNeeded = -not $DownloadAll
    HostBinariesOnMicrosoftUpdate  = $FilesOnMicrosoftUpdate
  }

  $Server = [PSCustomObject]@{
    Name                             = 'wsus01.example'
    PortNumber                       = 8531
    IsConnectionSecureForApiRemoting = $True
    Version                          = [System.Version]'10.0.20348.2700'
    Subscription                     = $Subscription
    Configuration                    = $Configuration
    State                            = $State
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetSubscription -Value { $this.Subscription }
  $Server | Add-Member -MemberType ScriptProperty -Name PreferredCulture -Value { $this.State.Culture } -SecondValue {
    Param ($Value)
    If ($this.State.CultureFails) { Throw 'The culture is not supported.' }
    $this.State.Culture = $Value
    $this.State.Cultures.Add($Value)
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetUpdates -Value {
    Param ($Scope)
    $this.State.UpdateScopes.Add($Scope)
    If ($this.State.UpdatesFailure -ne '') { Throw $this.State.UpdatesFailure }
    $Declined = [System.String]$Scope.ApprovedStates -eq 'Declined'
    @($this.State.Updates | Where-Object -FilterScript { ($PSItem.IsDeclined -eq $Declined) -and ($PSItem.ArrivalDate -ge $Scope.FromArrivalDate) })
  }
  $Server | Add-Member -MemberType ScriptMethod -Name DeleteUpdate -Value {
    Param ($UpdateId)
    $Target = @($this.State.Updates | Where-Object -FilterScript { $PSItem.Id.UpdateId -eq $UpdateId })[0]
    If ($this.State.FailingUpdates -contains $Target.Title) { Throw ('The update {0} is still referenced by other updates.' -f $Target.Title) }
    $Null = $this.State.Updates.Remove($Target)
    $this.State.DeletedUpdates.Add($Target.Title)
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetCleanupManager -Value {
    $Manager = [PSCustomObject]@{ State = $this.State }
    $Manager | Add-Member -MemberType ScriptMethod -Name PerformCleanup -Value {
      Param ($Scope)
      $this.State.CleanupScopes.Add($Scope)
      & $this.State.Cleanup $Scope
    }
    $Manager
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetComputerTargetCount -Value {
    Param ($Scope)
    @($this.State.Computers | Where-Object -FilterScript { $Scope.IncludeDownstreamComputerTargets -or (-not $PSItem.Downstream) }).Count
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetComputerTargets -Value {
    Param ($Scope)
    @($this.State.Computers | Where-Object -FilterScript { ($Scope.IncludeDownstreamComputerTargets -or (-not $PSItem.Downstream)) -and ($PSItem.LastSyncTime -le $Scope.ToLastSyncTime) })
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetComputerTargetGroups -Value { $this.State.Groups.ToArray() }
  $Server | Add-Member -MemberType ScriptMethod -Name GetSummariesPerUpdate -Value {
    Param ($UpdateScope, $ComputerScope)
    If ($this.State.SummariesFailure -ne '') { Throw $this.State.SummariesFailure }
    ForEach ($Update In @($this.State.Updates | Where-Object -FilterScript { -not $PSItem.IsDeclined })) {
      [PSCustomObject]@{ UpdateId = $Update.Id.UpdateId; NotInstalledCount = $Update.Needed; DownloadedCount = 0; InstalledPendingRebootCount = 0; FailedCount = 0; InstalledCount = 0 }
    }
  }
  $Server | Add-Member -MemberType ScriptMethod -Name GetUpdateApprovals -Value { Param ($Scope) $this.State.Approvals.ToArray() }
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
    $Log = $Null,
    $UpdateServer = $Null
  )

  $Json = '{ "schemaVersion": 1, "backup": { "destination": "H:\\Backups" }' + $Extra + ' }'
  [PSCustomObject]@{
    StageName           = 'Stage'
    DryRun              = $DryRun
    Configuration       = Get-FakeConfiguration -Json $Json
    Deadline            = $Deadline
    RunStart            = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)
    Log                 = $Log
    Server              = [PSCustomObject]@{
      Tier                  = $Tier
      Database              = $Database
      UpdateServer          = $UpdateServer
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

# A client computer as the WSUS administration API describes it. Delete fails for a computer the
#   update server lists in -FailingComputers.
Function New-FakeComputer {
  Param (
    [System.String]$Name,
    $LastSync,
    [System.Boolean]$Downstream = $False
  )

  $Computer = [PSCustomObject]@{
    Id             = [System.Guid]::NewGuid().ToString()
    FullDomainName = $Name
    LastSyncTime   = $LastSync
    OSDescription  = 'Windows Server 2022 Standard'
    ClientVersion  = '10.0.20348.2700'
    Downstream     = $Downstream
    State          = $Null
  }
  $Computer | Add-Member -MemberType ScriptMethod -Name Delete -Value {
    If ($this.State.FailingComputers -contains $this.FullDomainName) { Throw ('The computer {0} could not be deleted.' -f $this.FullDomainName) }
    $this.State.Deleted.Add($this.FullDomainName)
  }
  $Computer
}

# The scope objects of the WSUS administration API, as New-WsusAdministrationObject creates them.
Function New-FakeWsusObject {
  Param ([System.String]$TypeName)

  If ($TypeName -eq 'UpdateScope') {
    [PSCustomObject]@{
      ApprovedStates  = 'Any'
      FromArrivalDate = [System.DateTime]::MinValue
      ToArrivalDate   = [System.DateTime]::MaxValue
    }
  } ElseIf ($TypeName -eq 'CleanupScope') {
    [PSCustomObject]@{
      DeclineSupersededUpdates          = $False
      DeclineExpiredUpdates             = $False
      CleanupObsoleteUpdates            = $False
      CompressUpdates                   = $False
      CleanupObsoleteComputers          = $False
      CleanupUnneededContentFiles       = $False
      CleanupLocalPublishedContentFiles = $False
    }
  } Else {
    [PSCustomObject]@{
      IncludeDownstreamComputerTargets = $False
      FromLastSyncTime                 = [System.DateTime]::MinValue
      ToLastSyncTime                   = [System.DateTime]::MaxValue
    }
  }
}

# Cleanup results with a non-zero counter for each option the scope selects, or for every
#   counter with -All.
Function New-FakeCleanupResult {
  Param ($Scope, [System.Boolean]$All = $False)

  [PSCustomObject]@{
    SupersededUpdatesDeclined = $(If ($All -or $Scope.DeclineSupersededUpdates) { 4 } Else { 0 })
    ExpiredUpdatesDeclined    = $(If ($All -or $Scope.DeclineExpiredUpdates) { 1 } Else { 0 })
    ObsoleteUpdatesDeleted    = $(If ($All -or $Scope.CleanupObsoleteUpdates) { 2 } Else { 0 })
    UpdatesCompressed         = $(If ($All -or $Scope.CompressUpdates) { 3 } Else { 0 })
    ObsoleteComputersDeleted  = $(If ($All -or $Scope.CleanupObsoleteComputers) { 5 } Else { 0 })
    DiskSpaceFreed            = $(If ($All -or $Scope.CleanupUnneededContentFiles) { [System.Int64]1610612736 } Else { [System.Int64]0 })
  }
}

# An update as the WSUS administration API describes it. Decline, Approve and accepting the
#   licence fail for an update the update server lists in -FailingUpdates (by title). Needed is
#   the number of clients that need it; Local means its files are on the server (state Ready);
#   SupersededBy lists the identifiers of the updates that supersede it.
Function New-FakeUpdate {
  Param (
    [System.String]$Title,
    [System.String[]]$Kb = @(),
    [System.String]$Classification = 'Security Updates',
    [System.String[]]$Products = @('Windows Server 2022'),
    [System.String[]]$Families = @('Windows'),
    [System.String]$Source = 'MicrosoftUpdate',
    [System.DateTime]$Created = [System.DateTime]::new(2026, 1, 1),
    [System.DateTime]$Arrived = [System.DateTime]::new(2026, 1, 2),
    [System.Boolean]$Superseded = $False,
    [System.Boolean]$SupersedesOthers = $False,
    [System.Boolean]$Approved = $False,
    [System.Boolean]$Expired = $False,
    [System.Boolean]$Declined = $False,
    [System.String]$LegacyName = '',
    [System.Guid]$Id = [System.Guid]::NewGuid(),
    [System.Int32]$Needed = 0,
    [System.Int32]$Revision = 1,
    [System.Boolean]$Infrastructure = $False,
    [System.Boolean]$Licence = $False,
    [System.Boolean]$UserInput = $False,
    [System.Boolean]$Local = $False,
    [System.Guid[]]$SupersededBy = @()
  )

  $Update = [PSCustomObject]@{
    Id                                 = [PSCustomObject]@{ UpdateId = $Id; RevisionNumber = $Revision }
    Title                              = $Title
    LegacyName                         = $LegacyName
    KnowledgebaseArticles              = $Kb
    ProductTitles                      = $Products
    ProductFamilyTitles                = $Families
    UpdateClassificationTitle          = $Classification
    UpdateSource                       = $Source
    CreationDate                       = $Created
    ArrivalDate                        = $Arrived
    IsSuperseded                       = $Superseded
    HasSupersededUpdates               = $SupersedesOthers
    IsApproved                         = $Approved
    IsDeclined                         = $Declined
    PublicationState                   = $(If ($Expired) { 'Expired' } Else { 'Published' })
    Needed                             = $Needed
    IsWsusInfrastructureUpdate         = $Infrastructure
    RequiresLicenseAgreementAcceptance = $Licence
    InstallationBehavior               = [PSCustomObject]@{ CanRequestUserInput = $UserInput }
    SupersededBy                       = $SupersededBy
    State                              = $(If ($Local) { 'Ready' } Else { 'NotReady' })
    Server                             = $Null
  }
  $Update | Add-Member -MemberType ScriptMethod -Name AcceptLicenseAgreement -Value {
    If ($this.Server.FailingUpdates -contains $this.Title) { Throw ('The licence agreement of {0} could not be accepted.' -f $this.Title) }
    $this.RequiresLicenseAgreementAcceptance = $False
    $this.Server.Licences.Add($this.Title)
  }
  $Update | Add-Member -MemberType ScriptMethod -Name Approve -Value {
    Param ($Action, $Group, $Deadline)
    If ($this.Server.FailingUpdates -contains $this.Title) { Throw ('The update {0} could not be approved.' -f $this.Title) }
    If ($this.RequiresLicenseAgreementAcceptance) { Throw 'You must accept the license agreement for this update before you can approve the update for deployment.' }
    $Approval = [PSCustomObject]@{
      UpdateId              = $this.Id
      ComputerTargetGroupId = [System.Guid]$Group.Id
      Action                = [System.String]$Action
      Deadline              = $(If ($Null -eq $Deadline) { [System.DateTime]::MaxValue } Else { $Deadline })
      Server                = $this.Server
      Title                 = $this.Title
      GroupName             = $Group.Name
    }
    $Approval | Add-Member -MemberType ScriptMethod -Name Delete -Value {
      $Null = $this.Server.Approvals.Remove($this)
      $this.Server.RemovedApprovals.Add(('{0}:{1}' -f $this.GroupName, $this.Title))
    }
    $this.Server.Approvals.Add($Approval)
    $this.Server.ApprovalLog.Add(('{0}:{1}:{2}' -f $Group.Name, $this.Title, $(If ($Null -eq $Deadline) { 'none' } Else { $Deadline.ToString('yyyy-MM-dd HH:mm') })))
    $Approval
  }
  $Update | Add-Member -MemberType ScriptMethod -Name GetRelatedUpdates -Value {
    Param ($Relationship)
    $Ids = @($this.SupersededBy)
    @($this.Server.Updates | Where-Object -FilterScript { $Ids -contains $PSItem.Id.UpdateId })
  }
  $Update | Add-Member -MemberType ScriptMethod -Name Decline -Value {
    If ($this.Server.FailingUpdates -contains $this.Title) { Throw ('The update {0} could not be declined.' -f $this.Title) }
    $this.IsDeclined = $True
    $this.Server.DeclinedUpdates.Add($this.Title)
  }
  $Update
}

# The IIS configuration of a server with the WSUS website, as Get-IisConfiguration reads it from
#   applicationHost.config. The defaults describe a healthy WSUS site whose pool follows
#   Microsoft's recommendations; -Pool* replace the pool's attributes.
Function New-FakeIisConfiguration {
  Param (
    [System.String]$SiteName = 'WSUS Administration',
    [System.String]$SiteId = '1234567',
    [System.String]$PhysicalPath = 'C:\Program Files\Update Services\WebServices\Root',
    [System.String]$Pool = 'WsusPool',
    [System.String]$LogDirectory = '',
    [System.String]$DefaultLogDirectory = '',
    [System.Boolean]$HttpLogging = $True,
    [System.Int32[]]$HttpsPorts = @(8531),
    [System.Boolean]$RemoteAdministration = $True,
    [System.String]$PoolAttributes = 'queueLength="2000"',
    [System.String]$ProcessModel = 'idleTimeout="00:00:00" pingingEnabled="false"',
    [System.String]$PeriodicRestart = 'privateMemory="0" memory="0" time="00:00:00"',
    [System.String]$PoolDefaults = '',
    [System.String]$ExtraSites = ''
  )

  $Https = (@($HttpsPorts) | ForEach-Object -Process { '<binding protocol="https" bindingInformation="*:{0}:" />' -f $PSItem }) -join ''
  $LogFile = $(If ($LogDirectory -ne '') { '<logFile directory="{0}" />' -f $LogDirectory } Else { '' })
  $Defaults = $(If ($DefaultLogDirectory -ne '') { '<siteDefaults><logFile directory="{0}" /></siteDefaults>' -f $DefaultLogDirectory } Else { '' })
  $Remote = $(If ($RemoteAdministration) { '<application path="/ApiRemoting30" applicationPool="{0}"><virtualDirectory path="/" physicalPath="{1}\ApiRemoting30" /></application>' -f $Pool, $PhysicalPath } Else { '' })
  $Module = $(If ($HttpLogging) { '<add name="HttpLoggingModule" image="%windir%\System32\inetsrv\loghttp.dll" />' } Else { '' })
  [System.Xml.XmlDocument]$Document = [System.Xml.XmlDocument]::new()
  $Document.LoadXml(@"
<configuration>
  <system.applicationHost>
    <applicationPools>
      <add name="DefaultAppPool" />
      <add name="$Pool" $PoolAttributes>
        <processModel $ProcessModel />
        <recycling><periodicRestart $PeriodicRestart /></recycling>
      </add>
      <applicationPoolDefaults $PoolDefaults><processModel identityType="ApplicationPoolIdentity" /></applicationPoolDefaults>
    </applicationPools>
    <sites>
      <site name="Default Web Site" id="1">
        <application path="/"><virtualDirectory path="/" physicalPath="%SystemDrive%\inetpub\wwwroot" /></application>
        <bindings><binding protocol="http" bindingInformation="*:80:" /></bindings>
      </site>
      <site name="$SiteName" id="$SiteId">
        <application path="/" applicationPool="$Pool"><virtualDirectory path="/" physicalPath="$PhysicalPath" /></application>
        $Remote
        <bindings><binding protocol="http" bindingInformation="*:8530:" />$Https</bindings>
        $LogFile
      </site>
      $ExtraSites
      $Defaults
    </sites>
  </system.applicationHost>
  <system.webServer><globalModules><add name="StaticFileModule" />$Module</globalModules></system.webServer>
</configuration>
"@)
  $Document
}

# Registry keys of a healthy server, keyed by view and path, for a stand-in of
#   Get-MaintenanceRegistryKey: strong cryptography set in both views and a certificate bound in
#   HTTP.sys to -Port.
Function New-FakeRegistry {
  Param ([System.Int32]$Port = 8531, [System.Object]$StrongCrypto = 1)

  $Framework = 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
  $Bindings = 'SYSTEM\CurrentControlSet\Services\HTTP\Parameters\SslBindingInfo'
  @{
    ('Registry64|{0}' -f $Framework)                = [PSCustomObject]@{ SubKeys = @(); Values = @{ SchUseStrongCrypto = $StrongCrypto; SystemDefaultTlsVersions = $StrongCrypto } }
    ('Registry32|{0}' -f $Framework)                = [PSCustomObject]@{ SubKeys = @(); Values = @{ SchUseStrongCrypto = $StrongCrypto; SystemDefaultTlsVersions = $StrongCrypto } }
    ('Registry64|{0}' -f $Bindings)                 = [PSCustomObject]@{ SubKeys = @(('0.0.0.0:{0}' -f $Port)); Values = @{} }
    ('Registry64|{0}\0.0.0.0:{1}' -f $Bindings, $Port) = [PSCustomObject]@{ SubKeys = @(); Values = @{ SslCertHash = [System.Byte[]]@(0xAB, 0xCD, 0xEF); SslCertStoreName = 'MY' } }
  }
}
