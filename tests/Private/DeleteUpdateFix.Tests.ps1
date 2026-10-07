#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

# The procedure texts below are short stand-ins with the shape the fix works on, not the
#   product's own definition.
BeforeAll {
  . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  . (Join-Path -Path $PSScriptRoot -ChildPath '../Helpers/MaintenanceFakes.ps1')

  $script:Original = @(
    'CREATE PROCEDURE dbo.spDeleteUpdate'
    '    @localUpdateID int'
    'AS'
    'SET NOCOUNT ON'
    'DECLARE @revisionList TABLE(RevisionID INT)'
    'INSERT INTO @revisionList (RevisionID) SELECT RevisionID FROM dbo.tbRevision WHERE LocalUpdateID = @localUpdateID'
    'RETURN(0)'
  ) -join "`n"
  $script:Fixed = $script:Original.Replace('TABLE(RevisionID INT)', 'TABLE(RevisionID INT PRIMARY KEY)')
}

Describe 'ConvertTo-DeleteUpdateFix' {
  It 'adds the primary key and turns CREATE into ALTER, changing nothing else' {
    $Fix = ConvertTo-DeleteUpdateFix -Definition $script:Original

    $Fix.State | Should -Be 'Missing'
    $Fix.Definition | Should -BeExactly $script:Fixed.Replace('CREATE PROCEDURE', 'ALTER PROCEDURE')
  }

  It 'keeps leading comments, spacing and letter case' {
    $Definition = "/* maintained by the product */`r`n-- keep`r`ncreate proc dbo.spDeleteUpdate @localUpdateID int AS`r`ndeclare  @revisionList  table ( RevisionID  int )`r`n-- CREATE PROCEDURE in a comment stays"

    $Fix = ConvertTo-DeleteUpdateFix -Definition $Definition

    $Fix.State | Should -Be 'Missing'
    $Fix.Definition | Should -BeExactly "/* maintained by the product */`r`n-- keep`r`nALTER PROCEDURE dbo.spDeleteUpdate @localUpdateID int AS`r`ndeclare  @revisionList  table ( RevisionID  int PRIMARY KEY )`r`n-- CREATE PROCEDURE in a comment stays"
  }

  It 'recognises the fix already in place' {
    $Fix = ConvertTo-DeleteUpdateFix -Definition $script:Fixed.Replace('TABLE(RevisionID INT PRIMARY KEY)', 'TABLE (RevisionID int primary key)')

    $Fix.State | Should -Be 'Applied'
    $Fix.Definition | Should -Be ''
  }

  It 'refuses <Case>' -ForEach @(
    @{ Case = 'a definition without the declaration'; Definition = 'CREATE PROCEDURE dbo.spDeleteUpdate AS RETURN(0)' }
    @{ Case = 'two declarations'; Definition = "CREATE PROCEDURE p AS`nDECLARE @revisionList TABLE(RevisionID INT)`nDECLARE @revisionList TABLE(RevisionID INT)" }
    @{ Case = 'a declaration with and one without the key'; Definition = "CREATE PROCEDURE p AS`nDECLARE @revisionList TABLE(RevisionID INT)`nDECLARE @revisionList TABLE(RevisionID INT PRIMARY KEY)" }
    @{ Case = 'text before the header'; Definition = "SET ANSI_NULLS ON`nCREATE PROCEDURE p AS`nDECLARE @revisionList TABLE(RevisionID INT)" }
    @{ Case = 'a changed column list'; Definition = "CREATE PROCEDURE p AS`nDECLARE @revisionList TABLE(RevisionID INT, Extra INT)" }
    @{ Case = 'an empty definition'; Definition = '' }
  ) {
    $Fix = ConvertTo-DeleteUpdateFix -Definition $Definition

    $Fix.State | Should -Be 'Unexpected'
    $Fix.Definition | Should -Be ''
  }
}

Describe 'Set-DeleteUpdateProcedureFix' {
  BeforeAll {
    # A SUSDB holding one procedure definition. ALTER PROCEDURE replaces it as SQL Server would
    #   unless -Ignore is set; commands matching -FailOn fail.
    Function script:New-ProcedureDatabase {
      Param ([AllowNull()][System.String]$Definition, [System.String]$FailOn = '', [System.Boolean]$Ignore = $False)
      $State = @{ Definition = $Definition }
      $Responder = {
        Param ($Text, $Parameters, $NonQuery)
        If (($FailOn -ne '') -and ($Text -match $FailOn)) { Throw 'ALTER PROCEDURE permission denied on object spDeleteUpdate.' }
        If ($NonQuery) {
          If (($Text -like 'ALTER PROCEDURE*') -and (-not $Ignore)) { $State.Definition = 'CREATE' + $Text.Substring(5) }
          0
        } Else {
          [PSCustomObject]@{ Definition = $State.Definition }
        }
      }.GetNewClosure()
      New-FakeSqlConnection -Responder $Responder
    }
  }

  BeforeEach {
    $script:Log = New-MaintenanceLog -Folder (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))) -RunId 'RUN' -Verbosity 'Information'
  }

  It 'applies the fix with the before and after text in the log and verifies it' {
    $Database = New-ProcedureDatabase -Definition $script:Original

    $Result = Set-DeleteUpdateProcedureFix -Context (New-FakeStageContext -Database $Database -Log $script:Log)

    $Result.Status | Should -Be 'Success'
    $Result.Message | Should -Be 'applied'
    $Result.Counts['Applied'] | Should -Be 1
    $Commands = @(Get-FakeCommandText -Connection $Database)
    $Commands | Should -HaveCount 4
    $Commands[0] | Should -Be "SELECT OBJECT_DEFINITION(OBJECT_ID(N'dbo.spDeleteUpdate')) AS Definition"
    $Commands[1] | Should -Be 'SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;'
    $Commands[2] | Should -BeExactly $script:Fixed.Replace('CREATE PROCEDURE', 'ALTER PROCEDURE')
    $Commands[3] | Should -Be $Commands[0]
    $Text = Get-Content -LiteralPath $script:Log.Path -Raw
    $Text | Should -Match 'DeleteUpdateFix: spDeleteUpdate before the fix: CREATE PROCEDURE dbo\.spDeleteUpdate'
    $Text | Should -Match 'DECLARE @revisionList TABLE\(RevisionID INT\)\s'
    $Text | Should -Match 'DeleteUpdateFix: spDeleteUpdate after the fix: CREATE PROCEDURE dbo\.spDeleteUpdate'
    $Text | Should -Match 'DECLARE @revisionList TABLE\(RevisionID INT PRIMARY KEY\)'
  }

  It 'leaves a procedure that already carries the fix alone' {
    $Database = New-ProcedureDatabase -Definition $script:Fixed

    $Result = Set-DeleteUpdateProcedureFix -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Success'
    $Result.Message | Should -Be 'already applied'
    $Result.Counts['AlreadyApplied'] | Should -Be 1
    @(Get-FakeCommandText -Connection $Database) | Should -HaveCount 1
  }

  It 'warns and leaves the procedure untouched when its text is unexpected' {
    $Database = New-ProcedureDatabase -Definition 'CREATE PROCEDURE dbo.spDeleteUpdate AS RETURN(0)'

    $Result = Set-DeleteUpdateProcedureFix -Context (New-FakeStageContext -Database $Database)

    $Result.Status | Should -Be 'Warning'
    $Result.Message | Should -Be 'left untouched: unexpected definition'
    $Result.Notices | Should -HaveCount 1
    $Result.Notices[0].Severity | Should -Be 'Warning'
    $Result.Notices[0].Message | Should -Be 'dbo.spDeleteUpdate does not have the text the published fix expects, so it was left untouched.'
    @(Get-FakeCommandText -Connection $Database) | Should -HaveCount 1
  }

  It 'warns when <Case>' -ForEach @(
    @{ Case = 'the procedure is missing'; Definition = $Null; FailOn = ''; Ignore = $False; Message = 'failed: dbo.spDeleteUpdate was not found or its definition cannot be read' }
    @{ Case = 'the change is refused'; Definition = 'original'; FailOn = '^ALTER'; Ignore = $False; Message = 'failed: *ALTER PROCEDURE permission denied on object spDeleteUpdate.' }
    @{ Case = 'the change does not hold'; Definition = 'original'; FailOn = ''; Ignore = $True; Message = 'failed: the altered definition does not carry the fix' }
  ) {
    $Database = New-ProcedureDatabase -Definition $(If ($Definition -eq 'original') { $script:Original } Else { $Definition }) -FailOn $FailOn -Ignore $Ignore

    $Result = Set-DeleteUpdateProcedureFix -Context (New-FakeStageContext -Database $Database -Log $script:Log)

    $Result.Status | Should -Be 'Warning'
    $Result.Message | Should -BeLike $Message
    $Result.Counts['Applied'] | Should -Be 0
    $Result.Notices[0].Message | Should -BeLike 'The spDeleteUpdate fix could not be checked or applied: *. Obsolete-update deletion still runs.'
  }

  It 'changes nothing in a dry run' {
    $Database = New-ProcedureDatabase -Definition $script:Original

    $Result = Set-DeleteUpdateProcedureFix -Context (New-FakeStageContext -Database $Database -DryRun $True)

    $Result.Message | Should -Be 'would apply'
    @(Get-FakeCommandText -Connection $Database) | Should -HaveCount 1
  }
}
