#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Remove-BackupFile.Failed' = '{0} could not be deleted: {1}'
}

Function Remove-BackupFile {
  <#
    .SYNOPSIS
        Applies the backup retention to the backup files this script created.

    .DESCRIPTION
        Looks only at the top level of the backup folder and only at files named
        <database>_<yyyyMMdd>.bak, the names this script gives its backups; any other file and every
        sub-folder is left alone. The newest backup.minimumKept files are always kept. A file is past the
        maximum age when it is backup.maximumAgeDays or more days old by the date in its name. With both
        limits set, a file is deleted only when it is outside the kept set and past the maximum age;
        with one limit set, that limit alone decides; with neither, every file is kept and NoPolicy is
        set so the caller can raise a notice. A file that cannot be deleted is reported in Errors. With
        -DryRun nothing is deleted and Deleted lists what would be.

    .PARAMETER Database
        Database name, the prefix of the backup files.

    .PARAMETER DryRun
        Report without deleting.

    .PARAMETER Folder
        Backup folder, already expanded.

    .PARAMETER MaximumAgeDays
        Maximum age in days; 0 means no age limit.

    .PARAMETER MinimumKept
        Most recent files always kept; 0 means no minimum.

    .PARAMETER Now
        The run start, local.

    .EXAMPLE
        Remove-BackupFile -Folder 'H:\SUSDB' -Database 'SUSDB' -MinimumKept 7 -MaximumAgeDays 7 -Now (Get-MaintenanceTime)

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#remove-backupfile',
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
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Database,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Boolean]
    $DryRun = $False,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Folder,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 3650)]
    [System.Int32]
    $MaximumAgeDays,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateRange(0, 1000)]
    [System.Int32]
    $MinimumKept,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.DateTime]
    $Now
  )

  Write-Debug -Message:'[Remove-BackupFile] Entering'

  # Initialize Variable(s)
  [System.DateTime]$Private:Date = [System.DateTime]::MinValue
  [System.Boolean]$Private:Delete = $False
  [System.Collections.Generic.List[System.String]]$Private:Deleted = $Null
  [System.Collections.Generic.List[System.String]]$Private:Errors = $Null
  [PSCustomObject]$Private:File = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Files = $Null
  [System.Int64]$Private:Freed = 0
  [System.Boolean]$Private:InKeptSet = $False
  [System.Text.RegularExpressions.Match]$Private:Match = $Null
  [System.Boolean]$Private:NoPolicy = $False
  [System.Object[]]$Private:Ordered = @()
  [System.Boolean]$Private:PastAge = $False
  [System.String]$Private:Pattern = [System.String]::Empty
  [System.Int64]$Private:Size = 0
  [PSCustomObject]$Private:Result = $Null

  $Deleted = [System.Collections.Generic.List[System.String]]::new()
  $Errors = [System.Collections.Generic.List[System.String]]::new()
  $Files = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Pattern = '^{0}_(?<date>[0-9]{{8}})\.bak$' -f [System.Text.RegularExpressions.Regex]::Escape($Database)

  If ([System.IO.Directory]::Exists($Folder) -eq $True) {
    ForEach ($Path In [System.IO.Directory]::GetFiles($Folder)) {
      $Match = [System.Text.RegularExpressions.Regex]::Match([System.IO.Path]::GetFileName($Path), $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      $Date = [System.DateTime]::MinValue
      If (($Match.Success -eq $True) -and ([System.DateTime]::TryParseExact($Match.Groups['date'].Value, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Date) -eq $True)) {
        $Files.Add([PSCustomObject]@{ Path = $Path; Date = $Date })
      }
    }
  }

  $Ordered = @($Files | Sort-Object -Property:@{ Expression = 'Date'; Descending = $True }, @{ Expression = 'Path'; Descending = $True })
  $NoPolicy = ($MinimumKept -eq 0) -and ($MaximumAgeDays -eq 0)

  For ($Index = 0; $Index -lt $Ordered.Count; $Index++) {
    $File = $Ordered[$Index]
    $InKeptSet = ($MinimumKept -gt 0) -and ($Index -lt $MinimumKept)
    $PastAge = ($MaximumAgeDays -gt 0) -and ((($Now.Date - $File.Date.Date).TotalDays) -ge $MaximumAgeDays)

    If ($NoPolicy -eq $True) {
      $Delete = $False
    } ElseIf (($MinimumKept -gt 0) -and ($MaximumAgeDays -gt 0)) {
      $Delete = ($InKeptSet -eq $False) -and ($PastAge -eq $True)
    } ElseIf ($MinimumKept -gt 0) {
      $Delete = $InKeptSet -eq $False
    } Else {
      $Delete = $PastAge
    }

    If ($Delete -eq $True) {
      Try {
        $Size = [System.IO.FileInfo]::new($File.Path).Length
        If ($DryRun -eq $False) {
          [System.IO.File]::Delete($File.Path)
        }

        $Deleted.Add([System.IO.Path]::GetFileName($File.Path))
        $Freed = $Freed + $Size
      } Catch {
        $Errors.Add(($Script:Message['Remove-BackupFile.Failed'] -f [System.IO.Path]::GetFileName($File.Path), $PSItem.Exception.GetBaseException().Message))
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Deleted    = [System.String[]]$Deleted.ToArray()
    FreedBytes = [System.Int64]$Freed
    Kept       = [System.Int32]($Ordered.Count - $Deleted.Count - $Errors.Count)
    Errors     = [System.String[]]$Errors.ToArray()
    NoPolicy   = [System.Boolean]$NoPolicy
  }

  $Result
  Write-Debug -Message:'[Remove-BackupFile] Exiting'
}
