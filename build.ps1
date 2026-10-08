#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    Builds, analyzes, tests, and smokes the WSUS maintenance script.

.PARAMETER Task
    One or more tasks to run: Build, Test, Analyze, Smoke, Clean, or All.

.EXAMPLE
    .\build.ps1 -Task All
#>
[CmdletBinding()]
Param (
  [Parameter(
    DontShow = $False,
    Mandatory = $False,
    ParameterSetName = 'default',
    ValueFromPipeline = $False,
    ValueFromPipelineByPropertyName = $False
  )]
  [ValidateSet('Build', 'Test', 'Analyze', 'Smoke', 'Clean', 'All')]
  [System.String[]]
  $Task = 'Build'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = [System.String]$PSScriptRoot
$ProjectName = 'Invoke-WsusMaintenance'
$SourceRoot = Join-Path -Path $ProjectRoot -ChildPath 'src'
$TestRoot = Join-Path -Path $ProjectRoot -ChildPath 'tests'
$BuildRoot = Join-Path -Path $ProjectRoot -ChildPath 'build'
$OutputFile = Join-Path -Path $BuildRoot -ChildPath ('{0}.ps1' -f $ProjectName)
$FunctionsFile = Join-Path -Path $BuildRoot -ChildPath ('{0}.Functions.ps1' -f $ProjectName)

Function Get-LatestAvailableModule {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.PSModuleInfo])]
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
    $Name
  )

  Get-Module -ListAvailable -Name $Name |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1
}

Function Test-Syntax {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $Path
  )

  $private:Messages = [System.Collections.Generic.List[System.String]]::new()

  $Path | ForEach-Object -Process {
    $private:ScriptPath = [System.String]$PSItem
    If (Test-Path -LiteralPath $ScriptPath) {
      $private:Tokens = $Null
      $private:ParseErrors = $Null
      $Null = [System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath,
        [ref]$Tokens,
        [ref]$ParseErrors
      )

      If ($ParseErrors.Count -gt 0) {
        $ParseErrors | ForEach-Object -Process {
          $Messages.Add(
            (
              '{0}: line {1}: {2}' -f
              $ScriptPath,
              $PSItem.Extent.StartLineNumber,
              $PSItem.Message
            )
          )
        }
      }
    }
  }

  If ($Messages.Count -gt 0) {
    Throw (
      'Syntax errors detected:{0}{1}' -f
      [System.Environment]::NewLine,
      ($Messages -join [System.Environment]::NewLine)
    )
  }
}

Function Get-EntryPointContent {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject])]
  Param ()

  $private:EntryPointPath = Join-Path -Path $SourceRoot -ChildPath 'EntryPoint.ps1'
  $private:EntryPointText = (Get-Content -LiteralPath $EntryPointPath -Raw).Trim()
  $private:EntryPointLines = [System.String[]]($EntryPointText -split '\r?\n')
  $private:ParamEnd = -1
  $private:InParamBlock = $False
  $private:ParenDepth = 0

  For ($Index = 0; $Index -lt $EntryPointLines.Count; $Index++) {
    $private:Line = [System.String]$EntryPointLines[$Index]
    $private:TrimmedLine = $Line.Trim()

    If ($InParamBlock -eq $False -and $TrimmedLine -match '^Param\s*\(') {
      $InParamBlock = $True
    }

    If ($InParamBlock -eq $True) {
      $private:OpenParenCount = ([regex]::Matches($Line, '\(')).Count
      $private:CloseParenCount = ([regex]::Matches($Line, '\)')).Count
      $ParenDepth += ($OpenParenCount - $CloseParenCount)

      If ($ParenDepth -eq 0) {
        $ParamEnd = $Index
        Break
      }
    }
  }

  If ($ParamEnd -lt 0) {
    Throw 'EntryPoint.ps1 must contain a Param block.'
  }

  [PSCustomObject]@{
    Lines    = $EntryPointLines
    ParamEnd = $ParamEnd
  }
}

Function Add-FunctionFileContent {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
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
    $Directory,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $RegionName,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Text.StringBuilder]
    $StringBuilder
  )

  $private:FunctionFiles = @(
    Get-ChildItem `
      -LiteralPath $Directory `
      -Filter '*.ps1' `
      -ErrorAction SilentlyContinue |
      Sort-Object -Property Name
  )

  If ($FunctionFiles.Count -gt 0) {
    $Null = $StringBuilder.AppendLine(('#region {0}' -f $RegionName))
    $Null = $StringBuilder.AppendLine('')

    $FunctionFiles | ForEach-Object -Process {
      $private:Content = (Get-Content -LiteralPath $PSItem.FullName -Raw).Trim()
      $Content = $Content -replace '(?m)^#Requires[^\r\n]*(\r?\n)?', ''
      $Content = $Content -replace '(?m)^# SPDX-FileCopyrightText:[^\r\n]*(\r?\n)?', ''
      $Content = $Content -replace '(?m)^# SPDX-License-Identifier:[^\r\n]*(\r?\n)?', ''
      $Null = $StringBuilder.AppendLine($Content.Trim())
      $Null = $StringBuilder.AppendLine('')
    }

    $Null = $StringBuilder.AppendLine('#endregion')
    $Null = $StringBuilder.AppendLine('')
  }
}

Function Invoke-SmokeTest {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param ()

  $private:SmokeRoot = Join-Path -Path $TestRoot -ChildPath 'Smoke'
  $private:SmokeFiles = @(
    Get-ChildItem `
      -LiteralPath $SmokeRoot `
      -Filter '*.ps1' `
      -ErrorAction SilentlyContinue |
      Sort-Object -Property Name
  )

  If ($SmokeFiles.Count -eq 0) {
    Write-Warning -Message 'No smoke tests found.'
  } Else {
    $SmokeFiles | ForEach-Object -Process {
      Write-Information -MessageData ('Smoke: {0}' -f $PSItem.Name) -InformationAction Continue
      & $PSItem.FullName
    }
  }
}

Function Invoke-Build {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param ()

  If (-not (Test-Path -LiteralPath $BuildRoot)) {
    $Null = New-Item -Path $BuildRoot -ItemType Directory
  }

  $private:EntryPoint = Get-EntryPointContent
  $private:FunctionBuilder = [System.Text.StringBuilder]::new(32768)
  $Null = $FunctionBuilder.AppendLine('#Requires -Version 5.1')
  $Null = $FunctionBuilder.AppendLine('# SPDX-FileCopyrightText: 2026 Nicholas Warila')
  $Null = $FunctionBuilder.AppendLine('# SPDX-License-Identifier: MIT')
  $Null = $FunctionBuilder.AppendLine('')
  $Null = $FunctionBuilder.AppendLine('#region Message Table')
  $Null = $FunctionBuilder.AppendLine('[System.Collections.Hashtable]$Script:Message = @{}')
  $Null = $FunctionBuilder.AppendLine('#endregion')
  $Null = $FunctionBuilder.AppendLine('')

  Add-FunctionFileContent `
    -StringBuilder $FunctionBuilder `
    -Directory (Join-Path -Path $SourceRoot -ChildPath 'Private') `
    -RegionName 'Private Functions'

  Add-FunctionFileContent `
    -StringBuilder $FunctionBuilder `
    -Directory (Join-Path -Path $SourceRoot -ChildPath 'Public') `
    -RegionName 'Public Functions'

  $private:FunctionsContent = $FunctionBuilder.ToString().TrimEnd() + [System.Environment]::NewLine
  [System.IO.File]::WriteAllText(
    $FunctionsFile,
    $FunctionsContent,
    [System.Text.UTF8Encoding]::new($False)
  )

  $private:FullBuilder = [System.Text.StringBuilder]::new(32768)
  $Null = $FullBuilder.AppendLine('#Requires -Version 5.1')
  $Null = $FullBuilder.AppendLine('# SPDX-FileCopyrightText: 2026 Nicholas Warila')
  $Null = $FullBuilder.AppendLine('# SPDX-License-Identifier: MIT')
  $Null = $FullBuilder.AppendLine('')

  For ($Index = 0; $Index -le $EntryPoint.ParamEnd; $Index++) {
    $private:Line = [System.String]$EntryPoint.Lines[$Index]
    If ($Line.Trim() -match '^#Requires') {
      Continue
    }

    If ($Line.Trim() -match '^# SPDX-(FileCopyrightText|License-Identifier):') {
      Continue
    }

    $Null = $FullBuilder.AppendLine($Line)
  }

  $Null = $FullBuilder.AppendLine('')
  $private:FunctionBody = $FunctionsContent -replace '(?m)^#Requires[^\r\n]*(\r?\n)?', ''
  $FunctionBody = $FunctionBody -replace '(?m)^# SPDX-FileCopyrightText:[^\r\n]*(\r?\n)?', ''
  $FunctionBody = $FunctionBody -replace '(?m)^# SPDX-License-Identifier:[^\r\n]*(\r?\n)?', ''
  $FunctionBody = $FunctionBody.TrimStart()
  $Null = $FullBuilder.Append($FunctionBody)
  $Null = $FullBuilder.AppendLine('#region Entry Point')
  $Null = $FullBuilder.AppendLine('')

  For ($Index = ($EntryPoint.ParamEnd + 1); $Index -lt $EntryPoint.Lines.Count; $Index++) {
    $Null = $FullBuilder.AppendLine([System.String]$EntryPoint.Lines[$Index])
  }

  $Null = $FullBuilder.AppendLine('')
  $Null = $FullBuilder.AppendLine('#endregion')

  $private:FullContent = $FullBuilder.ToString().TrimEnd() + [System.Environment]::NewLine
  [System.IO.File]::WriteAllText(
    $OutputFile,
    $FullContent,
    [System.Text.UTF8Encoding]::new($False)
  )

  Test-Syntax -Path @($FunctionsFile, $OutputFile)
  Write-Information -MessageData ('Build complete: {0}' -f $OutputFile) -InformationAction Continue
}

Function Invoke-Analyze {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param ()

  If (-not (Test-Path -LiteralPath $OutputFile)) {
    Invoke-Build
  }

  $private:AnalyzerRuleFile = Join-Path -Path $ProjectRoot -ChildPath 'analyzers\HouseRules.psm1'
  $private:SyntaxTargets = @(
    Join-Path -Path $ProjectRoot -ChildPath 'build.ps1'
    $AnalyzerRuleFile
    $OutputFile
    $FunctionsFile
  )

  Test-Syntax -Path $SyntaxTargets

  $private:AnalyzerModule = Get-LatestAvailableModule -Name 'PSScriptAnalyzer'
  If ($Null -eq $AnalyzerModule) {
    Throw 'PSScriptAnalyzer is required for analysis. Install PSScriptAnalyzer 1.25.0.'
  }

  Import-Module -Name $AnalyzerModule.Path -Force

  $private:SettingsFile = Join-Path -Path $ProjectRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
  $private:Results = @(
    Invoke-ScriptAnalyzer -Path $OutputFile -Settings $SettingsFile
    Invoke-ScriptAnalyzer -Path $FunctionsFile -Settings $SettingsFile
    Invoke-ScriptAnalyzer -Path $AnalyzerRuleFile -Settings $SettingsFile
    Invoke-ScriptAnalyzer -Path (Join-Path -Path $ProjectRoot -ChildPath 'build.ps1') -Settings $SettingsFile
  )

  If ($Results.Count -gt 0) {
    $private:FormattedResults = $Results |
      Format-Table -Property RuleName, Severity, ScriptName, Line, Message -AutoSize |
      Out-String
    Write-Information -MessageData $FormattedResults -InformationAction Continue

    Throw ('PSScriptAnalyzer found {0} issue(s).' -f $Results.Count)
  }

  Write-Information -MessageData 'Analysis passed.' -InformationAction Continue
}

Function Invoke-Test {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param ()

  If (-not (Test-Path -LiteralPath $FunctionsFile)) {
    Invoke-Build
  }

  $private:PesterModule = Get-LatestAvailableModule -Name 'Pester'
  If ($Null -eq $PesterModule -or $PesterModule.Version.Major -lt 5) {
    Throw 'Pester 5 or newer is required for tests and coverage.'
  }

  Import-Module -Name $PesterModule.Path -Force

  $private:PesterConfig = [PesterConfiguration]::Default
  $PesterConfig.Run.Path = $TestRoot
  $PesterConfig.Run.Throw = $True
  $PesterConfig.Run.PassThru = $True
  $PesterConfig.Output.Verbosity = 'Detailed'
  $PesterConfig.TestResult.Enabled = $True
  $PesterConfig.TestResult.OutputFormat = 'NUnitXml'
  $PesterConfig.TestResult.OutputPath = Join-Path -Path $BuildRoot -ChildPath 'testResults.xml'
  $PesterConfig.CodeCoverage.Enabled = $True
  $PesterConfig.CodeCoverage.Path = $FunctionsFile
  $PesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
  $PesterConfig.CodeCoverage.OutputPath = Join-Path -Path $BuildRoot -ChildPath 'coverage.xml'
  $PesterConfig.CodeCoverage.CoveragePercentTarget = 90
  # Profiler-based coverage: Pester 5 measures with breakpoints by default, which makes every
  #   covered command several times slower under Windows PowerShell 5.1; Pester 6 already uses the
  #   profiler by default. The measured percentage is the same either way.
  $PesterConfig.CodeCoverage.UseBreakpoints = $False

  $private:PesterResult = Invoke-Pester -Configuration $PesterConfig

  [System.Double]$private:CoverageTarget = $PesterConfig.CodeCoverage.CoveragePercentTarget.Value
  [System.Double]$private:CoveragePercent = $PesterResult.CodeCoverage.CoveragePercent

  If ($CoveragePercent -lt $CoverageTarget) {
    Throw (
      'Code coverage {0:N2} percent is below the required {1:N0} percent gate.' -f
      $CoveragePercent, $CoverageTarget
    )
  }

  Write-Information -MessageData (
    'Code coverage {0:N2} percent meets the {1:N0} percent gate.' -f
    $CoveragePercent, $CoverageTarget
  ) -InformationAction Continue
}

Function Invoke-Smoke {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param ()

  If (-not (Test-Path -LiteralPath $FunctionsFile)) {
    Invoke-Build
  }

  Invoke-SmokeTest
}

Function Invoke-Clean {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Void])]
  Param ()

  If (Test-Path -LiteralPath $BuildRoot) {
    Remove-Item -LiteralPath $BuildRoot -Recurse -Force
  }

  Write-Information -MessageData 'Clean complete.' -InformationAction Continue
}

If ('All' -in $Task) {
  $Task = @('Clean', 'Build', 'Analyze', 'Test', 'Smoke')
}

$Task | ForEach-Object -Process {
  Write-Information -MessageData ('{0}=== {1} ===' -f [System.Environment]::NewLine, $PSItem) -InformationAction Continue
  & "Invoke-$PSItem"
}
