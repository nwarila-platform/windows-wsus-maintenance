#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Backup-Susdb.DrySummary'         = 'Would back up SUSDB to {0} and delete {1} old backup file(s).'
  'Backup-Susdb.Failed'             = 'The SUSDB backup to {0} failed: {1}'
  'Backup-Susdb.Folder'             = 'the backup folder cannot be used: {0}'
  'Backup-Susdb.FailedSummary'      = 'backup failed'
  'Backup-Susdb.NoFile'             = 'the file is not there'
  'Backup-Susdb.NoPolicy'           = 'Backup retention is off (backup.minimumKept and backup.maximumAgeDays are both 0), so every backup file is kept.'
  'Backup-Susdb.NoSpace'            = 'The SUSDB backup was skipped: {0} has {1} bytes free, and the estimated backup needs {2} bytes including the {3}% margin.'
  'Backup-Susdb.NoSpaceSummary'     = 'skipped: not enough free space'
  'Backup-Susdb.RetentionFailed'    = 'Backup retention: {0}'
  'Backup-Susdb.SetName'            = '{0} full backup {1}'
  'Backup-Susdb.SizeUnknown'        = 'The size of {0} could not be read: {1}'
  'Backup-Susdb.SpaceUnknown'       = 'The free space of {0} could not be read ({1}); the backup was attempted without the free-space check.'
  'Backup-Susdb.Summary'            = 'Backup set "{0}" written to {1} ({2} bytes, {3}, with checksum); {4} old backup file(s) deleted.'
  'Backup-Susdb.WithCompression'    = 'compressed'
  'Backup-Susdb.WithoutCompression' = 'uncompressed'
}

Function Backup-Susdb {
  <#
    .SYNOPSIS
        Creates the nightly full SUSDB backup and applies the backup retention.

    .DESCRIPTION
        Writes a full backup of SUSDB with checksums to backup.destination\<database>_<yyyyMMdd>.bak,
        so there is at most one file per calendar day; a second backup on the same day replaces it
        (backup.sameDay Replace, WITH INIT) or is appended to it (Append, WITH NOINIT). Compression
        follows backup.compression: Auto compresses on the editions that support backup compression
        (Enterprise, Standard and Developer), Always and Never force it. Before the backup the size is
        estimated from the space the database has reserved, and the destination must have that much
        free space plus backup.freeSpaceMarginPercent; otherwise the backup is skipped with a High
        notice. The folder is created when it is missing, protected: full control for SYSTEM,
        Administrators, the run identity and the SQL Server service that writes the file, and nobody
        else. An existing folder that other principals can change is not used (unless
        run.permissiveFolderOverride is set), which fails the backup. A failed backup raises a High
        notice and ends the stage in error; the backup gate then holds back the stages that alter SUSDB. After a
        successful backup, Remove-BackupFile applies the retention. A dry run checks the space and
        reports what it would do.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Backup-Susdb -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#backup-susdb',
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
    $Context
  )

  Write-Debug -Message:'[Backup-Susdb] Entering'

  # Initialize Variable(s)
  [System.Boolean]$Private:Compress = $False
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Object]$Private:Database = $Null
  [System.String]$Private:DatabaseName = [System.String]::Empty
  [System.Object]$Private:Facts = $Null
  [System.IO.FileInfo]$Private:File = $Null
  [System.String]$Private:FactsQuery = 'SELECT CAST(SERVERPROPERTY(''Edition'') AS NVARCHAR(128)) AS Edition, (SELECT CAST(SUM(reserved_page_count) AS BIGINT) * 8192 FROM sys.dm_db_partition_stats) AS ReservedBytes'
  [System.String]$Private:Folder = [System.String]::Empty
  [System.Int64]$Private:Free = 0
  [System.String[]]$Private:Items = @()
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.String]$Private:Path = [System.String]::Empty
  [PSCustomObject]$Private:Prepared = $Null
  [PSCustomObject]$Private:Preview = $Null
  [System.Int64]$Private:Required = 0
  [PSCustomObject]$Private:Retention = $Null
  [System.String]$Private:SetName = [System.String]::Empty
  [System.Object]$Private:Settings = $Null
  [System.String]$Private:Statement = [System.String]::Empty
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Int32]$Private:Timeout = 0
  [PSCustomObject]$Private:Result = $Null

  $Database = Get-SusdbConnection -Context:$Context
  $Timeout = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0)
  $Settings = $Context.Configuration.backup
  $DatabaseName = [System.String]$Context.Server.Environment.DatabaseName
  $Folder = Resolve-MaintenancePath -Path:([System.String]$Settings.destination)
  $Path = [System.IO.Path]::Combine($Folder, ('{0}_{1}.bak' -f $DatabaseName, $Context.RunStart.ToString('yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)))
  $SetName = $Script:Message['Backup-Susdb.SetName'] -f $DatabaseName, $Context.RunStart.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Created', 'WouldCreate', 'EstimatedBytes', 'FreeBytes', 'SizeBytes', 'Compressed', 'Deleted', 'FreedBytes')) {
    $Counts[$Name] = [System.Int64]0
  }

  # Editions that support backup compression:
  #   https://learn.microsoft.com/sql/relational-databases/backup-restore/backup-compression-sql-server
  $Facts = @(Invoke-SusdbCommand -CommandText:$FactsQuery -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout) | Select-Object -First:1
  $Counts['EstimatedBytes'] = [System.Int64]$Facts.ReservedBytes
  Switch ([System.String]$Settings.compression) {
    'Always' { $Compress = $True }
    'Never' { $Compress = $False }
    Default { $Compress = [System.String]$Facts.Edition -match '^(?:Enterprise|Standard|Developer)' }
  }

  $Counts['Compressed'] = [System.Int64][System.Int32]$Compress

  $Required = [System.Int64][System.Math]::Ceiling([System.Double]$Counts['EstimatedBytes'] * (1 + ([System.Double]$Settings.freeSpaceMarginPercent / 100)))
  Try {
    $Free = Get-BackupDestinationSpace -Path:$Folder
    $Counts['FreeBytes'] = $Free
  } Catch {
    $Free = -1
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Backup-Susdb.SpaceUnknown'] -f $Folder, $PSItem.Exception.GetBaseException().Message) -Severity:'Information' -Stage:'Backup'))
  }

  If (($Free -ge 0) -and ($Free -lt $Required)) {
    $Status = 'Warning'
    $Summary = $Script:Message['Backup-Susdb.NoSpaceSummary']
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Backup-Susdb.NoSpace'] -f $Folder, $Free, $Required, $Settings.freeSpaceMarginPercent) -Severity:'High' -Stage:'Backup'))
  } ElseIf ($Context.DryRun -eq $True) {
    $Counts['WouldCreate'] = 1
    $Preview = Remove-BackupFile -Database:$DatabaseName -DryRun:$True -Folder:$Folder -MaximumAgeDays:([System.Int32]$Settings.maximumAgeDays) -MinimumKept:([System.Int32]$Settings.minimumKept) -Now:$Context.RunStart
    $Items = $Preview.Deleted
    $Summary = $Script:Message['Backup-Susdb.DrySummary'] -f $Path, $Preview.Deleted.Count
  } Else {
    Try {
      # The folder is created protected, with full control for the SQL Server service that
      #   writes the file, and an existing folder that other principals can change is not used
      #   unless run.permissiveFolderOverride allows it (REQ-092).
      $Prepared = Initialize-MaintenanceFolder -AllowPermissive:([System.Boolean]$Context.Configuration.run.permissiveFolderOverride) -Grant:(ConvertTo-SqlServiceAccount -SqlServerName:([System.String](Get-MaintenancePropertyValue -InputObject:$Context.Server.Environment -Name:'SqlServerName' -Default:''))) -Path:([System.String]$Settings.destination) -Protect
      If ([System.String]::IsNullOrEmpty($Prepared.Error) -eq $False) {
        Throw ($Script:Message['Backup-Susdb.Folder'] -f $Prepared.Error)
      }

      If ([System.String]::IsNullOrEmpty($Prepared.Warning) -eq $False) {
        $Notices.Add((New-MaintenanceNotice -Message:$Prepared.Warning -Severity:'Warning' -Stage:'Backup'))
      }

      $Statement = 'BACKUP DATABASE {0} TO DISK = @path WITH CHECKSUM, {1}, {2}, NAME = @name, STATS = 10' -f (ConvertTo-SqlIdentifier -Name:$DatabaseName), $(If ($Settings.sameDay -eq 'Append') { 'NOINIT' } Else { 'INIT' }), $(If ($Compress -eq $True) { 'COMPRESSION' } Else { 'NO_COMPRESSION' })
      $Null = Invoke-SusdbCommand -CommandText:$Statement -Connection:$Database -Log:$Context.Log -NonQuery -Parameter:@{ path = $Path; name = $SetName } -TimeoutSeconds:$Timeout
      $Counts['Created'] = 1
    } Catch {
      $Status = 'Error'
      $Summary = $Script:Message['Backup-Susdb.FailedSummary']
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Backup-Susdb.Failed'] -f $Path, $PSItem.Exception.Message) -Severity:'High' -Stage:'Backup'))
    }

    If ($Counts['Created'] -eq 1) {
      Try {
        $File = [System.IO.FileInfo]::new($Path)
        If ($File.Exists -eq $False) {
          Throw $Script:Message['Backup-Susdb.NoFile']
        }

        $Counts['SizeBytes'] = [System.Int64]$File.Length
      } Catch {
        Write-MaintenanceLog -Level:'Warning' -Log:$Context.Log -Message:($Script:Message['Backup-Susdb.SizeUnknown'] -f $Path, $PSItem.Exception.Message) -Stage:'Backup'
      }

      $Retention = Remove-BackupFile -Database:$DatabaseName -Folder:$Folder -MaximumAgeDays:([System.Int32]$Settings.maximumAgeDays) -MinimumKept:([System.Int32]$Settings.minimumKept) -Now:$Context.RunStart
      $Counts['Deleted'] = [System.Int64]$Retention.Deleted.Count
      $Counts['FreedBytes'] = $Retention.FreedBytes
      $Items = $Retention.Deleted
      If ($Retention.NoPolicy -eq $True) {
        $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Backup-Susdb.NoPolicy'] -Severity:'Information' -Stage:'Backup'))
      }

      ForEach ($RetentionError In $Retention.Errors) {
        $Status = 'Warning'
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Backup-Susdb.RetentionFailed'] -f $RetentionError) -Severity:'Warning' -Stage:'Backup'))
      }

      $Summary = $Script:Message['Backup-Susdb.Summary'] -f $SetName, $Path, $Counts['SizeBytes'], $(If ($Compress -eq $True) { $Script:Message['Backup-Susdb.WithCompression'] } Else { $Script:Message['Backup-Susdb.WithoutCompression'] }), $Retention.Deleted.Count
    }
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:$Items -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Backup-Susdb] Exiting'
}
