<#
.SYNOPSIS
    PSScriptAnalyzer settings for this PowerShell project.

.DESCRIPTION
    Keeps local and CI analysis aligned with the portfolio PowerShell baseline.
    The settings file is intentionally self-clean under these same rules.
#>
@{
  Severity            = @('Error', 'Warning')

  CustomRulePath      = @(
    './analyzers/HouseRules.psm1'
  )

  IncludeDefaultRules = $true

  IncludeRules        = @('*')

  ExcludeRules        = @(
    'PSUseProcessBlockForPipelineCommand'
    'PSUseCorrectCasing'
    'PSUseShouldProcessForStateChangingFunctions'
  )

  Rules               = @{
    PSPlaceOpenBrace                     = @{
      Enable             = $true
      OnSameLine         = $true
      NewLineAfter       = $true
      IgnoreOneLineBlock = $true
    }

    PSPlaceCloseBrace                    = @{
      Enable             = $true
      NewLineAfter       = $false
      IgnoreOneLineBlock = $true
      NoEmptyLineBefore  = $false
    }

    PSUseConsistentIndentation           = @{
      Enable          = $true
      Kind            = 'space'
      IndentationSize = 2
    }

    PSUseConsistentWhitespace            = @{
      Enable                                  = $true
      CheckInnerBrace                         = $true
      CheckOpenBrace                          = $true
      CheckOpenParen                          = $true
      CheckOperator                           = $true
      CheckParameter                          = $true
      CheckPipe                               = $true
      CheckSeparator                          = $true
      IgnoreAssignmentOperatorInsideHashTable = $true
    }

    PSAlignAssignmentStatement           = @{
      Enable         = $true
      CheckEnums     = $false
      CheckHashtable = $true
    }

    'Measure-PrivateVariableDeclaration' = @{
      Enable = $true
    }

    'Measure-PipelineVariableLifecycle'  = @{
      Enable = $true
    }

    'Measure-FlatNonPipelineFunction'    = @{
      Enable = $true
    }

    'Measure-CanonicalNamedBlock'        = @{
      Enable = $true
    }

    'Measure-ExplicitCmdletBinding'      = @{
      Enable = $true
    }

    'Measure-ExplicitParameterAttribute' = @{
      Enable = $true
    }

    'Measure-CanonicalAttributeOrder'    = @{
      Enable = $true
    }

    'Measure-CanonicalKeywordCasing'     = @{
      Enable = $true
    }

    'Measure-NoRemoveVariableCleanup'    = @{
      Enable = $true
    }

    'Measure-NoNewVariableDeclaration'   = @{
      Enable = $true
    }

    'Measure-SoftReturn'                 = @{
      Enable = $true
    }
  }
}
