#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function ConvertTo-HouseRuleDiagnosticRecord {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.IScriptExtent]
    $Extent,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $Message,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $RuleName
  )

  [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]::new(
    $Message,
    $Extent,
    $RuleName,
    [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Warning,
    $Null,
    $Null,
    $Null
  )

}

Function Get-HouseRuleFunctionAst {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.Language.FunctionDefinitionAst[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  [System.Management.Automation.Language.FunctionDefinitionAst[]]@(
    $ScriptBlockAst.FindAll(
      {
        Param (
          [System.Management.Automation.Language.Ast]
          $Ast
        )

        $Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]
      },
      $True
    )
  )

}

Function Test-HouseRuleAstBelongsToFunction {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.Ast]
    $Ast,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  $Private:ParentAst = $Ast
  [System.Boolean]$Private:BelongsToFunction = $False

  While ($Null -ne $ParentAst -and $BelongsToFunction -eq $False) {
    If ($ParentAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
      $BelongsToFunction = [System.Boolean]([System.Object]::ReferenceEquals($ParentAst, $FunctionAst))
    } Else {
      $ParentAst = $ParentAst.Parent
    }
  }

  [System.Boolean]$BelongsToFunction

}

Function Get-HouseRuleVariableName {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.VariableExpressionAst]
    $VariableAst
  )

  If (
    $VariableAst.VariablePath.IsDriveQualified -eq $False -and
    $VariableAst.VariablePath.IsVariable -eq $True -and
    $VariableAst.VariablePath.IsScript -eq $False -and
    $VariableAst.VariablePath.IsGlobal -eq $False
  ) {
    [System.String]($VariableAst.VariablePath.UserPath -replace '(?i)^(private|local):', '')
  }

}

Function Test-HouseRuleAutomaticVariable {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $Name
  )

  $Private:AutomaticVariables = [System.Collections.Generic.HashSet[System.String]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  [System.String[]]@(
    '_',
    'args',
    'ConsoleFileName',
    'EnabledExperimentalFeatures',
    'Error',
    'ErrorActionPreference',
    'ErrorView',
    'ExecutionContext',
    'false',
    'foreach',
    'HOME',
    'Host',
    'input',
    'IsCoreCLR',
    'IsLinux',
    'IsMacOS',
    'IsWindows',
    'LASTEXITCODE',
    'Matches',
    'MyInvocation',
    'NestedPromptLevel',
    'null',
    'PID',
    'PROFILE',
    'PSBoundParameters',
    'PSCmdlet',
    'PSCommandPath',
    'PSCulture',
    'PSDebugContext',
    'PSDefaultParameterValues',
    'PSEdition',
    'PSHOME',
    'PSItem',
    'PSScriptRoot',
    'PSSenderInfo',
    'PSStyle',
    'PSUICulture',
    'PSVersionTable',
    'PWD',
    'ShellId',
    'StackTrace',
    'switch',
    'this',
    'true'
  ) | ForEach-Object -Process {
    [void]$AutomaticVariables.Add($PSItem)
  }

  [System.Boolean]$AutomaticVariables.Contains($Name)

}

Function Get-HouseRuleParameterName {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  [System.String[]]@(
    If ($Null -ne $FunctionAst.Body.ParamBlock) {
      $FunctionAst.Body.ParamBlock.Parameters |
        ForEach-Object -Process {
          Get-HouseRuleVariableName -VariableAst $PSItem.Name
        }
    }
  )

}

Function Get-HouseRuleIteratorName {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  $Private:Names = [System.Collections.Generic.HashSet[System.String]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  $FunctionAst.Body.FindAll(
    {
      Param (
        [System.Management.Automation.Language.Ast]
        $Ast
      )

      $Ast -is [System.Management.Automation.Language.ForEachStatementAst] -or
      $Ast -is [System.Management.Automation.Language.ForStatementAst]
    },
    $True
  ) | Where-Object -FilterScript {
    Test-HouseRuleAstBelongsToFunction -Ast $PSItem -FunctionAst $FunctionAst
  } | ForEach-Object -Process {
    If ($PSItem -is [System.Management.Automation.Language.ForEachStatementAst]) {
      [void]$Names.Add((Get-HouseRuleVariableName -VariableAst $PSItem.Variable))
    } Else {
      If ($Null -ne $PSItem.Initializer) {
        $PSItem.Initializer.FindAll(
          {
            Param (
              [System.Management.Automation.Language.Ast]
              $Ast
            )

            $Ast -is [System.Management.Automation.Language.VariableExpressionAst]
          },
          $False
        ) | ForEach-Object -Process {
          [void]$Names.Add((Get-HouseRuleVariableName -VariableAst $PSItem))
        }
      }

      If ($Null -ne $PSItem.Iterator) {
        $PSItem.Iterator.FindAll(
          {
            Param (
              [System.Management.Automation.Language.Ast]
              $Ast
            )

            $Ast -is [System.Management.Automation.Language.VariableExpressionAst]
          },
          $False
        ) | ForEach-Object -Process {
          [void]$Names.Add((Get-HouseRuleVariableName -VariableAst $PSItem))
        }
      }
    }
  }

  [System.String[]]@($Names)

}

Function Get-HouseRuleStaticString {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Management.Automation.Language.Ast]
    $Ast
  )

  If ($Null -ne $Ast) {
    If ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
      [System.String]$Ast.Value
    } ElseIf ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
      [System.String]$Ast.Value
    } ElseIf ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
      $Ast.Elements | ForEach-Object -Process {
        Get-HouseRuleStaticString -Ast $PSItem
      }
    }
  }

}

Function Get-HouseRuleCommandArgument {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.Language.Ast[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.CommandAst]
    $CommandAst,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $ParameterName
  )

  For ($Index = 1; $Index -lt $CommandAst.CommandElements.Count; $Index++) {
    $Private:Element = $CommandAst.CommandElements[$Index]

    If ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
      Continue
    }

    If ($Element.ParameterName -ine $ParameterName) {
      Continue
    }

    If ($Null -ne $Element.Argument) {
      $Element.Argument
      Continue
    }

    If (($Index + 1) -lt $CommandAst.CommandElements.Count) {
      $Private:NextElement = $CommandAst.CommandElements[$Index + 1]
      If ($NextElement -isnot [System.Management.Automation.Language.CommandParameterAst]) {
        $NextElement
      }
    }
  }

}

Function Get-HouseRuleCommandArgumentString {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.CommandAst]
    $CommandAst,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $ParameterName
  )

  Get-HouseRuleCommandArgument -CommandAst $CommandAst -ParameterName $ParameterName |
    ForEach-Object -Process {
      Get-HouseRuleStaticString -Ast $PSItem
    }

}

Function Test-HouseRuleCommandHasPrivateOption {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.CommandAst]
    $CommandAst
  )

  $Private:Options = [System.String[]]@(
    Get-HouseRuleCommandArgumentString -CommandAst $CommandAst -ParameterName 'Option'
  )

  [System.Boolean]($Options -icontains 'Private')

}

Function Test-HouseRuleCommandUsesNonLocalScope {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.CommandAst]
    $CommandAst
  )

  $Private:Scopes = [System.String[]]@(
    Get-HouseRuleCommandArgumentString -CommandAst $CommandAst -ParameterName 'Scope'
  )

  [System.Boolean]($Scopes -icontains 'Script' -or $Scopes -icontains 'Global')

}

Function Get-HouseRuleAssignedExpressionVariable {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.Ast]
    $Ast
  )

  If ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
    [PSCustomObject]@{
      Name      = Get-HouseRuleVariableName -VariableAst $Ast
      Extent    = $Ast.Extent
      IsPrivate = [System.Boolean]$Ast.VariablePath.IsPrivate
    }
  } ElseIf ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
    Get-HouseRuleAssignedExpressionVariable -Ast $Ast.Child
  } ElseIf ($Ast -is [System.Management.Automation.Language.AttributedExpressionAst]) {
    Get-HouseRuleAssignedExpressionVariable -Ast $Ast.Child
  } ElseIf ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
    $Ast.Elements | ForEach-Object -Process {
      Get-HouseRuleAssignedExpressionVariable -Ast $PSItem
    }
  }

}

Function Get-HouseRuleAssignedVariable {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([PSCustomObject[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  $FunctionAst.Body.FindAll(
    {
      Param (
        [System.Management.Automation.Language.Ast]
        $Ast
      )

      $Ast -is [System.Management.Automation.Language.AssignmentStatementAst] -or
      $Ast -is [System.Management.Automation.Language.UnaryExpressionAst] -or
      $Ast -is [System.Management.Automation.Language.CommandAst]
    },
    $True
  ) | Where-Object -FilterScript {
    Test-HouseRuleAstBelongsToFunction -Ast $PSItem -FunctionAst $FunctionAst
  } | ForEach-Object -Process {
    If ($PSItem -is [System.Management.Automation.Language.AssignmentStatementAst]) {
      Get-HouseRuleAssignedExpressionVariable -Ast $PSItem.Left
    } ElseIf ($PSItem -is [System.Management.Automation.Language.UnaryExpressionAst]) {
      Get-HouseRuleAssignedExpressionVariable -Ast $PSItem.Child
    } Else {
      $Private:CommandAst = $PSItem
      $Private:CommandName = $CommandAst.GetCommandName()

      If (
        $CommandName -imatch '^(New|Set)-Variable$' -and
        (Test-HouseRuleCommandUsesNonLocalScope -CommandAst $CommandAst) -eq $False
      ) {
        $Private:Names = [System.String[]]@(
          Get-HouseRuleCommandArgumentString -CommandAst $CommandAst -ParameterName 'Name'
        )

        $Names | ForEach-Object -Process {
          [PSCustomObject]@{
            Name      = [System.String]$PSItem
            Extent    = $CommandAst.Extent
            IsPrivate = [System.Boolean](
              $CommandName -ieq 'New-Variable' -and
              (Test-HouseRuleCommandHasPrivateOption -CommandAst $CommandAst)
            )
          }
        }
      }
    }
  } | Where-Object -FilterScript {
    -not [System.String]::IsNullOrWhiteSpace($PSItem.Name)
  }

}

Function Get-HouseRulePrivateDeclarationName {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst,

    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Management.Automation.Language.Ast]
    $SearchAst = $Null
  )

  If ($Null -eq $SearchAst) {
    $SearchAst = $FunctionAst.Body
  }

  $Private:Names = [System.Collections.Generic.List[System.String]]::new()

  $SearchAst.FindAll(
    {
      Param (
        [System.Management.Automation.Language.Ast]
        $Ast
      )

      $Ast -is [System.Management.Automation.Language.AssignmentStatementAst] -or
      $Ast -is [System.Management.Automation.Language.CommandAst]
    },
    $True
  ) | Where-Object -FilterScript {
    Test-HouseRuleAstBelongsToFunction -Ast $PSItem -FunctionAst $FunctionAst
  } | ForEach-Object -Process {
    If ($PSItem -is [System.Management.Automation.Language.AssignmentStatementAst]) {
      ForEach ($AssignedVariable In Get-HouseRuleAssignedExpressionVariable -Ast $PSItem.Left) {
        If ($AssignedVariable.IsPrivate -eq $True) {
          [void]$Names.Add($AssignedVariable.Name)
        }
      }
    }

    If (
      $PSItem -is [System.Management.Automation.Language.CommandAst] -and
      $PSItem.GetCommandName() -imatch '^New-Variable$' -and
      (Test-HouseRuleCommandHasPrivateOption -CommandAst $PSItem) -eq $True
    ) {
      ForEach ($CommandArgumentName In Get-HouseRuleCommandArgumentString -CommandAst $PSItem -ParameterName 'Name') {
        [void]$Names.Add($CommandArgumentName)
      }
    }
  }

  [System.String[]]$Names.ToArray()

}

Function Test-HouseRulePipelineParameter {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  [System.Boolean]$Private:HasPipelineParameter = $False

  If ($Null -ne $FunctionAst.Body.ParamBlock) {
    ForEach ($ParameterAst In $FunctionAst.Body.ParamBlock.Parameters) {
      ForEach ($AttributeAst In $ParameterAst.Attributes) {
        If ($AttributeAst -isnot [System.Management.Automation.Language.AttributeAst]) {
          Continue
        }

        If ($AttributeAst.TypeName.FullName -ine 'Parameter') {
          Continue
        }

        ForEach ($NamedArgument In $AttributeAst.NamedArguments) {
          If ($NamedArgument.ArgumentName -inotmatch '^ValueFromPipeline(ByPropertyName)?$') {
            Continue
          }

          If ($Null -eq $NamedArgument.Argument) {
            $HasPipelineParameter = $True
          } ElseIf ($NamedArgument.Argument.Extent.Text -ieq $NamedArgument.ArgumentName) {
            $HasPipelineParameter = $True
          } Else {
            Try {
              If ($NamedArgument.Argument.SafeGetValue() -eq $True) {
                $HasPipelineParameter = $True
              }
            } Catch {
              Continue
            }
          }
        }
      }
    }
  }

  [System.Boolean]$HasPipelineParameter

}

Function Test-HouseRuleNamedBlock {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  [System.Boolean](
    $Null -ne $FunctionAst.Body.DynamicParamBlock -or
    $Null -ne $FunctionAst.Body.BeginBlock -or
    $Null -ne $FunctionAst.Body.ProcessBlock -or
    ($Null -ne $FunctionAst.Body.EndBlock -and $FunctionAst.Body.EndBlock.Unnamed -eq $False)
  )

}

Function Get-HouseRuleNamedBlockAst {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.Language.NamedBlockAst[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  [System.Collections.Generic.List[System.Management.Automation.Language.NamedBlockAst]]$Private:Blocks = [System.Collections.Generic.List[System.Management.Automation.Language.NamedBlockAst]]::new()

  If ($Null -ne $FunctionAst.Body.DynamicParamBlock) {
    [void]$Blocks.Add($FunctionAst.Body.DynamicParamBlock)
  }

  If ($Null -ne $FunctionAst.Body.BeginBlock) {
    [void]$Blocks.Add($FunctionAst.Body.BeginBlock)
  }

  If ($Null -ne $FunctionAst.Body.ProcessBlock) {
    [void]$Blocks.Add($FunctionAst.Body.ProcessBlock)
  }

  If ($Null -ne $FunctionAst.Body.EndBlock -and $FunctionAst.Body.EndBlock.Unnamed -eq $False) {
    [void]$Blocks.Add($FunctionAst.Body.EndBlock)
  }

  [System.Management.Automation.Language.NamedBlockAst[]]@(
    $Blocks | Sort-Object -Property { $PSItem.Extent.StartOffset }
  )

}

Function Get-HouseRuleFunctionAttribute {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.Language.AttributeAst[]])]
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
    $AttributeName,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  If ($Null -ne $FunctionAst.Body.ParamBlock) {
    $FunctionAst.Body.ParamBlock.Attributes |
      Where-Object -FilterScript {
        $PSItem -is [System.Management.Automation.Language.AttributeAst] -and
        (
          (
            ([System.String]$PSItem.TypeName.FullName) -replace
            '^(System\.Management\.Automation\.)?',
            ''
          ) -replace 'Attribute$',
          ''
        ) -ieq $AttributeName
      }
  }

}

Function Get-HouseRuleAttributeName {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.AttributeAst]
    $AttributeAst
  )

  [System.String](
    (
      ([System.String]$AttributeAst.TypeName.FullName) -replace
      '^(System\.Management\.Automation\.)?',
      ''
    ) -replace 'Attribute$',
    ''
  )

}

Function Get-HouseRuleParameterAttributeOrderKey {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.AttributeBaseAst]
    $AttributeAst
  )

  [System.String]$Private:OrderKey = '2|'

  If ($AttributeAst -is [System.Management.Automation.Language.TypeConstraintAst]) {
    $OrderKey = '3|'
  } ElseIf ($AttributeAst -is [System.Management.Automation.Language.AttributeAst]) {
    $Private:AttributeName = Get-HouseRuleAttributeName -AttributeAst $AttributeAst

    If ($AttributeName -ieq 'Parameter') {
      $OrderKey = '0|Parameter'
    } ElseIf ($AttributeName -ieq 'Alias') {
      $OrderKey = '1|Alias'
    } Else {
      $OrderKey = [System.String]('2|{0}' -f $AttributeName)
    }
  }

  [System.String]$OrderKey

}

Function Test-HouseRuleAlphabeticalOrder {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.String[]]
    $Value
  )

  [System.Boolean]$Private:IsOrdered = $True

  For ($Index = 1; $Index -lt $Value.Count; $Index++) {
    If ([System.StringComparer]::OrdinalIgnoreCase.Compare($Value[$Index - 1], $Value[$Index]) -gt 0) {
      $IsOrdered = $False
    }
  }

  [System.Boolean]$IsOrdered

}

Function Test-HouseRuleNamedArgumentValueIsTrue {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.NamedAttributeArgumentAst]
    $NamedArgument
  )

  [System.Boolean]$Private:IsTrue = $False

  If ($Null -eq $NamedArgument.Argument) {
    $IsTrue = $True
  } ElseIf ($NamedArgument.Argument.Extent.Text -ieq $NamedArgument.ArgumentName) {
    $IsTrue = $True
  } Else {
    Try {
      $IsTrue = [System.Boolean]$NamedArgument.Argument.SafeGetValue()
    } Catch {
      $IsTrue = $False
    }
  }

  [System.Boolean]$IsTrue

}

Function Get-HouseRuleNamedAttributeArgument {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Management.Automation.Language.NamedAttributeArgumentAst])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $ArgumentName,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.AttributeAst]
    $AttributeAst
  )

  [System.Management.Automation.Language.NamedAttributeArgumentAst]$Private:MatchedArgument = $Null

  ForEach ($NamedArgument In $AttributeAst.NamedArguments) {
    If ($NamedArgument.ArgumentName -ieq $ArgumentName -and $Null -eq $MatchedArgument) {
      $MatchedArgument = [System.Management.Automation.Language.NamedAttributeArgumentAst]$NamedArgument
    }
  }

  $MatchedArgument

}

Function Test-HouseRuleNamedArgumentValueEqual {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Object]
    $ExpectedValue,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.NamedAttributeArgumentAst]
    $NamedArgument
  )

  [System.Boolean]$Private:IsEqual = $False

  If ($Null -ne $NamedArgument.Argument) {
    Try {
      $Private:ActualValue = $NamedArgument.Argument.SafeGetValue()
      $IsEqual = [System.Boolean]([System.Object]::Equals($ActualValue, $ExpectedValue))
    } Catch {
      $IsEqual = $False
    }
  }

  [System.Boolean]$IsEqual

}

Function Get-HouseRuleExplicitParameterAttributeDiagnostic {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.String]
    $OwnerLabel,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyCollection()]
    [System.Management.Automation.Language.ParameterAst[]]
    $ParameterAst
  )

  [System.String[]]$Private:RequiredOptionNames = @(
    'DontShow',
    'Mandatory',
    'ParameterSetName',
    'ValueFromPipeline',
    'ValueFromPipelineByPropertyName'
  )
  [System.Collections.Generic.Dictionary[System.String, System.String]]$Private:ForbiddenReasonByName = (
    [System.Collections.Generic.Dictionary[System.String, System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
  )
  $ForbiddenReasonByName.Add(
    'HelpMessage',
    'comment-based .PARAMETER help owns help text'
  )
  $ForbiddenReasonByName.Add(
    'Position',
    'it re-enables positional binding even when CmdletBinding(PositionalBinding = $False)'
  )
  $ForbiddenReasonByName.Add(
    'ValueFromRemainingArguments',
    'the project does not use remaining-argument capture'
  )

  ForEach ($Parameter In $ParameterAst) {
    [System.String]$Private:ParameterName = Get-HouseRuleVariableName -VariableAst $Parameter.Name
    [System.Management.Automation.Language.AttributeAst[]]$Private:ParameterAttributes = @(
      $Parameter.Attributes |
        Where-Object -FilterScript {
          $PSItem -is [System.Management.Automation.Language.AttributeAst] -and
          (Get-HouseRuleAttributeName -AttributeAst $PSItem) -ieq 'Parameter'
        }
    )

    If ($ParameterAttributes.Count -eq 0) {
      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-ExplicitParameterAttribute' `
        -Extent $Parameter.Extent `
        -Message (
        "{0} parameter '{1}' is missing the Parameter attribute required by SG-7." -f
        $OwnerLabel,
        $ParameterName
      )

      Continue
    }

    ForEach ($AttributeAst In $ParameterAttributes) {
      [System.Collections.Generic.HashSet[System.String]]$Private:SeenOptionNames = (
        [System.Collections.Generic.HashSet[System.String]]::new(
          [System.StringComparer]::OrdinalIgnoreCase
        )
      )

      ForEach ($NamedArgument In $AttributeAst.NamedArguments) {
        [void]$SeenOptionNames.Add($NamedArgument.ArgumentName)

        If ($ForbiddenReasonByName.ContainsKey($NamedArgument.ArgumentName) -eq $False) {
          Continue
        }

        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-ExplicitParameterAttribute' `
          -Extent $NamedArgument.Extent `
          -Message (
          "{0} parameter '{1}' must not declare Parameter({2}); {3} (SG-7)." -f
          $OwnerLabel,
          $ParameterName,
          $NamedArgument.ArgumentName,
          $ForbiddenReasonByName[$NamedArgument.ArgumentName]
        )
      }

      ForEach ($RequiredOptionName In $RequiredOptionNames) {
        If ($SeenOptionNames.Contains($RequiredOptionName) -eq $True) {
          Continue
        }

        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-ExplicitParameterAttribute' `
          -Extent $AttributeAst.Extent `
          -Message (
          "{0} parameter '{1}' Parameter attribute is missing explicit option '{2}' required by SG-7." -f
          $OwnerLabel,
          $ParameterName,
          $RequiredOptionName
        )
      }
    }
  }

}

Function Test-HouseRuleParameterAttributeOrder {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ParameterAst]
    $ParameterAst
  )

  # Initialize Variable(s)
  [System.String]$Private:CurrentKey = [System.String]::Empty
  [System.Boolean]$Private:HasPreviousKey = $False
  [System.Boolean]$Private:IsOrdered = $True
  [System.String]$Private:PreviousKey = [System.String]::Empty

  ForEach ($AttributeAst In $ParameterAst.Attributes) {
    $CurrentKey = Get-HouseRuleParameterAttributeOrderKey -AttributeAst $AttributeAst

    If (
      $HasPreviousKey -eq $True -and
      [System.StringComparer]::OrdinalIgnoreCase.Compare($PreviousKey, $CurrentKey) -gt 0
    ) {
      $IsOrdered = $False
    }

    $HasPreviousKey = $True
    $PreviousKey = $CurrentKey
  }

  [System.Boolean]$IsOrdered

}

Function Test-HouseRuleParameterTypeLast {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ParameterAst]
    $ParameterAst
  )

  [System.Boolean]$Private:HasSeenType = $False
  [System.Boolean]$Private:IsTypeLast = $True

  ForEach ($AttributeAst In $ParameterAst.Attributes) {
    If ($AttributeAst -is [System.Management.Automation.Language.TypeConstraintAst]) {
      $HasSeenType = $True
      Continue
    }

    If (
      $HasSeenType -eq $True -and
      $AttributeAst -is [System.Management.Automation.Language.AttributeAst]
    ) {
      $IsTypeLast = $False
    }
  }

  [System.Boolean]$IsTypeLast

}

Function Test-HouseRuleParameterOrderGuard {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  [System.Boolean]$Private:HasParameterOrderGuard = $False

  ForEach ($CmdletBindingAttribute In Get-HouseRuleFunctionAttribute -FunctionAst $FunctionAst -AttributeName 'CmdletBinding') {
    ForEach ($NamedArgument In $CmdletBindingAttribute.NamedArguments) {
      If ($NamedArgument.ArgumentName -ine 'PositionalBinding') {
        Continue
      }

      If ((Test-HouseRuleNamedArgumentValueIsTrue -NamedArgument $NamedArgument) -eq $True) {
        $HasParameterOrderGuard = $True
      }
    }
  }

  If ($Null -ne $FunctionAst.Body.ParamBlock) {
    ForEach ($ParameterAst In $FunctionAst.Body.ParamBlock.Parameters) {
      ForEach ($AttributeAst In $ParameterAst.Attributes) {
        If ($AttributeAst -isnot [System.Management.Automation.Language.AttributeAst]) {
          Continue
        }

        If ((Get-HouseRuleAttributeName -AttributeAst $AttributeAst) -ine 'Parameter') {
          Continue
        }

        ForEach ($NamedArgument In $AttributeAst.NamedArguments) {
          If ($NamedArgument.ArgumentName -ieq 'Position') {
            $HasParameterOrderGuard = $True
          }
        }
      }
    }
  }

  [System.Boolean]$HasParameterOrderGuard

}

Function Get-HouseRuleProcessResetVariableName {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.String[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.NamedBlockAst]
    $ProcessBlock
  )

  $Private:Names = [System.Collections.Generic.List[System.String]]::new()
  [System.Boolean]$Private:CanSkipEnteringProcess = $True

  ForEach ($Statement In $ProcessBlock.Statements) {
    If (
      $CanSkipEnteringProcess -eq $True -and
      (Test-HouseRuleEnteringProcessDebugStatement -StatementAst $Statement) -eq $True
    ) {
      $CanSkipEnteringProcess = $False
      Continue
    }

    $CanSkipEnteringProcess = $False

    If ($Statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
      Get-HouseRuleAssignedExpressionVariable -Ast $Statement.Left |
        ForEach-Object -Process {
          [void]$Names.Add($PSItem.Name)
        }
      Continue
    }

    If ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) {
      Break
    }

    If ($Statement.PipelineElements.Count -ne 1) {
      Break
    }

    $Private:CommandAst = $Statement.PipelineElements[0]
    If ($CommandAst -isnot [System.Management.Automation.Language.CommandAst]) {
      Break
    }

    If ($CommandAst.GetCommandName() -inotmatch '^Clear-Variable$') {
      Break
    }

    Get-HouseRuleCommandArgumentString -CommandAst $CommandAst -ParameterName 'Name' |
      ForEach-Object -Process {
        [void]$Names.Add($PSItem)
      }
  }

  [System.String[]]$Names.ToArray()

}

Function Test-HouseRuleEnteringProcessDebugStatement {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.StatementAst]
    $StatementAst
  )

  [System.Boolean]$Private:IsEnteringProcessDebug = $False

  If (
    $StatementAst -is [System.Management.Automation.Language.PipelineAst] -and
    $StatementAst.PipelineElements.Count -eq 1
  ) {
    [System.Management.Automation.Language.CommandAst]$Private:CommandAst = $StatementAst.PipelineElements[0] -as [System.Management.Automation.Language.CommandAst]
    If ($Null -ne $CommandAst -and $CommandAst.GetCommandName() -imatch '^Write-Debug$') {
      ForEach ($Message In Get-HouseRuleCommandArgumentString -CommandAst $CommandAst -ParameterName 'Message') {
        If ($Message -imatch '\]\s+Entering Process$') {
          $IsEnteringProcessDebug = $True
        }
      }
    }
  }

  [System.Boolean]$IsEnteringProcessDebug

}

Function Test-HouseRuleExitingDebugStatement {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.StatementAst]
    $StatementAst
  )

  [System.Boolean]$Private:IsExitingDebug = $False

  If (
    $StatementAst -is [System.Management.Automation.Language.PipelineAst] -and
    $StatementAst.PipelineElements.Count -eq 1
  ) {
    [System.Management.Automation.Language.CommandAst]$Private:CommandAst = $StatementAst.PipelineElements[0] -as [System.Management.Automation.Language.CommandAst]
    If ($Null -ne $CommandAst -and $CommandAst.GetCommandName() -imatch '^Write-Debug$') {
      ForEach ($Message In Get-HouseRuleCommandArgumentString -CommandAst $CommandAst -ParameterName 'Message') {
        If ($Message -imatch '\]\s+Exiting(\s+.+)?$') {
          $IsExitingDebug = $True
        }
      }
    }
  }

  [System.Boolean]$IsExitingDebug

}

Function Test-HouseRuleFunctionDeclaresPrivateResult {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.FunctionDefinitionAst]
    $FunctionAst
  )

  [System.Boolean]$Private:DeclaresPrivateResult = $False

  ForEach ($DeclarationName In Get-HouseRulePrivateDeclarationName -FunctionAst $FunctionAst) {
    If ($DeclarationName -ieq 'Result') {
      $DeclaresPrivateResult = $True
    }
  }

  [System.Boolean]$DeclaresPrivateResult

}

Function Test-HouseRuleLastStatementExitingDebug {
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([System.Boolean])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $False,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowNull()]
    [System.Management.Automation.Language.NamedBlockAst]
    $BlockAst
  )

  [System.Boolean]$Private:IsLastStatementExitingDebug = $False

  If ($Null -ne $BlockAst -and $BlockAst.Statements.Count -gt 0) {
    [System.Management.Automation.Language.StatementAst]$Private:LastStatement = $BlockAst.Statements[$BlockAst.Statements.Count - 1]
    $IsLastStatementExitingDebug = Test-HouseRuleExitingDebugStatement -StatementAst $LastStatement
  }

  [System.Boolean]$IsLastStatementExitingDebug

}

Function Measure-CanonicalAttributeOrder {
  <#
    .SYNOPSIS
        Flags non-canonical ordering in function declaration attributes and parameters.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    ForEach ($CmdletBindingAttribute In Get-HouseRuleFunctionAttribute -FunctionAst $FunctionAst -AttributeName 'CmdletBinding') {
      $Private:CmdletBindingOptionNames = [System.String[]]@(
        $CmdletBindingAttribute.NamedArguments |
          ForEach-Object -Process { $PSItem.ArgumentName }
      )

      If ((Test-HouseRuleAlphabeticalOrder -Value $CmdletBindingOptionNames) -eq $False) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-CanonicalAttributeOrder' `
          -Extent $CmdletBindingAttribute.Extent `
          -Message (
          "Function '{0}' CmdletBinding options are not in alphabetical order (SG-5a)." -f
          $FunctionAst.Name
        )
      }
    }

    If ($Null -eq $FunctionAst.Body.ParamBlock) {
      Continue
    }

    ForEach ($ParameterAst In $FunctionAst.Body.ParamBlock.Parameters) {
      ForEach ($AttributeAst In $ParameterAst.Attributes) {
        If ($AttributeAst -isnot [System.Management.Automation.Language.AttributeAst]) {
          Continue
        }

        If ((Get-HouseRuleAttributeName -AttributeAst $AttributeAst) -ine 'Parameter') {
          Continue
        }

        $Private:ParameterArgumentNames = [System.String[]]@(
          $AttributeAst.NamedArguments |
            ForEach-Object -Process { $PSItem.ArgumentName }
        )

        If ((Test-HouseRuleAlphabeticalOrder -Value $ParameterArgumentNames) -eq $False) {
          ConvertTo-HouseRuleDiagnosticRecord `
            -RuleName 'Measure-CanonicalAttributeOrder' `
            -Extent $AttributeAst.Extent `
            -Message (
            "Function '{0}' parameter '{1}' Parameter attribute arguments are not in alphabetical order (SG-5b)." -f
            $FunctionAst.Name,
            (Get-HouseRuleVariableName -VariableAst $ParameterAst.Name)
          )
        }

        ForEach ($NamedArgument In $AttributeAst.NamedArguments) {
          If ($NamedArgument.ArgumentName -ine 'Position') {
            Continue
          }

          ConvertTo-HouseRuleDiagnosticRecord `
            -RuleName 'Measure-CanonicalAttributeOrder' `
            -Extent $NamedArgument.Extent `
            -Message (
            "Function '{0}' parameter '{1}' must not use Parameter(Position); PositionalBinding must stay false (SG-5e)." -f
            $FunctionAst.Name,
            (Get-HouseRuleVariableName -VariableAst $ParameterAst.Name)
          )
        }

      }

      If ((Test-HouseRuleParameterTypeLast -ParameterAst $ParameterAst) -eq $False) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-CanonicalAttributeOrder' `
          -Extent $ParameterAst.Extent `
          -Message (
          "Function '{0}' parameter '{1}' has an attribute after the type literal; the type must be last before the variable (SG-5c)." -f
          $FunctionAst.Name,
          (Get-HouseRuleVariableName -VariableAst $ParameterAst.Name)
        )
      }

      If ((Test-HouseRuleParameterAttributeOrder -ParameterAst $ParameterAst) -eq $False) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-CanonicalAttributeOrder' `
          -Extent $ParameterAst.Extent `
          -Message (
          "Function '{0}' parameter '{1}' attributes are not in canonical Parameter/Alias/attribute/type order (SG-5c)." -f
          $FunctionAst.Name,
          (Get-HouseRuleVariableName -VariableAst $ParameterAst.Name)
        )
      }
    }

    $Private:ParameterNames = [System.String[]]@(Get-HouseRuleParameterName -FunctionAst $FunctionAst)
    If ((Test-HouseRuleAlphabeticalOrder -Value $ParameterNames) -eq $True) {
      Continue
    }

    ConvertTo-HouseRuleDiagnosticRecord `
      -RuleName 'Measure-CanonicalAttributeOrder' `
      -Extent $FunctionAst.Body.ParamBlock.Extent `
      -Message (
      "Function '{0}' parameters are not in alphabetical order by name (SG-5d)." -f
      $FunctionAst.Name
    )
  }

}

Function Measure-CanonicalKeywordCasing {
  <#
    .SYNOPSIS
        Flags PowerShell keywords that do not use the house canonical casing.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  If ($Null -eq $ScriptBlockAst.Parent -and $ScriptBlockAst.Extent.StartOffset -eq 0) {
    $Private:CanonicalKeywords = [System.Collections.Generic.Dictionary[System.String, System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )

    [System.String[]]@(
      'Assembly',
      'Base',
      'Begin',
      'Break',
      'Catch',
      'Class',
      'Command',
      'Configuration',
      'Continue',
      'Data',
      'Define',
      'Do',
      'DynamicKeyword',
      'DynamicParam',
      'Else',
      'ElseIf',
      'End',
      'Enum',
      'Exit',
      'Filter',
      'Finally',
      'For',
      'ForEach',
      'From',
      'Function',
      'Hidden',
      'If',
      'In',
      'InlineScript',
      'Interface',
      'Module',
      'Namespace',
      'Param',
      'Parallel',
      'Private',
      'Process',
      'Public',
      'Return',
      'Sequence',
      'Static',
      'Switch',
      'Throw',
      'Trap',
      'Try',
      'Type',
      'Until',
      'Using',
      'Var',
      'While',
      'Workflow'
    ) | ForEach-Object -Process {
      $CanonicalKeywords.Add($PSItem, $PSItem)
    }

    [System.Management.Automation.Language.Token[]]$Private:Tokens = @()
    [System.Management.Automation.Language.ParseError[]]$Private:ParseErrors = @()
    $Null = [System.Management.Automation.Language.Parser]::ParseInput(
      $ScriptBlockAst.Extent.Text,
      [ref]$Tokens,
      [ref]$ParseErrors
    )

    ForEach ($Token In $Tokens) {
      [System.Management.Automation.Language.TokenFlags]$Private:TokenTraits = (
        [System.Management.Automation.Language.TokenTraits]::GetTraits($Token.Kind)
      )

      If (($TokenTraits -band [System.Management.Automation.Language.TokenFlags]::Keyword) -eq 0) {
        Continue
      }

      If ($CanonicalKeywords.ContainsKey($Token.Text) -eq $False) {
        Continue
      }

      [System.String]$Private:ExpectedKeyword = $CanonicalKeywords[$Token.Text]
      If ($Token.Text -ceq $ExpectedKeyword) {
        Continue
      }

      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-CanonicalKeywordCasing' `
        -Extent $Token.Extent `
        -Message ("Keyword '{0}' must be canonical casing '{1}'." -f $Token.Text, $ExpectedKeyword)
    }
  }

}

Function Measure-ExplicitCmdletBinding {
  <#
    .SYNOPSIS
        Flags functions missing the house explicit CmdletBinding surface.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  # Initialize Variable(s)
  [System.Management.Automation.Language.AttributeAst]$Private:CmdletBindingAttribute = $Null
  [System.Management.Automation.Language.AttributeAst[]]$Private:CmdletBindingAttributes = @()
  [System.Boolean]$Private:HasOutputType = $False
  [System.String[]]$Private:RequiredOptionNames = @(
    'SupportsShouldProcess',
    'ConfirmImpact',
    'PositionalBinding',
    'DefaultParameterSetName',
    'HelpUri',
    'SupportsPaging'
  )
  [System.Collections.Generic.HashSet[System.String]]$Private:SeenOptionNames = $Null

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    $CmdletBindingAttributes = [System.Management.Automation.Language.AttributeAst[]]@(
      Get-HouseRuleFunctionAttribute -FunctionAst $FunctionAst -AttributeName 'CmdletBinding'
    )
    $CmdletBindingAttribute = $Null
    If ($CmdletBindingAttributes.Count -gt 0) {
      $CmdletBindingAttribute = $CmdletBindingAttributes[0]
    }

    If ($Null -eq $CmdletBindingAttribute) {
      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-ExplicitCmdletBinding' `
        -Extent $FunctionAst.Extent `
        -Message (
        "Function '{0}' is missing the explicit CmdletBinding attribute required by SG-4." -f
        $FunctionAst.Name
      )
    } Else {
      $SeenOptionNames = [System.Collections.Generic.HashSet[System.String]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
      )
      ForEach ($NamedArgument In $CmdletBindingAttribute.NamedArguments) {
        [void]$SeenOptionNames.Add($NamedArgument.ArgumentName)
      }

      ForEach ($RequiredOptionName In $RequiredOptionNames) {
        If ($SeenOptionNames.Contains($RequiredOptionName) -eq $True) {
          Continue
        }

        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-ExplicitCmdletBinding' `
          -Extent $CmdletBindingAttribute.Extent `
          -Message (
          "Function '{0}' CmdletBinding is missing explicit option '{1}' required by SG-4." -f
          $FunctionAst.Name,
          $RequiredOptionName
        )
      }

      $Private:PositionalBindingArgument = Get-HouseRuleNamedAttributeArgument `
        -ArgumentName 'PositionalBinding' `
        -AttributeAst $CmdletBindingAttribute

      If (
        $Null -ne $PositionalBindingArgument -and
        (Test-HouseRuleNamedArgumentValueEqual `
          -ExpectedValue $False `
          -NamedArgument $PositionalBindingArgument) -eq $False
      ) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-ExplicitCmdletBinding' `
          -Extent $PositionalBindingArgument.Extent `
          -Message (
          "Function '{0}' CmdletBinding must set PositionalBinding = `$False required by SG-4." -f
          $FunctionAst.Name
        )
      }
    }

    $HasOutputType = [System.Boolean](
      @(
        Get-HouseRuleFunctionAttribute -FunctionAst $FunctionAst -AttributeName 'OutputType'
      ).Count -gt 0
    )
    If ($HasOutputType -eq $True) {
      Continue
    }

    ConvertTo-HouseRuleDiagnosticRecord `
      -RuleName 'Measure-ExplicitCmdletBinding' `
      -Extent $FunctionAst.Extent `
      -Message (
      "Function '{0}' is missing the OutputType attribute required by SG-4." -f
      $FunctionAst.Name
    )
  }

}

Function Measure-ExplicitParameterAttribute {
  <#
    .SYNOPSIS
        Flags parameters missing the house explicit Parameter attribute surface.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  If ($Null -eq $ScriptBlockAst.Parent) {
    If ($Null -ne $ScriptBlockAst.ParamBlock) {
      Get-HouseRuleExplicitParameterAttributeDiagnostic `
        -OwnerLabel 'Script' `
        -ParameterAst $ScriptBlockAst.ParamBlock.Parameters
    }

    ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
      If ($Null -eq $FunctionAst.Body.ParamBlock) {
        Continue
      }

      Get-HouseRuleExplicitParameterAttributeDiagnostic `
        -OwnerLabel ("Function '{0}'" -f $FunctionAst.Name) `
        -ParameterAst $FunctionAst.Body.ParamBlock.Parameters
    }
  }

}

Function Measure-PrivateVariableDeclaration {
  <#
    .SYNOPSIS
        Flags function-local assignments that are not Private-scoped.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    $Private:PrivateDeclarations = [System.Collections.Generic.HashSet[System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
    Get-HouseRulePrivateDeclarationName -FunctionAst $FunctionAst | ForEach-Object -Process {
      [void]$PrivateDeclarations.Add($PSItem)
    }

    $Private:ExemptNames = [System.Collections.Generic.HashSet[System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
    Get-HouseRuleParameterName -FunctionAst $FunctionAst | ForEach-Object -Process {
      [void]$ExemptNames.Add($PSItem)
    }
    Get-HouseRuleIteratorName -FunctionAst $FunctionAst | ForEach-Object -Process {
      [void]$ExemptNames.Add($PSItem)
    }

    ForEach ($AssignedVariable In Get-HouseRuleAssignedVariable -FunctionAst $FunctionAst) {
      If ($ExemptNames.Contains($AssignedVariable.Name)) {
        Continue
      }

      If (Test-HouseRuleAutomaticVariable -Name $AssignedVariable.Name) {
        Continue
      }

      If ($AssignedVariable.IsPrivate -eq $True -or $PrivateDeclarations.Contains($AssignedVariable.Name)) {
        Continue
      }

      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-PrivateVariableDeclaration' `
        -Extent $AssignedVariable.Extent `
        -Message (
        "Function '{0}' assigns local variable '{1}' without declaring it Private-scoped." -f
        $FunctionAst.Name,
        $AssignedVariable.Name
      )
    }
  }

}

Function Measure-PipelineVariableLifecycle {
  <#
    .SYNOPSIS
        Flags pipeline function locals not declared in Begin or cleared at Process start.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    If ((Test-HouseRulePipelineParameter -FunctionAst $FunctionAst) -eq $False) {
      Continue
    }

    If ($Null -eq $FunctionAst.Body.BeginBlock -or $Null -eq $FunctionAst.Body.ProcessBlock) {
      Continue
    }

    $Private:BeginDeclarations = [System.Collections.Generic.HashSet[System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
    Get-HouseRulePrivateDeclarationName -FunctionAst $FunctionAst -SearchAst $FunctionAst.Body.BeginBlock |
      ForEach-Object -Process {
        [void]$BeginDeclarations.Add($PSItem)
      }

    $Private:ResetNames = [System.Collections.Generic.HashSet[System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
    Get-HouseRuleProcessResetVariableName -ProcessBlock $FunctionAst.Body.ProcessBlock |
      ForEach-Object -Process {
        [void]$ResetNames.Add($PSItem)
      }

    $Private:ExemptNames = [System.Collections.Generic.HashSet[System.String]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )
    Get-HouseRuleParameterName -FunctionAst $FunctionAst | ForEach-Object -Process {
      [void]$ExemptNames.Add($PSItem)
    }
    Get-HouseRuleIteratorName -FunctionAst $FunctionAst | ForEach-Object -Process {
      [void]$ExemptNames.Add($PSItem)
    }

    $Private:AssignedNames = [System.Collections.Generic.Dictionary[
    System.String,
    System.Management.Automation.Language.IScriptExtent
    ]]::new([System.StringComparer]::OrdinalIgnoreCase)

    ForEach ($AssignedVariable In Get-HouseRuleAssignedVariable -FunctionAst $FunctionAst) {
      If ($ExemptNames.Contains($AssignedVariable.Name)) {
        Continue
      }

      If (Test-HouseRuleAutomaticVariable -Name $AssignedVariable.Name) {
        Continue
      }

      If (-not $AssignedNames.ContainsKey($AssignedVariable.Name)) {
        $AssignedNames.Add($AssignedVariable.Name, $AssignedVariable.Extent)
      }
    }

    ForEach ($AssignedName In $AssignedNames.Keys) {
      If ($BeginDeclarations.Contains($AssignedName) -eq $False) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-PipelineVariableLifecycle' `
          -Extent $AssignedNames[$AssignedName] `
          -Message (
          "Pipeline function '{0}' uses local variable '{1}' without declaring it in Begin." -f
          $FunctionAst.Name,
          $AssignedName
        )
      }
    }

    ForEach ($DeclaredName In $BeginDeclarations) {
      If ($ResetNames.Contains($DeclaredName)) {
        Continue
      }

      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-PipelineVariableLifecycle' `
        -Extent $FunctionAst.Body.ProcessBlock.Extent `
        -Message (
        "Pipeline function '{0}' declares local variable '{1}' in Begin but does not reset it at the top of Process." -f
        $FunctionAst.Name,
        $DeclaredName
      )
    }
  }

}

Function Measure-FlatNonPipelineFunction {
  <#
    .SYNOPSIS
        Flags named blocks on functions that do not accept pipeline input.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    If ((Test-HouseRulePipelineParameter -FunctionAst $FunctionAst) -eq $True) {
      Continue
    }

    If ((Test-HouseRuleNamedBlock -FunctionAst $FunctionAst) -eq $False) {
      Continue
    }

    ConvertTo-HouseRuleDiagnosticRecord `
      -RuleName 'Measure-FlatNonPipelineFunction' `
      -Extent $FunctionAst.Extent `
      -Message (
      "Function '{0}' has no pipeline input, so it must be flat; remove the named blocks and let code run in the implicit End block (SG-2c)." -f
      $FunctionAst.Name
    )
  }

}

Function Measure-CanonicalNamedBlock {
  <#
    .SYNOPSIS
        Flags non-canonical named block casing and brace layout.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    [System.Management.Automation.Language.NamedBlockAst[]]$Private:Blocks = @(
      Get-HouseRuleNamedBlockAst -FunctionAst $FunctionAst
    )

    ForEach ($Block In $Blocks) {
      [System.String]$Private:ExpectedHeader = '{0} {{' -f $Block.BlockKind.ToString()
      [System.String]$Private:HeaderPattern = '^\s*{0}\s*\{{' -f [System.Text.RegularExpressions.Regex]::Escape($Block.BlockKind.ToString())

      If ($Block.Extent.Text -cnotmatch $HeaderPattern) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-CanonicalNamedBlock' `
          -Extent $Block.Extent `
          -Message (
          "Function '{0}' named block must start with '{1}'." -f
          $FunctionAst.Name,
          $ExpectedHeader
        )
      }
    }

    For ($Index = 1; $Index -lt $Blocks.Count; $Index++) {
      [System.Management.Automation.Language.NamedBlockAst]$Private:PreviousBlock = $Blocks[$Index - 1]
      [System.Management.Automation.Language.NamedBlockAst]$Private:CurrentBlock = $Blocks[$Index]

      If ($PreviousBlock.Extent.EndLineNumber -eq $CurrentBlock.Extent.StartLineNumber) {
        Continue
      }

      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-CanonicalNamedBlock' `
        -Extent $CurrentBlock.Extent `
        -Message (
        "Function '{0}' named block transition must be cuddled as '}} {1} {{'." -f
        $FunctionAst.Name,
        $CurrentBlock.BlockKind.ToString()
      )
    }
  }

}

Function Measure-NoRemoveVariableCleanup {
  <#
    .SYNOPSIS
        Flags Remove-Variable cleanup in function End blocks.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    If ($Null -eq $FunctionAst.Body.EndBlock) {
      Continue
    }

    $FunctionAst.Body.EndBlock.FindAll(
      {
        Param (
          [System.Management.Automation.Language.Ast]
          $Ast
        )

        $Ast -is [System.Management.Automation.Language.CommandAst]
      },
      $True
    ) | Where-Object -FilterScript {
      Test-HouseRuleAstBelongsToFunction -Ast $PSItem -FunctionAst $FunctionAst
    } | Where-Object -FilterScript {
      $PSItem.GetCommandName() -imatch '^Remove-Variable$'
    } | ForEach-Object -Process {
      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-NoRemoveVariableCleanup' `
        -Extent $PSItem.Extent `
        -Message (
        "Function '{0}' uses Remove-Variable for end-of-scope cleanup." -f
        $FunctionAst.Name
      )
    }
  }

}

Function Measure-NoNewVariableDeclaration {
  <#
    .SYNOPSIS
        Flags New-Variable local declarations inside functions.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    $FunctionAst.Body.FindAll(
      {
        Param (
          [System.Management.Automation.Language.Ast]
          $Ast
        )

        $Ast -is [System.Management.Automation.Language.CommandAst]
      },
      $True
    ) | Where-Object -FilterScript {
      Test-HouseRuleAstBelongsToFunction -Ast $PSItem -FunctionAst $FunctionAst
    } | Where-Object -FilterScript {
      $PSItem.GetCommandName() -imatch '^New-Variable$' -and
      (Test-HouseRuleCommandUsesNonLocalScope -CommandAst $PSItem) -eq $False
    } | ForEach-Object -Process {
      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-NoNewVariableDeclaration' `
        -Extent $PSItem.Extent `
        -Message (
        "Function '{0}' uses New-Variable for a local declaration; use a typed `$Private:Name assignment instead." -f
        $FunctionAst.Name
      )
    }
  }

}

Function Measure-SoftReturn {
  <#
    .SYNOPSIS
        Flags hard returns and missing SG-6 soft-return debug anchors.
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/NWarila/powershell-template/blob/main/docs/README.md',
    PositionalBinding = $False,
    SupportsPaging = $False,
    SupportsShouldProcess = $False
  )]
  [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
  Param (
    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [System.Management.Automation.Language.ScriptBlockAst]
    $ScriptBlockAst
  )

  ForEach ($FunctionAst In Get-HouseRuleFunctionAst -ScriptBlockAst $ScriptBlockAst) {
    $FunctionAst.Body.FindAll(
      {
        Param (
          [System.Management.Automation.Language.Ast]
          $Ast
        )

        $Ast -is [System.Management.Automation.Language.ReturnStatementAst]
      },
      $True
    ) | Where-Object -FilterScript {
      Test-HouseRuleAstBelongsToFunction -Ast $PSItem -FunctionAst $FunctionAst
    } | ForEach-Object -Process {
      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-SoftReturn' `
        -Extent $PSItem.Extent `
        -Message (
        "Function '{0}' uses 'return'; SG-6 requires single-exit (soft return)." -f
        $FunctionAst.Name
      )
    }

    If ((Test-HouseRuleFunctionDeclaresPrivateResult -FunctionAst $FunctionAst) -eq $False) {
      Continue
    }

    [System.Boolean]$Private:HasExplicitEndBlock = [System.Boolean](
      $Null -ne $FunctionAst.Body.EndBlock -and
      $FunctionAst.Body.EndBlock.Unnamed -eq $False
    )
    [System.Boolean]$Private:HasPipelineShape = [System.Boolean](
      $Null -ne $FunctionAst.Body.ProcessBlock -or
      $HasExplicitEndBlock -eq $True
    )
    [System.String]$Private:Message = (
      "Function '{0}' last statement must be Write-Debug '... Exiting ...' (SG-6 soft return)." -f
      $FunctionAst.Name
    )

    If ($HasPipelineShape -eq $True) {
      If (
        $Null -ne $FunctionAst.Body.ProcessBlock -and
        (Test-HouseRuleLastStatementExitingDebug -BlockAst $FunctionAst.Body.ProcessBlock) -eq $False
      ) {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-SoftReturn' `
          -Extent $FunctionAst.Body.ProcessBlock.Extent `
          -Message $Message
      }

      If ($HasExplicitEndBlock -eq $True) {
        If ((Test-HouseRuleLastStatementExitingDebug -BlockAst $FunctionAst.Body.EndBlock) -eq $False) {
          ConvertTo-HouseRuleDiagnosticRecord `
            -RuleName 'Measure-SoftReturn' `
            -Extent $FunctionAst.Body.EndBlock.Extent `
            -Message $Message
        }
      } Else {
        ConvertTo-HouseRuleDiagnosticRecord `
          -RuleName 'Measure-SoftReturn' `
          -Extent $FunctionAst.Extent `
          -Message $Message
      }
    } ElseIf ((Test-HouseRuleLastStatementExitingDebug -BlockAst $FunctionAst.Body.EndBlock) -eq $False) {
      ConvertTo-HouseRuleDiagnosticRecord `
        -RuleName 'Measure-SoftReturn' `
        -Extent $FunctionAst.Body.EndBlock.Extent `
        -Message $Message
    }
  }

}

Export-ModuleMember -Function 'Measure-*'
