#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Initialize-MaintenanceFolder.NotProtected' = 'the folder was created, but its access control list does not match the protected form: {0} can change it'
  'Initialize-MaintenanceFolder.NotRooted'    = "'{0}' is not an absolute path on this host."
  'Initialize-MaintenanceFolder.Overridden'   = "The folder '{0}' can be changed by {1}, not only by SYSTEM, Administrators and the run identity; it is used because run.permissiveFolderOverride is set."
  'Initialize-MaintenanceFolder.Permissive'   = 'it can be changed by {0}, not only by SYSTEM, Administrators and the run identity, so the run does not use it'
}

Function Initialize-MaintenanceFolder {
  <#
    .SYNOPSIS
        Makes sure a folder exists, is protected and can be written.

    .DESCRIPTION
        Expands environment variables in the path, creates the folder if it is missing, and writes and
        deletes a probe file to prove that the run identity can write to it. A path that is not
        absolute on this host (for example a Windows path on another platform, or an unexpanded
        variable) is refused without touching the file system.

        With -Protect, on a host with access control lists, every missing level of the path is created
        with a protected access control list: inheritance off and full control for SYSTEM,
        Administrators, the run identity and the -Grant identities only (New-MaintenanceProtectedFolder),
        and the result is verified. An existing folder is never changed: when principals other than the
        trusted ones can change it (Test-MaintenancePathProtection), it is refused before anything is
        written to it, unless -AllowPermissive is given, which uses it with a warning.

        Returns the expanded path, the reason the folder cannot be used (empty when it can), whether it
        was refused for its permissions, and the warning for a permissive folder used on purpose.

    .PARAMETER AllowPermissive
        Use an existing folder that other principals can change, with a warning (run.permissiveFolderOverride).

    .PARAMETER Grant
        Further identities given full control of the levels this creates, for example the SQL Server service.

    .PARAMETER Path
        Configured folder; may start with one %VARIABLE%.

    .PARAMETER Protect
        Create missing levels protected and refuse a folder that other principals can change.

    .EXAMPLE
        Initialize-MaintenanceFolder -Path '%ProgramData%\NWarila\WsusMaintenance\Logs' -Protect

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#initialize-maintenancefolder',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $AllowPermissive,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Grant = @(),

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Path,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $Protect
  )

  Write-Debug -Message:'[Initialize-MaintenanceFolder] Entering'

  # Initialize Variable(s)
  [PSCustomObject]$Private:Check = $Null
  [System.String]$Private:Cursor = [System.String]::Empty
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.Collections.Generic.List[System.String]]$Private:Missing = $Null
  [System.Boolean]$Private:Permissive = $False
  [System.String]$Private:Probe = [System.String]::Empty
  [System.String]$Private:Resolved = [System.String]::Empty
  [System.String[]]$Private:Trusted = @()
  [System.String]$Private:WarningText = [System.String]::Empty
  [PSCustomObject]$Private:Result = $Null

  $Resolved = Resolve-MaintenancePath -Path:$Path
  $Missing = [System.Collections.Generic.List[System.String]]::new()

  If ([System.IO.Path]::IsPathRooted($Resolved) -eq $False) {
    $ErrorText = $Script:Message['Initialize-MaintenanceFolder.NotRooted'] -f $Resolved
  } Else {
    Try {
      If (($Protect.IsPresent -eq $True) -and ((Test-MaintenanceAclSupport) -eq $True)) {
        $Trusted = Get-MaintenanceTrustedSid
        $Cursor = $Resolved
        While (([System.String]::IsNullOrEmpty($Cursor) -eq $False) -and ([System.IO.Directory]::Exists($Cursor) -eq $False)) {
          $Missing.Insert(0, $Cursor)
          $Cursor = [System.IO.Path]::GetDirectoryName($Cursor)
        }

        ForEach ($Level In $Missing) {
          New-MaintenanceProtectedFolder -Identity:([System.String[]]@($Trusted + $Grant)) -Path:$Level
        }

        $Check = Test-MaintenancePathProtection -Path:$Resolved -TrustedSid:$Trusted
        If ($Check.Permissive -eq $True) {
          If ($Missing.Count -gt 0) {
            Throw ($Script:Message['Initialize-MaintenanceFolder.NotProtected'] -f ($Check.Writers -join ', '))
          } ElseIf ($AllowPermissive.IsPresent -eq $True) {
            $WarningText = $Script:Message['Initialize-MaintenanceFolder.Overridden'] -f $Resolved, ($Check.Writers -join ', ')
          } Else {
            $Permissive = $True
            $ErrorText = $Script:Message['Initialize-MaintenanceFolder.Permissive'] -f ($Check.Writers -join ', ')
          }
        }
      }

      If ($Permissive -eq $False) {
        $Null = [System.IO.Directory]::CreateDirectory($Resolved)
        # A probe file proves the folder can be written, not just that it exists.
        $Probe = [System.IO.Path]::Combine($Resolved, ('.write-probe-{0}' -f [System.Guid]::NewGuid().ToString('N')))
        [System.IO.File]::WriteAllText($Probe, [System.String]::Empty)
        [System.IO.File]::Delete($Probe)
      }
    } Catch {
      $ErrorText = $PSItem.Exception.GetBaseException().Message
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Path       = [System.String]$Resolved
    Error      = [System.String]$ErrorText
    Permissive = [System.Boolean]$Permissive
    Warning    = [System.String]$WarningText
  }

  $Result
  Write-Debug -Message:'[Initialize-MaintenanceFolder] Exiting'
}
