#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'Save-MaintenanceReport' {
  BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../build/Invoke-WsusMaintenance.Functions.ps1')
  }

  It 'writes one file per format, named after the run identifier' {
    $Folder = Join-Path -Path $TestDrive -ChildPath 'both'
    $Null = New-Item -ItemType Directory -Path $Folder

    $Saved = Save-MaintenanceReport -Folder $Folder -Format @('Text', 'Html') -Text "text`r`n" -Html '<html></html>' -RunId 'RUN'

    $Saved.Errors | Should -HaveCount 0
    $Saved.Paths | Should -Be @((Join-Path -Path $Folder -ChildPath 'WsusMaintenance-RUN.txt'), (Join-Path -Path $Folder -ChildPath 'WsusMaintenance-RUN.html'))
    [System.IO.File]::ReadAllText($Saved.Paths[0]) | Should -Be "text`r`n"
    [System.IO.File]::ReadAllText($Saved.Paths[1]) | Should -Be '<html></html>'
  }

  It 'writes only the configured formats' {
    $Folder = Join-Path -Path $TestDrive -ChildPath 'html'
    $Null = New-Item -ItemType Directory -Path $Folder

    $Saved = Save-MaintenanceReport -Folder $Folder -Format @('Html') -Text 't' -Html 'h' -RunId 'RUN'

    $Saved.Paths | Should -HaveCount 1
    $Saved.Paths[0] | Should -BeLike '*.html'
  }

  It 'writes nothing without a usable folder' {
    $Saved = Save-MaintenanceReport -Folder '' -Format @('Text') -Text 't' -Html 'h' -RunId 'RUN'

    $Saved.Paths | Should -HaveCount 0
    $Saved.Errors | Should -HaveCount 0
  }

  It 'reports a file that cannot be written' {
    $Saved = Save-MaintenanceReport -Folder (Join-Path -Path $TestDrive -ChildPath 'missing') -Format @('Text') -Text 't' -Html 'h' -RunId 'RUN'

    $Saved.Paths | Should -HaveCount 0
    $Saved.Errors[0] | Should -BeLike "The report file '*WsusMaintenance-RUN.txt' could not be written: *"
  }
}
