#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Set-DeleteUpdateProcedureFix.AfterLog'         = 'spDeleteUpdate after the fix: {0}'
  'Set-DeleteUpdateProcedureFix.AlreadyApplied'   = 'already applied'
  'Set-DeleteUpdateProcedureFix.Applied'          = 'applied'
  'Set-DeleteUpdateProcedureFix.BeforeLog'        = 'spDeleteUpdate before the fix: {0}'
  'Set-DeleteUpdateProcedureFix.Failed'           = 'failed: {0}'
  'Set-DeleteUpdateProcedureFix.FailedNotice'     = 'The spDeleteUpdate fix could not be checked or applied: {0}. Obsolete-update deletion still runs.'
  'Set-DeleteUpdateProcedureFix.NotFound'         = 'dbo.spDeleteUpdate was not found or its definition cannot be read'
  'Set-DeleteUpdateProcedureFix.NotVerified'      = 'the altered definition does not carry the fix'
  'Set-DeleteUpdateProcedureFix.UnexpectedNotice' = 'dbo.spDeleteUpdate does not have the text the published fix expects, so it was left untouched.'
  'Set-DeleteUpdateProcedureFix.Untouched'        = 'left untouched: unexpected definition'
  'Set-DeleteUpdateProcedureFix.WouldApply'       = 'would apply'
}

Function Set-DeleteUpdateProcedureFix {
  <#
    .SYNOPSIS
        Applies Microsoft's fix for the slow spDeleteUpdate procedure when it is missing.

    .DESCRIPTION
        Runs before obsolete-update deletion on every run, because WSUS servicing can restore the
        original procedure. Reads the live definition of dbo.spDeleteUpdate and classifies it with
        ConvertTo-DeleteUpdateFix. Already applied: nothing changes. Missing: the definition before the
        change is written to the run log, the procedure is altered with exactly Microsoft's change
        (ANSI_NULLS and QUOTED_IDENTIFIER on, as in Microsoft's script), read back, and the definition
        after the change is written to the run log. Unexpected text, or a definition that cannot be read
        or altered, raises a Warning notice and leaves the procedure untouched; obsolete-update deletion
        still runs. No other object definition is ever altered. A dry run only reports.

    .PARAMETER Context
        The stage context.

    .EXAMPLE
        Set-DeleteUpdateProcedureFix -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#set-deleteupdateprocedurefix',
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

  Write-Debug -Message:'[Set-DeleteUpdateProcedureFix] Entering'

  # Initialize Variable(s)
  [System.String]$Private:After = [System.String]::Empty
  [System.String]$Private:Before = [System.String]::Empty
  [System.Collections.Specialized.OrderedDictionary]$Private:Counts = $Null
  [System.Object]$Private:Database = $Null
  [System.String]$Private:DefinitionQuery = 'SELECT OBJECT_DEFINITION(OBJECT_ID(N''dbo.spDeleteUpdate'')) AS Definition'
  [PSCustomObject]$Private:Fix = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Notices = [System.Collections.Generic.List[PSCustomObject]]::new()
  [System.String]$Private:Status = 'Success'
  [System.String]$Private:Summary = [System.String]::Empty
  [System.Int32]$Private:Timeout = 0
  [PSCustomObject]$Private:Result = $Null

  $Database = Get-SusdbConnection -Context:$Context
  $Timeout = [System.Int32](Get-MaintenancePropertyValue -InputObject:$Context.Server -Name:'CommandTimeoutSeconds' -Default:0)
  $Counts = [System.Collections.Specialized.OrderedDictionary]::new()
  $Counts['Applied'] = 0
  $Counts['AlreadyApplied'] = 0

  Try {
    $Before = [System.String](@(Invoke-SusdbCommand -CommandText:$DefinitionQuery -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout) | Select-Object -First:1).Definition
    If ([System.String]::IsNullOrWhiteSpace($Before) -eq $True) {
      Throw $Script:Message['Set-DeleteUpdateProcedureFix.NotFound']
    }

    $Fix = ConvertTo-DeleteUpdateFix -Definition:$Before
    Switch ($Fix.State) {
      'Applied' {
        $Counts['AlreadyApplied'] = 1
        $Summary = $Script:Message['Set-DeleteUpdateProcedureFix.AlreadyApplied']
      }
      'Missing' {
        If ($Context.DryRun -eq $True) {
          $Summary = $Script:Message['Set-DeleteUpdateProcedureFix.WouldApply']
        } Else {
          Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Set-DeleteUpdateProcedureFix.BeforeLog'] -f $Before) -Stage:'DeleteUpdateFix'
          $Null = Invoke-SusdbCommand -CommandText:'SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;' -Connection:$Database -Log:$Context.Log -NonQuery -TimeoutSeconds:$Timeout
          $Null = Invoke-SusdbCommand -CommandText:$Fix.Definition -Connection:$Database -Log:$Context.Log -NonQuery -TimeoutSeconds:$Timeout
          $After = [System.String](@(Invoke-SusdbCommand -CommandText:$DefinitionQuery -Connection:$Database -Log:$Context.Log -TimeoutSeconds:$Timeout) | Select-Object -First:1).Definition
          Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Set-DeleteUpdateProcedureFix.AfterLog'] -f $After) -Stage:'DeleteUpdateFix'
          If ((ConvertTo-DeleteUpdateFix -Definition:$After).State -ne 'Applied') {
            Throw $Script:Message['Set-DeleteUpdateProcedureFix.NotVerified']
          }

          $Counts['Applied'] = 1
          $Summary = $Script:Message['Set-DeleteUpdateProcedureFix.Applied']
        }
      }
      Default {
        $Status = 'Warning'
        $Summary = $Script:Message['Set-DeleteUpdateProcedureFix.Untouched']
        $Notices.Add((New-MaintenanceNotice -Message:$Script:Message['Set-DeleteUpdateProcedureFix.UnexpectedNotice'] -Severity:'Warning' -Stage:'DeleteUpdateFix'))
      }
    }
  } Catch {
    $Status = 'Warning'
    $Summary = $Script:Message['Set-DeleteUpdateProcedureFix.Failed'] -f $PSItem.Exception.Message
    $Notices.Add((New-MaintenanceNotice -Message:($Script:Message['Set-DeleteUpdateProcedureFix.FailedNotice'] -f $PSItem.Exception.Message) -Severity:'Warning' -Stage:'DeleteUpdateFix'))
  }

  [PSCustomObject]$Result = New-MaintenanceStageResult -Counts:$Counts -Message:$Summary -Notice:$Notices.ToArray() -Status:$Status

  $Result
  Write-Debug -Message:'[Set-DeleteUpdateProcedureFix] Exiting'
}
