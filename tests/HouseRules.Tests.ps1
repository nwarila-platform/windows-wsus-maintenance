#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Describe 'SG-1 house analyzer rules' {
  BeforeAll {
    $AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    $script:AnalyzerRulePath = $AnalyzerRulePath
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }
  }

  It 'flags function-local assignments that are not Private-scoped' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    $Value = 'thing'
    $Value
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-PrivateVariableDeclaration'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-PrivateVariableDeclaration' })
    $Results.RuleName | Should -Contain 'Measure-PrivateVariableDeclaration'
  }

  It 'accepts Private-scoped local assignments' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    [System.String]$Private:Value = 'thing'
    $Value
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-PrivateVariableDeclaration'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-PrivateVariableDeclaration' })
    $Results | Should -HaveCount 0
  }

  It 'flags New-Variable local declarations' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    New-Variable -Name 'Value' -Force -Option Private -Value ([System.String]::Empty)
    $Value = 'thing'
    $Value
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-NoNewVariableDeclaration'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-NoNewVariableDeclaration' })
    $Results.RuleName | Should -Contain 'Measure-NoNewVariableDeclaration'
  }

  It 'flags pipeline locals not declared in Begin' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [System.String]
        $InputObject
    )
    begin { }
    process {
        $Value = [System.String]::Empty
        [System.String]$Private:Value = $InputObject.ToUpperInvariant()
        $Value
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-PipelineVariableLifecycle'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-PipelineVariableLifecycle' })
    $Results.RuleName | Should -Contain 'Measure-PipelineVariableLifecycle'
    $Results.Message | Should -Match 'without declaring it in Begin'
  }

  It 'flags pipeline locals not reset at the top of Process' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    process {
        Write-Debug -Message 'not clear first'
        $Value = $InputObject.ToUpperInvariant()
        $Value
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-PipelineVariableLifecycle'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-PipelineVariableLifecycle' })
    $Results.RuleName | Should -Contain 'Measure-PipelineVariableLifecycle'
    $Results.Message | Should -Match 'does not reset it at the top of Process'
  }

  It 'accepts the pipeline Begin and reset idiom' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    process {
        $Value = [System.String]::Empty
        $Value = $InputObject.ToUpperInvariant()
        $Value
    }
    end { }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-PipelineVariableLifecycle'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-PipelineVariableLifecycle' })
    $Results | Should -HaveCount 0
  }

  It 'accepts an Entering Process debug anchor before pipeline resets' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    process {
        Write-Debug -Message '[ConvertTo-Thing] Entering Process'
        $Value = [System.String]::Empty
        $Value = $InputObject.ToUpperInvariant()
        $Value
    }
    end { }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-PipelineVariableLifecycle'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-PipelineVariableLifecycle' })
    $Results | Should -HaveCount 0
  }

  It 'flags named blocks on flat non-pipeline functions' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    process {
        $Value = 'thing'
        $Value
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-FlatNonPipelineFunction'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-FlatNonPipelineFunction' })
    $Results.RuleName | Should -Contain 'Measure-FlatNonPipelineFunction'
    $Results.Message | Should -Match 'no pipeline input'
  }

  It 'accepts implicit End block flat functions' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    [System.String]$Private:Value = 'thing'
    $Value
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-FlatNonPipelineFunction'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-FlatNonPipelineFunction' })
    $Results | Should -HaveCount 0
  }

  It 'accepts named blocks when a function declares pipeline input' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [System.String]
        $Name
    )
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    process {
        $Value = [System.String]::Empty
        $Value = $Name.ToUpperInvariant()
        $Value
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-FlatNonPipelineFunction'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-FlatNonPipelineFunction' })
    $Results | Should -HaveCount 0
  }

  It 'flags Remove-Variable cleanup in End blocks' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    process {
        $Value = 'thing'
        $Value
    }
    end {
        Remove-Variable -Name 'Value'
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-NoRemoveVariableCleanup'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-NoRemoveVariableCleanup' })
    $Results.RuleName | Should -Contain 'Measure-NoRemoveVariableCleanup'
  }
}

Describe 'SG-3 house analyzer rules' {
  BeforeAll {
    $script:AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }
  }

  It 'flags mis-cased named blocks' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    begin {
        [System.String]$Private:Value = [System.String]::Empty
    } process {
        $Value = $InputObject.ToUpperInvariant()
        $Value
    } end {
        Write-Debug -Message '[ConvertTo-Thing] Exiting End'
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalNamedBlock'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalNamedBlock' })
    $Results.RuleName | Should -Contain 'Measure-CanonicalNamedBlock'
    [System.String]$MessageText = $Results.Message -join "`n"
    $MessageText | Should -Match "must start with 'Begin {'"
    $MessageText | Should -Match "must start with 'Process {'"
    $MessageText | Should -Match "must start with 'End {'"
  }

  It 'flags uncuddled named block transitions' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    Begin {
        [System.String]$Private:Value = [System.String]::Empty
    }
    Process {
        $Value = $InputObject.ToUpperInvariant()
        $Value
    }
    End {
        Write-Debug -Message '[ConvertTo-Thing] Exiting End'
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalNamedBlock'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalNamedBlock' })
    $Results.RuleName | Should -Contain 'Measure-CanonicalNamedBlock'
    [System.String]$MessageText = $Results.Message -join "`n"
    $MessageText | Should -Match "must be cuddled as '} Process {'"
    $MessageText | Should -Match "must be cuddled as '} End {'"
  }

  It 'accepts canonical named block casing and layout' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    Begin {
        [System.String]$Private:Value = [System.String]::Empty
    } Process {
        $Value = $InputObject.ToUpperInvariant()
        $Value
    } End {
        Write-Debug -Message '[ConvertTo-Thing] Exiting End'
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalNamedBlock'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalNamedBlock' })
    $Results | Should -HaveCount 0
  }
}

Describe 'canonical keyword casing house analyzer rule' {
  BeforeAll {
    $script:AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }
  }

  It 'flags lowercase <Keyword> with canonical suggestion <ExpectedKeyword>' -TestCases @(
    @{
      ExpectedKeyword  = 'If'
      Keyword          = 'if'
      ScriptDefinition = "Function Get-Thing {`n    Param ()`n    if (`$True) { 'yes' }`n}"
    }
    @{
      ExpectedKeyword  = 'ForEach'
      Keyword          = 'foreach'
      ScriptDefinition = "Function Get-Thing {`n    Param ()`n    foreach (`$Item In @(1)) { `$Item }`n}"
    }
    @{
      ExpectedKeyword  = 'Param'
      Keyword          = 'param'
      ScriptDefinition = "Function Get-Thing {`n    param ()`n}"
    }
    @{
      ExpectedKeyword  = 'Function'
      Keyword          = 'function'
      ScriptDefinition = "function Get-Thing {`n    Param ()`n}"
    }
  ) {
    param (
      [System.String]
      $ExpectedKeyword,

      [System.String]
      $Keyword,

      [System.String]
      $ScriptDefinition
    )

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalKeywordCasing'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalKeywordCasing' })
    [System.String[]]$Messages = @($Results.Message | Select-Object -Unique)

    $Messages | Should -HaveCount 1
    $Messages | Should -Contain ("Keyword '{0}' must be canonical casing '{1}'." -f $Keyword, $ExpectedKeyword)
  }

  It 'accepts PascalCase forms including compound keywords' {
    $ScriptDefinition = @'
Function ConvertTo-Thing {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    DynamicParam {
        [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    } Begin {
        If ($InputObject) {
            $InputObject
        } ElseIf ($False) {
            'fallback'
        } Else {
            ForEach ($Item In @(1)) {
                $Item
            }
        }
    } Process {
        $InputObject
    } End {
        Try {
            'done'
        } Catch {
            Throw
        } Finally {
            'cleanup'
        }
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalKeywordCasing'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalKeywordCasing' })

    $Results | Should -HaveCount 0
  }

  It 'does not flag lower-case operator tokens' {
    $ScriptDefinition = @'
Function Test-Thing {
    Param ()
    If ($True -and (1 -in @(1))) {
        'ok'
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalKeywordCasing'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalKeywordCasing' })

    $Results | Should -HaveCount 0
  }
}

Describe 'SG-4 house analyzer rules' {
  BeforeAll {
    $script:AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }

    $script:NewExplicitBindingFixture = {
      param (
        [Parameter()]
        [AllowNull()]
        [System.String]
        $MissingOption = $Null,

        [Parameter()]
        [System.Boolean]
        $IncludeOutputType = $True
      )

      $Options = @(
        @{ Name = 'SupportsShouldProcess'; Value = '$False' },
        @{ Name = 'ConfirmImpact'; Value = "'None'" },
        @{ Name = 'PositionalBinding'; Value = '$False' },
        @{ Name = 'DefaultParameterSetName'; Value = "'default'" },
        @{ Name = 'HelpUri'; Value = "'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing'" },
        @{ Name = 'SupportsPaging'; Value = '$False' }
      ) | Where-Object -FilterScript {
        $PSItem.Name -ine $MissingOption
      }

      $OptionLines = [System.Collections.Generic.List[System.String]]::new()
      for ($Index = 0; $Index -lt $Options.Count; $Index++) {
        $Line = '        {0} = {1}' -f $Options[$Index].Name, $Options[$Index].Value
        if ($Index -lt ($Options.Count - 1)) {
          $Line = '{0},' -f $Line
        }

        [void]$OptionLines.Add($Line)
      }

      $OutputTypeLine = [System.String]::Empty
      if ($IncludeOutputType -eq $True) {
        $OutputTypeLine = '    [OutputType([System.String])]'
      }

      @"
function Get-Thing {
    [CmdletBinding(
$($OptionLines.ToArray() -join "`n")
    )]
$OutputTypeLine
    param ()
    [System.String]'thing'
}
"@
    }.GetNewClosure()
  }

  It 'accepts the complete explicit CmdletBinding and OutputType surface' {
    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition (& $script:NewExplicitBindingFixture) `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitCmdletBinding'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitCmdletBinding' })
    $Results | Should -HaveCount 0
  }

  It 'flags every missing explicit CmdletBinding option' {
    $RequiredOptions = [System.String[]]@(
      'SupportsShouldProcess',
      'ConfirmImpact',
      'PositionalBinding',
      'DefaultParameterSetName',
      'HelpUri',
      'SupportsPaging'
    )

    foreach ($RequiredOption in $RequiredOptions) {
      $Results = Invoke-ScriptAnalyzer `
        -ScriptDefinition (& $script:NewExplicitBindingFixture -MissingOption $RequiredOption) `
        -CustomRulePath $script:AnalyzerRulePath `
        -IncludeRule 'Measure-ExplicitCmdletBinding'


      $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitCmdletBinding' })
      $Results.RuleName | Should -Contain 'Measure-ExplicitCmdletBinding'
      $Results.Message | Should -Match $RequiredOption
    }
  }

  It 'flags missing OutputType even when CmdletBinding is complete' {
    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition (& $script:NewExplicitBindingFixture -IncludeOutputType $False) `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitCmdletBinding'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitCmdletBinding' })
    $Results.RuleName | Should -Contain 'Measure-ExplicitCmdletBinding'
    $Results.Message | Should -Match 'OutputType'
  }

  It 'flags PositionalBinding values other than false' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing',
        PositionalBinding = $True,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param ()
    [System.String]'thing'
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitCmdletBinding'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitCmdletBinding' })
    $Results.RuleName | Should -Contain 'Measure-ExplicitCmdletBinding'
    $Results.Message | Should -Match 'PositionalBinding'
  }

  It 'flags functions without CmdletBinding' {
    $ScriptDefinition = @'
function Get-Thing {
    [OutputType([System.String])]
    param ()
    [System.String]'thing'
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitCmdletBinding'


    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitCmdletBinding' })
    $Results.RuleName | Should -Contain 'Measure-ExplicitCmdletBinding'
    $Results.Message | Should -Match 'CmdletBinding'
  }
}

Describe 'SG-5 house analyzer rules' {
  BeforeAll {
    $script:AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }
  }

  It 'flags misordered CmdletBinding options' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding(
        SupportsShouldProcess = $False,
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing',
        PositionalBinding = $False,
        SupportsPaging = $False
    )]
    [OutputType([System.String])]
    param ()
    [System.String]'thing'
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results.RuleName | Should -Contain 'Measure-CanonicalAttributeOrder'
    $Results.Message | Should -Match 'SG-5a'
  }

  It 'flags misordered Parameter attribute arguments' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#convertto-thing',
        PositionalBinding = $False,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param (
        [Parameter(ValueFromPipeline = $True, Mandatory = $True, DontShow = $False, ParameterSetName = 'default', ValueFromPipelineByPropertyName = $True)]
        [System.String]
        $InputObject
    )
    process {
        $InputObject
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results.RuleName | Should -Contain 'Measure-CanonicalAttributeOrder'
    $Results.Message | Should -Match 'SG-5b'
  }

  It 'flags validation attributes after the type literal' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing',
        PositionalBinding = $False,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param (
        [Parameter(
            DontShow = $False,
            Mandatory = $True,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [System.String]
        [ValidateNotNullOrEmpty()]
        $Name
    )
    $Name
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results.RuleName | Should -Contain 'Measure-CanonicalAttributeOrder'
    $Results.Message -join [System.Environment]::NewLine | Should -Match 'type must be last'
  }

  It 'flags wrong parameter attribute order' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing',
        PositionalBinding = $False,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param (
        [ValidateNotNullOrEmpty()]
        [Parameter(
            DontShow = $False,
            Mandatory = $True,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [System.String]
        $Name
    )
    $Name
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results.RuleName | Should -Contain 'Measure-CanonicalAttributeOrder'
    $Results.Message | Should -Match 'SG-5c'
  }

  It 'flags unsorted parameter names' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing',
        PositionalBinding = $False,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param (
        [Parameter(
            DontShow = $False,
            Mandatory = $False,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [System.String]
        $Zoo,

        [Parameter(
            DontShow = $False,
            Mandatory = $False,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [System.String]
        $Alpha
    )
    $Alpha
    $Zoo
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results.RuleName | Should -Contain 'Measure-CanonicalAttributeOrder'
    $Results.Message | Should -Match 'SG-5d'
  }

  It 'flags Parameter Position even when the rest of the surface is explicit' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#get-thing',
        PositionalBinding = $False,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param (
        [Parameter(
            DontShow = $False,
            Mandatory = $False,
            ParameterSetName = 'default',
            Position = 1,
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [System.String]
        $Zoo,

        [Parameter(
            DontShow = $False,
            Mandatory = $False,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [System.String]
        $Alpha
    )
    $Alpha
    $Zoo
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results.RuleName | Should -Contain 'Measure-CanonicalAttributeOrder'
    [System.String]$MessageText = $Results.Message -join "`n"
    $MessageText | Should -Match 'Position'
    $MessageText | Should -Match 'SG-5e'
  }

  It 'accepts the canonical declaration idiom' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding(
        ConfirmImpact = 'None',
        DefaultParameterSetName = 'default',
        HelpUri = 'https://github.com/example/repo/blob/main/docs/reference/functions.md#convertto-thing',
        PositionalBinding = $False,
        SupportsPaging = $False,
        SupportsShouldProcess = $False
    )]
    [OutputType([System.String])]
    param (
        [Parameter(
            DontShow = $False,
            Mandatory = $True,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Alpha,

        [Parameter(
            DontShow = $False,
            Mandatory = $True,
            ParameterSetName = 'default',
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True
        )]
        [Alias('n')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )
    process {
        $Name
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-CanonicalAttributeOrder'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-CanonicalAttributeOrder' })

    $Results | Should -HaveCount 0
  }
}

Describe 'SG-6 house analyzer rules' {
  BeforeAll {
    $script:AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }
  }

  It 'flags hard return statements inside functions' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    return 'thing'
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-SoftReturn'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-SoftReturn' })

    $Results.RuleName | Should -Contain 'Measure-SoftReturn'
    $Results.Message | Should -Match "uses 'return'"
  }

  It 'flags Private Result functions whose last statement is not an Exiting debug anchor' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    [System.String]$Private:Result = 'thing'
    $Result
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-SoftReturn'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-SoftReturn' })

    $Results.RuleName | Should -Contain 'Measure-SoftReturn'
    $Results.Message | Should -Match 'last statement'
  }

  It 'accepts a compliant flat soft-return function' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param ()
    Write-Debug -Message '[Get-Thing] Entering'
    [System.String]$Private:Result = 'thing'
    $Result
    Write-Debug -Message '[Get-Thing] Exiting'
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-SoftReturn'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-SoftReturn' })

    $Results | Should -HaveCount 0
  }

  It 'accepts a compliant pipeline soft-return function' {
    $ScriptDefinition = @'
function ConvertTo-Thing {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $True)]
        [System.String]
        $InputObject
    )
    begin {
        [System.String]$Private:Result = [System.String]::Empty
    }
    process {
        Write-Debug -Message '[ConvertTo-Thing] Entering Process'
        $Result = [System.String]::Empty
        [System.String]$Result = $InputObject.ToUpperInvariant()
        $Result
        Write-Debug -Message '[ConvertTo-Thing] Exiting Process'
    }
    end {
        Write-Debug -Message '[ConvertTo-Thing] Exiting End'
    }
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-SoftReturn'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-SoftReturn' })

    $Results | Should -HaveCount 0
  }

  It 'exempts throw-only helpers without Private Result' {
    $ScriptDefinition = @'
function New-ThingError {
    [CmdletBinding()]
    param ()
    $PSCmdlet.ThrowTerminatingError($Null)
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-SoftReturn'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-SoftReturn' })

    $Results | Should -HaveCount 0
  }
}

Describe 'SG-7 house analyzer rules' {
  BeforeAll {
    $script:AnalyzerRulePath = Join-Path -Path $PSScriptRoot -ChildPath '../analyzers/HouseRules.psm1'
    if (-not (Get-Module -Name PSScriptAnalyzer)) {
      Import-Module -Name PSScriptAnalyzer -ErrorAction Stop
    }
  }

  It 'flags Parameter attributes missing explicit options' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param (
        [Parameter()]
        [System.String]
        $Name
    )
    $Name
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitParameterAttribute'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitParameterAttribute' })

    $Results.RuleName | Should -Contain 'Measure-ExplicitParameterAttribute'
    [System.String]$MessageText = $Results.Message -join "`n"
    $MessageText | Should -Match 'DontShow'
    $MessageText | Should -Match 'ValueFromPipelineByPropertyName'
  }

  It 'flags Parameter Position because it re-enables positional binding' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param (
        [Parameter(
            DontShow = $False,
            Mandatory = $False,
            ParameterSetName = 'default',
            Position = 0,
            ValueFromPipeline = $False,
            ValueFromPipelineByPropertyName = $False
        )]
        [System.String]
        $Name
    )
    $Name
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitParameterAttribute'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitParameterAttribute' })

    $Results.RuleName | Should -Contain 'Measure-ExplicitParameterAttribute'
    $Results.Message | Should -Match 're-enables positional binding'
  }

  It 'accepts the complete explicit Parameter attribute surface' {
    $ScriptDefinition = @'
function Get-Thing {
    [CmdletBinding()]
    param (
        [Parameter(
            DontShow = $False,
            Mandatory = $False,
            ParameterSetName = 'default',
            ValueFromPipeline = $False,
            ValueFromPipelineByPropertyName = $False
        )]
        [System.String]
        $Name
    )
    $Name
}
'@

    $Results = Invoke-ScriptAnalyzer `
      -ScriptDefinition $ScriptDefinition `
      -CustomRulePath $script:AnalyzerRulePath `
      -IncludeRule 'Measure-ExplicitParameterAttribute'

    $Results = @($Results | Where-Object -FilterScript { $PSItem.RuleName -eq 'Measure-ExplicitParameterAttribute' })

    $Results | Should -HaveCount 0
  }
}
