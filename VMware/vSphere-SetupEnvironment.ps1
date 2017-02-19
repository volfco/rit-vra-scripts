<#
Copyright 2017 Rochester Institute of Technology
  Colum McGaley <cxm7688@rit.edu>

This product, and all resources contained herein, are provided for reference,
and non-commercial uses only. Modifications are permitted for Personal and
Educational use only, as long as they are distributed for the same purpose and
not for used for commercial purposes. Any other use is prohibited unless
authorized by owner or the Institute.

See README for more information. https://bitbucket.org/colum/vsphere-deployment

Note. This Powershell script expects:
        - WindowsServer-DeployDNS.ps1 to be executed
        - A DNS Delegation be configured, and running on this node.

Required vRA Variables:
    $MGMT_BaseIP                Base IP address of the Management Subnet. This
                                could be any IP address on the network.
    $MGMT_BaseNetmask           Netmask of the Management Subnet
    $ESXiNodes                  This is an array of IP addresses of target ESXi
                                nodes that we are working with.

Overview:
  This script basically does two things.
    1. Install prereqsuite software that is used later on. 7-Zip, Firefox,
       Flash, PowerCLI, VPX Client.
    2. Executes the VCSA installer to deploy vCenter to the 1st ESXiNode.

  This script supports 6.0 and 6.5. It was tested on 6.0u2 and 6.5u0.

  This script short circuits the VRMGuestAgent's error catching because VCSA
  will send out non zero exit code even when the process completes.

  This script expects the system to be restarted after it is run and before
  anything else is done. I'm not exactly sure why, but it has to be done or
  stuff will break.
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

  [CmdLetBinding()] param(
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

  [CmdLetBinding()] param(
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

  [CmdLetBinding()] param(
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
# Static Variables
# =========================================================================================
# The desired hostname of the vCenter server
$vCenterHostname = 'vcenter'

# Base Path where we will find all the components we need for this script.
$SourcePath = "\\itsnas01.main.ad.rit.edu\vRAscripts$\Blueprints\vSphere_Cluster"

# The default username and password for the ESXi Nodes.
$ESXiUser = 'root';
$ESXiPass = 'student';

# Define the DNS server we wish to use. 
#  172.31.1.2 not 172.31.1.1 because everything else uses .1, so let's be cool and use .2
$DNSSrv = '172.31.1.2'

# =========================================================================================
# Preflight Checks
# =========================================================================================
# Verify DNS is configured
Write-Output '== Verifying Environment ==============='
Get-WindowsFeature DNS > $null
if ($? -ne $true) {
    Write-Output '  DNS is not configured. Can not continue, as we depend on DNS'
    exit 1
}

# =========================================================================================
# Define Needed Variables
# =========================================================================================
# Get our needed Addresses, and figure out the vCenter IP address
# !!$MGMT_BaseIP and $MGMT_Netmask are generated by vRA!!
$ManagementNetworkIPAddresses = Get-NetworkRange $MGMT_BaseIP $MGMT_Netmask
$ManagementNetworkPrefix = ConvertTo-MaskLength $MGMT_Netmask
$VCSAIP = $ManagementNetworkIPAddresses[-3]

$DnsZone = ( Get-DnsServerZone | Where {$_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors"} ).ZoneName

$NewPassword = ([char[]](Get-Random -Input $(48..57 + 65..90 + 97..122) -Count 12)) -join "" # https://gallery.technet.microsoft.com/scriptcenter/Simple-random-code-b2c9c9c9

$Summary = New-Object System.XMl.XmlTextWriter('C:\Summary-vCenter.xml',$Null)
$Summary.Formatting = 'Indented'
$Summary.Indentation = 1
$Summary.IndentChar = "`t"
$Summary.WriteStartDocument()
$Summary.WriteStartElement('state')
# =========================================================================================
# End Define Needed Variables
# =========================================================================================

# =========================================================================================
# Code
# =========================================================================================

# Setup workspace
Write-Output '== Setting up Workspace ================'
New-Item -ItemType directory -Path C:\Workspace > $null
New-Item -ItemType directory -Path C:\ITS\Logs  > $null # SCCM scripts log here

# Mount Fileshare
Write-Output '== Setting up Fileshare ================'
net use $SourcePath /user:vrauser Student1!

# Install Firefox
Write-Output '== Installing Firefox =================='
& Invoke-Expression $SourcePath'\Programs\Firefox\SCCM_Install.cmd'

# Install 7-Zip
Write-Output '== Installing 7-Zip ===================='
& Invoke-Expression $SourcePath'\Programs\7-Zip\SCCM_Install.cmd'

# Install PowerCLI
Write-Output '== Installing PowerCLI ================='
& Invoke-Expression $SourcePath'\Programs\PowerCLI\SCCM_Install.cmd'

# Install Adobe Flash
Write-Output '== Installing Flash ===================='
& Invoke-Expression $SourcePath'\Programs\Flash\SCCM_Install_Plugin.cmd'  # Firefox
& Invoke-Expression $SourcePath'\Programs\Flash\SCCM_Install_ActiveX.cmd' # Internet Explorer

# Install vSphere/ESXi Client
Write-Output '== Installing vSphere Client ==========='
Install-WindowsFeature NET-Framework-Core
& Invoke-Expression $SourcePath'\Programs\vSphere_Client\SCCM_Install.cmd'

# Install OpenSSH
Write-Output '== Copying OpenSSH ====================='
Copy-Item -Path $SourcePath'\Programs\OpenSSH' -Destination C:\OpenSSH

Write-Output '== Updating System PATH with OpenSSH ==='
## Update the system PATH
$oldpath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
$newPath = $oldpath + ";C:\OpenSSH\bin"
Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH –Value $newPath
## Set the path
$env:Path += ";C:\OpenSSH\bin"
Write-Output "Our path is: $env:Path"


if ($Install_VCSA -eq "True") {

    Write-Output '== Copying VCSA Template ==============='
    Copy-Item -Path $SourcePath'\'$VCSA_Version'_lab_embedded_std.template.json' -Destination C:\Workspace\lab_embedded_std.json

    Write-Output '== Updating VCSA Template =============='
    $TemplateContents = Get-Content C:\Workspace\lab_embedded_std.json
    $TemplateContents = $TemplateContents.Replace('%FQDN%', $ESXiHosts[0])
    $TemplateContents = $TemplateContents.Replace('%VCSA_IP%', $VCSAIP)
    $TemplateContents = $TemplateContents.Replace('%VCSA_HOSTNAME%', "$vCenterHostname.$DnsZone")
    $TemplateContents = $TemplateContents.Replace('%VCSA_PREFIX%', $ManagementNetworkPrefix)
    $TemplateContents = $TemplateContents.Replace('%VCSA_UPLINK%', $ManagementNetworkIPAddresses[0])
    $TemplateContents = $TemplateContents.Replace('%VCSA_DNS%', $DNSSrv)
    # $TemplateContents = $TemplateContents.Replace('%VCSA_PASSWORD%', $NewPassword)
    $TemplateContents | Set-Content C:\Workspace\lab_embedded_std.json

    Write-Output '== Writing State ======================='
    $Summary.WriteStartElement('vcenter') # <vcenter>
    $Summary.WriteAttributeString('installed', 'true')
    $Summary.WriteAttributeString('version', $VCSA_Version)
    $Summary.WriteElementString('config_path', 'C:\Workspace\lab_embedded_std.json')
        $Summary.WriteStartElement('network') # <network>
            $Summary.WriteElementString('fqdn', $ESXiHosts[0])
            $Summary.WriteElementString('ipaddr', $VCSAIP)
            $Summary.WriteElementString('netmask', $ManagementNetworkPrefix)
            $Summary.WriteElementString('gateway', $ManagementNetworkIPAddresses[0])
            $Summary.WriteElementString('dns', $DNSSrv)
            $Summary.WriteElementString('hostname', "$vCenterHostname.$DnsZone")
        $Summary.WriteEndElement() # </network>
        $Summary.WriteStartElement('credentials') # <credentials>
            $Summary.WriteElementString('username', 'Administrator@vSphere.local')
            $Summary.WriteElementString('password', 'Student1!')  # $NewPassword
        $Summary.WriteEndElement() # </credentials>
    $Summary.WriteEndElement() # </vcenter>

    if ($VCSA_Version -eq "6.0") {
        # Add a shortcut to VpxClient pointing to the VCSA Server
        $TargetFile = ${env:ProgramFiles(x86)} + '\VMware\Infrastructure\Virtual Infrastructure Client\Launcher\VpxClient.exe'
        $ShortcutFile = "$env:Public\Desktop\vSphere (VpxClient).lnk"
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
        $Shortcut.TargetPath = $TargetFile
        $Shortcut.Arguments = "-s $vCenterHostname.$DnsZone -u Administrator@vSphere.local -p Student1!"
        $Shortcut.Save()

    } else {
        Write-Output "!! VCSA 6.5 does not support the thick client. Skipping. !!"
    }

    # Firefox Shortcut to VCSA
    # TODO Import SSL Certificate into Firefox Trust Store and Local Store
    $TargetFile = ${env:ProgramFiles} + '\Mozilla Firefox\firefox.exe'
    $ShortcutFile = "$env:Public\Desktop\vSphere (Web).lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.Arguments = "https://$vCenterHostname.$DnsZone"
    $Shortcut.Save()

    # Write VCSA DNS Entry
    Add-DnsServerResourceRecord -Zone $DnsZone -A -Name $vCenterHostname -IPv4Address $VCSAIP

    # Make sure our target is reads.
    $TargetCheck = Test-NetConnection $ESXiHosts[0] -Port 80
    if ($Check.TcpTestSucceeded -eq $false) {
        Write-Output 'Target not responding on port 80, sleeping a bit'
        Start-Sleep -s 15
    }

    # Install VCSA
    Write-Output '== Installing vCenter Server Appliance ='
    try {
        if ($VCSA_Version -eq "6.5") {
            & $SourcePath'\VCSA_6.5\vcsa-cli-installer\win32\vcsa-deploy.exe' install --verbose --no-esx-ssl-verify --accept-eula C:\Workspace\lab_embedded_std.json
        } ElseIf ($VCSA_Version -eq "6.0")  {
            & $SourcePath'\VCSA_6.0\vcsa-cli-installer\win32\vcsa-deploy.exe' install --verbose --no-esx-ssl-verify --accept-eula C:\Workspace\lab_embedded_std.json
        } else {
            Write-Output "!! Unsupported VCSA Version !!"
            exit 1
        }
    } catch { # This will sometimes catch errors. 
        Write-Output "Error caught."
        Write-Output $_.Exception.Message
        Write-Output $_.Exception.ItemName
        exit 1
    }

    # Final verification of VCSA. The above might fail for some unpredictable reason, so we need to have a final check
    $Check = Test-NetConnection $VCSAIP -Port 443  # Test the https port
    if ($Check.TcpTestSucceeded -eq $false) {
        Write-Output 'VCSA Verification failed. Assuming install failed...'
        exit 1
    }
} else {
    Write-Output '!! Skipping VCSA Install !!'

    Write-Output '== Writing State ======================='
    $Summary.WriteStartElement('vcenter') # <vcenter>
    $Summary.WriteAttributeString('installed', 'false')
    $Summary.WriteAttributeString('version', $VCSA_Version)
        $Summary.WriteStartElement('network') # <network>
            $Summary.WriteElementString('fqdn', $ESXiHosts[0])
            $Summary.WriteElementString('ipaddr', $VCSAIP)
            $Summary.WriteElementString('netmask', $ManagementNetworkPrefix)
            $Summary.WriteElementString('gateway', $ManagementNetworkIPAddresses[0])
            $Summary.WriteElementString('dns', $DNSSrv)
            $Summary.WriteElementString('hostname', "$vCenterHostname.$DnsZone")
        $Summary.WriteEndElement() # </network>
    $Summary.WriteEndElement() # </vcenter>
}

$Summary.WriteEndElement()
$Summary.Flush()
$Summary.Flush()
$Summary.Close()

Write-Output 'Initial Configuration Done! Rebooting...'

$global:LASTEXITCODE = $null
$error.clear()
exit 0
