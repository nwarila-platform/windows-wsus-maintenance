#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Remove-IisLogFile.Budget'           = 'Time budget reached after deleting {0} IIS log file(s); the rest are deleted on the next run.'
  'Remove-IisLogFile.Deleted'          = 'deleted: {0}'
  'Remove-IisLogFile.DrySummary'       = 'pending: {0} IIS log file(s) older than {1} day(s) would be deleted from {2}.'
  'Remove-IisLogFile.Failed'           = 'failed: {0}: {1}'
  'Remove-IisLogFile.FailedNotice'     = '{0} IIS log file(s) could not be deleted and are retried on the next run. First failure: {1}'
  'Remove-IisLogFile.KeepAll'          = 'IIS log files in {0} are kept: iisLogs.maxAgeDays is 0.'
  'Remove-IisLogFile.NoFolder'         = 'IIS log retention deleted nothing: the folder {0} does not exist. Set iisLogs.folder if the WSUS website logs elsewhere.'
  'Remove-IisLogFile.NoFolderSummary'  = 'nothing deleted: the IIS log folder {0} does not exist'
  'Remove-IisLogFile.NoIis'            = 'IIS log retention deleted nothing: the IIS configuration could not be read ({0}).'
  'Remove-IisLogFile.NoIisSummary'     = 'nothing deleted: the IIS configuration could not be read'
  'Remove-IisLogFile.NoLogging'        = 'The IIS HTTP logging feature is not installed, so there are no IIS log files to remove; set iisLogs.enabled to false.'
  'Remove-IisLogFile.NoLoggingSummary' = 'skipped: the IIS HTTP logging feature is not installed'
  'Remove-IisLogFile.NoSite'           = 'IIS log retention deleted nothing: {0}. Set iisLogs.siteName to the WSUS website.'
  'Remove-IisLogFile.NoSiteSummary'    = 'nothing deleted: {0}'
  'Remove-IisLogFile.Override'         = 'IIS log folder from iisLogs.folder: {0}.'
  'Remove-IisLogFile.Pending'          = 'pending: {0}'
  'Remove-IisLogFile.Site'             = 'WSUS website {0} (identifier {1}) found {2}; IIS log folder {3}.'
  'Remove-IisLogFile.Summary'          = 'Deleted {0} IIS log file(s) older than {1} day(s) from {2}, {3} reclaimed; {4} kept, {5} failed.'
}

Function Remove-IisLogFile {
  <#
    .SYNOPSIS
        Deletes the WSUS website's IIS log files older than the maximum age.

    .DESCRIPTION
        Deletes the files with the .log extension directly in the WSUS website's IIS log folder whose
        last write time is more than iisLogs.maxAgeDays days before the run start, as Microsoft describes
        for managing IIS log storage. Other files and sub-folders are never touched, and zero days keeps
        every file. The folder is iisLogs.folder (environment variables expanded) or, without it, the log
        folder of the WSUS website (Find-WsusWebSite) in the IIS configuration, which the log names with
        how the site was found. When the IIS HTTP logging feature is not installed the stage does nothing
        and suggests turning it off; when the site or the folder cannot be found, or the site is
        ambiguous, nothing is deleted and the stage ends in error. A file that cannot be deleted (for
        example the log IIS is writing) is a warning. A dry run deletes nothing and lists the files.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Remove-IisLogFile -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#remove-iislogfile',
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

  Write-Debug -Message:'[Remove-IisLogFile] Entering'

  # Initialize Variable(s)
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.DateTime]$Private:Cutoff = [System.DateTime]::MinValue
  [System.Collections.Generic.List[System.String]]$Private:Failures = $Null
  [System.IO.FileInfo]$Private:File = $Null
  [System.String]$Private:Folder = [System.String]::Empty
  [System.Xml.XmlDocument]$Private:Iis = $Null
  [System.Collections.Generic.List[System.String]]$Private:Items = $Null
  [System.Int32]$Private:MaxAge = 0
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = $Null
  [System.Object]$Private:Settings = $Null
  [PSCustomObject]$Private:Site = $Null
  [System.Int64]$Private:Size = 0
  [System.String]$Private:Status = 'Success'
  [System.Boolean]$Private:Stopped = $False
  [System.String]$Private:Summary = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Settings = $Context.Configuration.iisLogs
  $MaxAge = [System.Int32]$Settings.maxAgeDays
  $Items = [System.Collections.Generic.List[System.String]]::new()
  $Failures = [System.Collections.Generic.List[System.String]]::new()
  $Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  ForEach ($Name In @('Found', 'Deleted', 'Pending', 'Kept', 'FreedBytes', 'Failed')) {
    $Counts[$Name] = [System.Int64]0
  }

  If ([System.String]::IsNullOrEmpty([System.String]$Settings.folder) -eq $False) {
    $Folder = Resolve-MaintenancePath -Path:([System.String]$Settings.folder)
    Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Remove-IisLogFile.Override'] -f $Folder) -Stage:$Context.StageName
  } Else {
    Try {
      $Iis = Get-IisConfiguration
    } Catch {
      $Status = 'Error'
      $Summary = $Script:Message['Remove-IisLogFile.NoIisSummary']
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-IisLogFile.NoIis'] -f $PSItem.Exception.GetBaseException().Message) -Severity:'Error' -Stage:$Context.StageName))
    }

    If ($Null -ne $Iis) {
      If ($Null -eq $Iis.SelectSingleNode("/configuration/system.webServer/globalModules/add[@name='HttpLoggingModule']")) {
        $Summary = $Script:Message['Remove-IisLogFile.NoLoggingSummary']
        $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Remove-IisLogFile.NoLogging'] -Severity:'Information' -Stage:$Context.StageName))
      } Else {
        $Site = Find-WsusWebSite -Iis:$Iis -Setup:(Get-WsusSetupValue) -SiteName:([System.String]$Settings.siteName)
        If ([System.String]::IsNullOrEmpty($Site.Error) -eq $False) {
          $Status = 'Error'
          $Summary = $Script:Message['Remove-IisLogFile.NoSiteSummary'] -f $Site.Error
          $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-IisLogFile.NoSite'] -f $Site.Error) -Severity:'Error' -Stage:$Context.StageName))
        } Else {
          If ([System.String]::IsNullOrEmpty($Site.Warning) -eq $False) {
            $Notices.Add((New-MaintenanceNotice -Message:$Site.Warning -Severity:'Warning' -Stage:$Context.StageName))
            Write-MaintenanceLog -Level:'Warning' -Log:$Context.Log -Message:$Site.Warning -Stage:$Context.StageName
          }

          $Folder = $Site.LogFolder
          Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Remove-IisLogFile.Site'] -f $Site.Name, $Site.Id, $Site.Method, $Folder) -Stage:$Context.StageName
        }
      }
    }
  }

  If ([System.String]::IsNullOrEmpty($Folder) -eq $False) {
    If ([System.IO.Directory]::Exists($Folder) -eq $False) {
      $Status = 'Error'
      $Summary = $Script:Message['Remove-IisLogFile.NoFolderSummary'] -f $Folder
      $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-IisLogFile.NoFolder'] -f $Folder) -Severity:'Error' -Stage:$Context.StageName))
    } ElseIf ($MaxAge -eq 0) {
      $Summary = $Script:Message['Remove-IisLogFile.KeepAll'] -f $Folder
    } Else {
      # Deleting aged log files is how Microsoft describes keeping IIS log storage in check:
      #   https://learn.microsoft.com/iis/manage/provisioning-and-managing-iis/managing-iis-log-file-storage
      $Cutoff = $Context.RunStart.ToUniversalTime().AddDays(-$MaxAge)
      ForEach ($Path In [System.IO.Directory]::GetFiles($Folder)) {
        If ([System.String]::Equals([System.IO.Path]::GetExtension($Path), '.log', [System.StringComparison]::OrdinalIgnoreCase) -eq $False) {
          Continue
        }

        $Counts['Found'] = $Counts['Found'] + 1
        $File = [System.IO.FileInfo]::new($Path)
        If ($File.LastWriteTimeUtc -ge $Cutoff) {
          $Counts['Kept'] = $Counts['Kept'] + 1
          Continue
        }

        If ($Context.DryRun -eq $True) {
          $Counts['Pending'] = $Counts['Pending'] + 1
          $Items.Add(($Script:Message['Remove-IisLogFile.Pending'] -f $File.Name))
          Continue
        }

        If ((Test-MaintenanceBudget -Deadline:$Context.Deadline) -eq $True) {
          $Stopped = $True
          Break
        }

        Try {
          $Size = $File.Length
          $File.Delete()
          $Counts['Deleted'] = $Counts['Deleted'] + 1
          $Counts['FreedBytes'] = $Counts['FreedBytes'] + $Size
          $Items.Add(($Script:Message['Remove-IisLogFile.Deleted'] -f $File.Name))
        } Catch {
          $Failures.Add(($Script:Message['Remove-IisLogFile.Failed'] -f $File.Name, $PSItem.Exception.GetBaseException().Message))
        }
      }

      $Counts['Failed'] = [System.Int64]$Failures.Count
      If ($Failures.Count -gt 0) {
        $Status = 'Warning'
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-IisLogFile.FailedNotice'] -f $Failures.Count, $Failures[0]) -Severity:'Warning' -Stage:$Context.StageName))
      }

      If ($Stopped -eq $True) {
        $Status = 'Warning'
        $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Remove-IisLogFile.Budget'] -f $Counts['Deleted']) -Severity:'Warning' -Stage:$Context.StageName))
      }

      If ($Context.DryRun -eq $True) {
        $Summary = $Script:Message['Remove-IisLogFile.DrySummary'] -f $Counts['Pending'], $MaxAge, $Folder
      } Else {
        $Summary = $Script:Message['Remove-IisLogFile.Summary'] -f $Counts['Deleted'], $MaxAge, $Folder, (ConvertTo-MaintenanceByteText -Bytes:$Counts['FreedBytes']), $Counts['Kept'], $Counts['Failed']
      }
    }
  }

  If (($Status -eq 'Success') -and (@($Notices | Where-Object -FilterScript:({ $PSItem.Severity -ne 'Information' })).Count -gt 0)) {
    $Status = 'Warning'
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Item:($Items.ToArray() + $Failures.ToArray()) -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Remove-IisLogFile] Exiting'
}
