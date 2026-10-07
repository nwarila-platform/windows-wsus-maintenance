#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Get-WsusUpdateRecord.Failed'         = 'The update list could not be retrieved: {0}'
  'Get-WsusUpdateRecord.Language'       = 'Update titles and category names are retrieved in language {0}.'
  'Get-WsusUpdateRecord.LanguageFailed' = 'The evaluation language {0} could not be set: {1}'
  'Get-WsusUpdateRecord.RestoreFailed'  = 'The previous language preference ''{0}'' could not be restored: {1}'
  'Get-WsusUpdateRecord.Retrieved'      = 'Retrieved {0} update(s) for evaluation.'
}

Function Get-WsusUpdateRecord {
  <#
    .SYNOPSIS
        Retrieves updates from WSUS in the evaluation language, as decline records.

    .DESCRIPTION
        Sets the connection's preferred language to declines.evaluationLanguage, so that titles and
        category names arrive in one fixed language whatever the server's display language, retrieves the
        updates (IUpdateServer.GetUpdates with an UpdateScope) and turns each into a decline record, then
        restores the previous language preference. Without -Declined it retrieves the updates that are
        not declined, in every other approval state (not approved, latest revision approved, stale
        approvals), limited to the declines.arrivalWindowDays window when one is set; with -Declined it
        retrieves the declined updates. A language that cannot be set is reported in LanguageError and the
        retrieval still runs; a retrieval that fails or times out is reported in Error with no records.

    .PARAMETER Context
        The stage context.

    .PARAMETER Declined
        Retrieve the declined updates instead of the undeclined ones.

    .EXAMPLE
        Get-WsusUpdateRecord -Context $Context

    .OUTPUTS
        [System.Management.Automation.PSCustomObject]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#get-wsusupdaterecord',
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
    $Context,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.SwitchParameter]
    $Declined
  )

  Write-Debug -Message:'[Get-WsusUpdateRecord] Entering'

  # Initialize Variable(s)
  [System.String]$Private:ErrorText = [System.String]::Empty
  [System.String]$Private:Language = [System.String]::Empty
  [System.String]$Private:LanguageError = [System.String]::Empty
  [System.Boolean]$Private:LanguageSet = $False
  [System.String]$Private:Previous = [System.String]::Empty
  [PSCustomObject]$Private:Record = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Records = $Null
  [System.Object]$Private:Scope = $Null
  [System.Object]$Private:UpdateServer = $Null
  [System.Int32]$Private:Window = 0
  [PSCustomObject]$Private:Result = $Null

  $UpdateServer = Get-WsusConnection -Context:$Context
  $Language = [System.String]$Context.Configuration.declines.evaluationLanguage
  $Window = [System.Int32]$Context.Configuration.declines.arrivalWindowDays
  $Records = [System.Collections.Generic.List[PSCustomObject]]::new()

  # The preferred culture governs the language of returned strings and is set per connection:
  #   https://learn.microsoft.com/previous-versions/windows/desktop/ms751963(v=vs.85)
  Try {
    $Previous = [System.String]$UpdateServer.PreferredCulture
    $UpdateServer.PreferredCulture = $Language
    $LanguageSet = $True
    Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Get-WsusUpdateRecord.Language'] -f $Language) -Stage:$Context.StageName
  } Catch {
    $LanguageError = $PSItem.Exception.GetBaseException().Message
    Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Get-WsusUpdateRecord.LanguageFailed'] -f $Language, $LanguageError) -Stage:$Context.StageName
  }

  Try {
    $Scope = New-WsusAdministrationObject -TypeName:'UpdateScope'
    If ($Declined.IsPresent -eq $True) {
      $Scope.ApprovedStates = 'Declined'
    } Else {
      $Scope.ApprovedStates = 'NotApproved, LatestRevisionApproved, HasStaleUpdateApprovals'
      If ($Window -gt 0) {
        $Scope.FromArrivalDate = $Context.RunStart.ToUniversalTime().AddDays(-$Window)
      }
    }

    ForEach ($Update In @($UpdateServer.GetUpdates($Scope))) {
      $Record = ConvertTo-DeclineRecord -Update:$Update
      If ($Record.IsDeclined -eq $Declined.IsPresent) {
        $Records.Add($Record)
      }
    }

    Write-MaintenanceLog -Level:'Information' -Log:$Context.Log -Message:($Script:Message['Get-WsusUpdateRecord.Retrieved'] -f $Records.Count) -Stage:$Context.StageName
  } Catch {
    $ErrorText = $PSItem.Exception.GetBaseException().Message
    $Records.Clear()
    Write-MaintenanceLog -Level:'Error' -Log:$Context.Log -Message:($Script:Message['Get-WsusUpdateRecord.Failed'] -f $ErrorText) -Stage:$Context.StageName
  } Finally {
    If ($LanguageSet -eq $True) {
      Try {
        $UpdateServer.PreferredCulture = $Previous
      } Catch {
        Write-MaintenanceLog -Level:'Warning' -Log:$Context.Log -Message:($Script:Message['Get-WsusUpdateRecord.RestoreFailed'] -f $Previous, $PSItem.Exception.Message) -Stage:$Context.StageName
      }
    }
  }

  [PSCustomObject]$Result = [PSCustomObject]@{
    Records       = $Records
    Error         = [System.String]$ErrorText
    LanguageError = [System.String]$LanguageError
    Language      = [System.String]$Language
  }

  $Result
  Write-Debug -Message:'[Get-WsusUpdateRecord] Exiting'
}
