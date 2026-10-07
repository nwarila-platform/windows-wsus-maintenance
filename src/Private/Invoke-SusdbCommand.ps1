#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# Message(s)
$Script:Message += @{
  'Invoke-SusdbCommand.Failed' = 'The database command failed after {0} s: {1}'
  'Invoke-SusdbCommand.Info'   = 'SQL Server: {0}'
}

Function Invoke-SusdbCommand {
  <#
    .SYNOPSIS
        Runs one parameterized command against SUSDB.

    .DESCRIPTION
        Creates the command on the open connection with the given text, a client-side time-out (zero
        means none, the default, so long Microsoft procedures can finish) and one parameter per hashtable
        entry, passed as @name. Returns the rows as objects, or the number of rows affected with
        -NonQuery. Messages the command prints are collected and written to the run log when it ends.
        A failure is rethrown with the time the command had been running, so a time-out reads as such in
        the stage error.

    .PARAMETER CommandText
        T-SQL text; values are passed as parameters, never concatenated.

    .PARAMETER Connection
        Open SUSDB connection (New-SqlConnection).

    .PARAMETER Log
        The run log, or null.

    .PARAMETER NonQuery
        Return the number of rows affected instead of rows.

    .PARAMETER Parameter
        Parameter values by name, without the @.

    .PARAMETER TimeoutSeconds
        Client-side command time-out; zero means none.

    .EXAMPLE
        Invoke-SusdbCommand -Connection $Database -CommandText 'SELECT COUNT(*) AS Total FROM dbo.tbUpdate WHERE IsHidden = @hidden' -Parameter @{ hidden = 0 }

    .OUTPUTS
        [System.Object]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#invoke-susdbcommand',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Object])]
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
    $CommandText,

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
    [System.Management.Automation.SwitchParameter]
    $NonQuery,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Collections.Hashtable]
    $Parameter = $Null,

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

  Write-Debug -Message:'[Invoke-SusdbCommand] Entering'

  # Initialize Variable(s)
  [System.Int32]$Private:Affected = 0
  [System.Object]$Private:Command = $Null
  [System.Double]$Private:FailedAfter = 0
  [System.String]$Private:Failure = [System.String]::Empty
  [System.Management.Automation.ScriptBlock]$Private:Handler = $Null
  [System.Collections.Generic.List[System.String]]$Private:Messages = $Null
  [System.Object]$Private:Reader = $Null
  [System.Collections.Specialized.OrderedDictionary]$Private:Row = $Null
  [System.Collections.Generic.List[PSCustomObject]]$Private:Rows = $Null
  [System.DateTime]$Private:Started = [System.DateTime]::MinValue
  [System.Object]$Private:Result = $Null

  $Messages = [System.Collections.Generic.List[System.String]]::new()
  $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()
  $Handler = New-SusdbMessageHandler -Collector:$Messages
  $Started = Get-MaintenanceTime
  $Connection.add_InfoMessage($Handler)

  Try {
    $Command = $Connection.CreateCommand()
    $Command.CommandText = $CommandText
    $Command.CommandTimeout = $TimeoutSeconds
    If ($Null -ne $Parameter) {
      ForEach ($Name In @($Parameter.Keys | Sort-Object)) {
        If ($Null -eq $Parameter[$Name]) {
          $Null = $Command.Parameters.AddWithValue(('@{0}' -f $Name), [System.DBNull]::Value)
        } Else {
          $Null = $Command.Parameters.AddWithValue(('@{0}' -f $Name), $Parameter[$Name])
        }
      }
    }

    If ($NonQuery.IsPresent -eq $True) {
      $Affected = [System.Int32]$Command.ExecuteNonQuery()
    } Else {
      $Reader = $Command.ExecuteReader()
      Try {
        While ($Reader.Read() -eq $True) {
          $Row = [System.Collections.Specialized.OrderedDictionary]::new()
          For ($Index = 0; $Index -lt $Reader.FieldCount; $Index++) {
            If ($Reader.IsDBNull($Index) -eq $True) {
              $Row[$Reader.GetName($Index)] = $Null
            } Else {
              $Row[$Reader.GetName($Index)] = $Reader.GetValue($Index)
            }
          }

          $Rows.Add([PSCustomObject]$Row)
        }
      } Finally {
        $Reader.Dispose()
      }
    }
  } Catch {
    $Failure = $PSItem.Exception.GetBaseException().Message
    $FailedAfter = [System.Math]::Max([System.Double]0, ((Get-MaintenanceTime) - $Started).TotalSeconds)
  } Finally {
    $Connection.remove_InfoMessage($Handler)
    ForEach ($Line In $Messages) {
      Write-MaintenanceLog -Level:'Information' -Log:$Log -Message:($Script:Message['Invoke-SusdbCommand.Info'] -f $Line)
    }
  }

  If ([System.String]::IsNullOrEmpty($Failure) -eq $False) {
    Throw ($Script:Message['Invoke-SusdbCommand.Failed'] -f $FailedAfter.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $Failure)
  }

  If ($NonQuery.IsPresent -eq $True) {
    [System.Object]$Result = $Affected
  } Else {
    [System.Object]$Result = [PSCustomObject[]]$Rows.ToArray()
  }

  $Result
  Write-Debug -Message:'[Invoke-SusdbCommand] Exiting'
}
