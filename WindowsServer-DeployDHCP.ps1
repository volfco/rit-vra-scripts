<#

DHCPNIC

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
# Setup Variables
# =========================================================================================
if ($InvertRangeIP -eq "True") {
    $IPs = Get-WmiObject win32_NetworkAdapterConfiguration | where {$_.IPAddress -ne $null} | foreach {$_.IPAddress[0]}
    if ($IPs.Length -ne 2) {
        # The logic below only works when Windows has 2 NICs.
	    Write-Error "!! Host does not have the required number of NICs! !!"
	    exit 1
    }
    $IPBase = $IPs | Where-Object {$_ -ne $RangeIP}	# That is so f*cking cool 
} else {
    $IPBase = $RangeIP
}
$VMNetworkIPAddresses = Get-NetworkRange $IPBase $RangeNetmask

# =========================================================================================
# Functions
# =========================================================================================

Write-Output '== Installing DHCP ====================='
Install-WindowsFeature DHCP -IncludeManagementTools

## Configure DHCP on the VM Network
Write-Output '== Configuring DHCP ===================='
netsh dhcp add securitygroups
Restart-Service dhcpserver
Set-DhcpServerv4Binding -BindingState $true -InterfaceAlias $DHCPNIC

Write-Output '== Adding DHCP Range for VM Network ===='
# 0 is Gate
Write-Output "== Range: "$VMNetworkIPAddresses[1]" - "$VMNetworkIPAddresses[-1]
Write-Output "== Netmask: $RangeNetmask"
Add-DhcpServerv4Scope -Name "The Scope" -StartRange $VMNetworkIPAddresses[1] -EndRange $VMNetworkIPAddresses[-1] -SubnetMask $RangeNetmask
Set-DhcpServerv4OptionValue -DnsServer $DNSServer0 -Router $VMNetworkIPAddresses[0]