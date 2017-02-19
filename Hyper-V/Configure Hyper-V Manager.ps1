<#

    $Hosts            List of Hyper-V Hostnames
    $ManagementIPNetmask  IP Address of the Management Network
    $ManagementIPAddress

#>

# =========================================================================================
# Functions
# =========================================================================================
# Src: http://www.indented.co.uk/2010/01/23/powershell-subnet-math/
function ConvertTo-DottedDecimalIP {
  <#
    .Synopsis
      Returns a dotted decimal IP address from either an unsigned 32-bit integer or a dotted binary string.
    .Description
      ConvertTo-DottedDecimalIP uses a regular expression match on the input string to convert to an IP address.
    .Parameter IPAddress
      A string representation of an IP address from either UInt32 or dotted binary.
  #>

  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [String]$IPAddress
  )
  
  process {
    Switch -RegEx ($IPAddress) {
      "([01]{8}.){3}[01]{8}" {
        return [String]::Join('.', $( $IPAddress.Split('.') | ForEach-Object { [Convert]::ToUInt32($_, 2) } ))
      }
      "\d" {
        $IPAddress = [UInt32]$IPAddress
        $DottedIP = $( For ($i = 3; $i -gt -1; $i--) {
          $Remainder = $IPAddress % [Math]::Pow(256, $i)
          ($IPAddress - $Remainder) / [Math]::Pow(256, $i)
          $IPAddress = $Remainder
         } )
       
        return [String]::Join('.', $DottedIP)
      }
      default {
        Write-Error "Cannot convert this format"
      }
    }
  }
}

function ConvertTo-DecimalIP {
  <#
    .Synopsis
      Converts a Decimal IP address into a 32-bit unsigned integer.
    .Description
      ConvertTo-DecimalIP takes a decimal IP, uses a shift-like operation on each octet and returns a single UInt32 value.
    .Parameter IPAddress
      An IP Address to convert.
  #>
  
  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Net.IPAddress]$IPAddress
  )

  process {
    $i = 3; $DecimalIP = 0;
    $IPAddress.GetAddressBytes() | ForEach-Object { $DecimalIP += $_ * [Math]::Pow(256, $i); $i-- }

    return [UInt32]$DecimalIP
  }
}
function ConvertTo-MaskLength {
  <#
    .Synopsis
      Returns the length of a subnet mask.
    .Description
      ConvertTo-MaskLength accepts any IPv4 address as input, however the output value 
      only makes sense when using a subnet mask.
    .Parameter SubnetMask
      A subnet mask to convert into length
  #>
 
  [CmdLetBinding()]
  param(
    [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
    [Alias("Mask")]
    [Net.IPAddress]$SubnetMask
  )
 
  process {
    $Bits = "$( $SubnetMask.GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2) } )" -replace '[\s0]'
 
    return $Bits.Length
  }
}

function Get-NetworkRange( [String]$IP, [String]$Mask ) {
  if ($IP.Contains("/")) {
    $Temp = $IP.Split("/")
    $IP = $Temp[0]
    $Mask = $Temp[1]
  }

  if (!$Mask.Contains(".")) {
    $Mask = ConvertTo-Mask $Mask
  }

  $DecimalIP = ConvertTo-DecimalIP $IP
  $DecimalMask = ConvertTo-DecimalIP $Mask
  
  $Network = $DecimalIP -band $DecimalMask
  $Broadcast = $DecimalIP -bor ((-bnot $DecimalMask) -band [UInt32]::MaxValue)

  for ($i = $($Network + 1); $i -lt $Broadcast; $i++) {
    ConvertTo-DottedDecimalIP $i
  }
}

# =========================================================================================
# Define Needed Variables
# =========================================================================================
$ManagementNetworkIPAddresses = Get-NetworkRange $ManagementIPAddress $ManagementIPNetmask
$ManagementNetworkPrefix = ConvertTo-MaskLength $ManagementIPNetmask


Write-Output '== Installing Hyper-V Tools ============'
Install-WindowsFeature Hyper-V-Tools, Hyper-V-Powershell

Start-Sleep -s 30

Write-Output '== Create AD OU For Hosts =============='
$OU = New-ADOrganizationalUnit -Name 'Hyper-V Hosts' -PassThru

Write-Output '== Get Hyper-V Hosts ==================='
# We are assuming that Hyper-V Hosts will follow the naming convention of HyperV0000. 
# We could do all computers, but there might be a lab deployment that consists of more
#   than just hyper-v hosts. In that case, we verify that hyper-v is installed before
#   we continue. So, this might be useless, but whatever. 
$Hosts = Get-ADComputer -Filter "SamAccountName -like 'HyperV*'"

$WorkingNode = $false

foreach ($__Host in $Hosts) {
    
    Write-Output " Host: $__Host.Name"
    Write-Output '>= Verifying Host gots Hyper-V ========='
    # Sanity Check to make sure we are not modifying a non hypervisor entity
    $State = Get-WindowsFeature -ComputerName $__Host.Name Hyper-V
    if ($State.InstallState -ne "Installed") {
        Write-Output '!! Host does not have Hyper-V Installed !!'
        # Don't fail hard, as we might have other nodes that would work
        continue
    } else {
        $WorkingNode = $true
    }

    Write-Output '>= Moving Host to AD Container ========='
    # For subseuqnet scripts, let's put all the hypervisors in one place
    Move-ADObject $__Host $OU
    
    Write-Output '>= Adding Migration Network ============'
    $BaseIP = $ManagementNetworkIPAddresses[0] 
    Write-Output "DEBUG  Subnet: $BaseIP/$ManagementNetworkPrefix"
    # Tell Hyper-V that we want to use the management network as the network to migrate state
    Add-VMMigrationNetwork -ComputerName $__Host.Name $BaseIP
    
    # Enable VM Migration
    Write-Output '>= Enabling Migration =================='
    Enable-VMMigration -ComputerName $__Host.Name

    Write-Output '>= Adding Virtual Switch ==============='
    # Add a Virtual Switch to allow VMs to talk to the routed network
    New-VMSwitch -AllowManagementOS $false -ComputerName $__Host.Name -Name "External Network" -NetAdapterName Ethernet1 -Confirm:$false
}


# Fail if we didn't do any work
if ($WorkingNode -eq $false) {
    Write-Output "We didn't find any working Hyper-V nodes"
    exit 1
}

exit 0
