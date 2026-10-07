#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Invoke-SusdbCommand' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')
  }

  BeforeEach {
    $script:Clock = [System.DateTime]::new(2026, 11, 2, 1, 0, 0)
    Mock -CommandName Get-MaintenanceTime -MockWith { $script:Clock = $script:Clock.AddSeconds(2.5); $script:Clock }
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'returns the rows as objects, with database nulls as null' {
    $Connection = New-FakeSqlConnection -Rows @([PSCustomObject]@{ Name = 'a'; Count = 1 }, [PSCustomObject]@{ Name = $Null; Count = 2 })

    $Rows = @(Invoke-SusdbCommand -Connection $Connection -CommandText 'SELECT Name, Count FROM t')

    $Rows | Should -HaveCount 2
    $Rows[0].Name | Should -Be 'a'
    $Rows[1].Name | Should -BeNullOrEmpty
    $Rows[1].Count | Should -Be 2
  }

  It 'returns nothing for a query without rows' {
    @(Invoke-SusdbCommand -Connection (New-FakeSqlConnection) -CommandText 'SELECT 1 WHERE 1 = 0') | Should -HaveCount 0
  }

  It 'passes the text, the time-out and every parameter, with null as a database null' {
    $Connection = New-FakeSqlConnection -Affected 3

    $Affected = Invoke-SusdbCommand -Connection $Connection -CommandText 'DELETE FROM t WHERE a = @a AND b = @b' -Parameter @{ b = $Null; a = 7 } -TimeoutSeconds 0 -NonQuery

    $Affected | Should -Be 3
    $Connection.Commands[0].CommandText | Should -Be 'DELETE FROM t WHERE a = @a AND b = @b'
    $Connection.Commands[0].CommandTimeout | Should -Be 0
    @($Connection.Commands[0].Parameters.Values.Keys) | Should -Be @('@a', '@b')
    $Connection.Commands[0].Parameters.Values['@a'] | Should -Be 7
    $Connection.Commands[0].Parameters.Values['@b'] | Should -Be ([System.DBNull]::Value)
  }

  It 'writes what the command prints to the run log and detaches its handler' {
    $Connection = New-FakeSqlConnection -InfoMessages @('Estimating fragmentation: Begin.', 'Done.')

    $Null = Invoke-SusdbCommand -Connection $Connection -CommandText 'EXEC dbo.spReindex' -Log $script:Log

    $Lines = @(Get-Content -LiteralPath $script:Log.Path)
    $Lines | Should -HaveCount 2
    $Lines[0] | Should -BeLike '*SQL Server: Estimating fragmentation: Begin.'
    $Connection.Handlers | Should -HaveCount 0
  }

  It 'rethrows a failure with the time the command ran, after logging its messages' {
    $Connection = New-FakeSqlConnection -InfoMessages @('Started.') -Failure 'Execution Timeout Expired.'

    { Invoke-SusdbCommand -Connection $Connection -CommandText 'EXEC dbo.spSlow' -Log $script:Log } |
      Should -Throw -ExpectedMessage 'The database command failed after 2.5 s: Execution Timeout Expired.'
    (Get-Content -LiteralPath $script:Log.Path -Raw) | Should -Match 'SQL Server: Started\.'
    $Connection.Handlers | Should -HaveCount 0
  }

  It 'creates a handler that collects messages into an emptied collector' {
    $Collector = [System.Collections.Generic.List[System.String]]::new()
    $Collector.Add('stale')

    $Handler = New-SusdbMessageHandler -Collector $Collector
    & $Handler $Null ([PSCustomObject]@{ Message = 'fresh' })

    $Collector | Should -Be @('fresh')
  }
}
