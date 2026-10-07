#Requires -Version 5.1
# SPDX-FileCopyrightText: 2026 Nicholas Warila
# SPDX-License-Identifier: MIT

Function Test-VirtualMachine {
  <#
    .SYNOPSIS
        Tells from the computer manufacturer and model whether it is a virtual machine.

    .DESCRIPTION
        Recognises the manufacturer and model strings that the common hypervisors report through
        Win32_ComputerSystem: Hyper-V and Azure ("Virtual Machine" by Microsoft Corporation), VMware,
        VirtualBox, QEMU and KVM, Xen, Amazon EC2, Google Compute Engine, Parallels, OpenStack, oVirt
        and Nutanix AHV.

    .PARAMETER Manufacturer
        Win32_ComputerSystem.Manufacturer.

    .PARAMETER Model
        Win32_ComputerSystem.Model.

    .EXAMPLE
        Test-VirtualMachine -Manufacturer 'Microsoft Corporation' -Model 'Virtual Machine'

    .OUTPUTS
        [System.Boolean]
    #>
  [CmdletBinding(
    ConfirmImpact = 'None',
    DefaultParameterSetName = 'default',
    HelpUri = 'https://github.com/nwarila-platform/windows-wsus-maintenance/blob/main/docs/reference/functions.md#test-virtualmachine',
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
    [AllowEmptyString()]
    [System.String]
    $Manufacturer,

    [Parameter(
      DontShow = $False,
      Mandatory = $True,
      ParameterSetName = 'default',
      ValueFromPipeline = $False,
      ValueFromPipelineByPropertyName = $False
    )]
    [AllowEmptyString()]
    [System.String]
    $Model
  )

  Write-Debug -Message:'[Test-VirtualMachine] Entering'

  # Initialize Variable(s)
  [System.String]$Private:Text = [System.String]::Empty
  [System.Boolean]$Private:Result = $False

  $Text = '{0} | {1}' -f $Manufacturer, $Model
  [System.Boolean]$Result = [System.Text.RegularExpressions.Regex]::IsMatch($Text, '(?i)virtual machine|vmware|virtualbox|innotek|qemu|kvm|xen|amazon ec2|google compute engine|parallels|openstack|ovirt|nutanix|\bahv\b|bochs')

  $Result
  Write-Debug -Message:'[Test-VirtualMachine] Exiting'
}
