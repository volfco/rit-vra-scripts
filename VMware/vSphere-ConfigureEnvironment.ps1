# =========================================================================================
# Preflight Checks
# =========================================================================================

# Attempt to read in the Summary.xml
$Summary = [System.Xml.XmlDocument](Get-Content 'C:\Summary-vCenter.xml');
$vCenterInstalled = $Summary.state.vcenter.installed
if ($vCenterInstalled -ne "true") {
    Write-Output 'State could not be verified'
    exit 1
}

$State = New-Object System.XMl.XmlTextWriter('C:\Summary-Env.xml',$Null)
$State.Formatting = 'Indented'
$State.Indentation = 1
$State.IndentChar = "`t"
$State.WriteStartDocument()
$State.WriteStartElement('state')

# =========================================================================================
# End Preflight Checks
# =========================================================================================

# Get our DNS Zone we will be working with
$DnsZone = ( Get-DnsServerZone | Where {$_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors"} ).ZoneName


# =========================================================================================
# Static Variables
# =========================================================================================


<#
# Generate SSH Key
#Write-Output '== Generating SSH Key =================='
#New-Item -ItemType directory -Path C:\Users\Administrator\.ssh
#& C:\OpenSSH\ssh-keygen.exe -b 2048 -t rsa -q -N "''" -f C:\Users\Administrator\.ssh\id_rsa

# Copy SSH key to ESXi Hosts and disable password login
Write-Output '== Configuring ESXi Instances ========='
foreach ($host in $ESXiHosts) {
#	# Each ESXi host should have the esxi_setup_key installed, root password login disabled, and all other configurations set. 
#	# All we need to do is replace the setup key with the user's key here
#	$publicKey = Get-Content C:\Users\Administrator\.ssh\id_rsa.pub
#    & ssh -i C:\Workspace\esxi_setup_key root@$host "echo '$publicKey' > /etc/ssh/keys-root/authorized_keys; exit"

	# Make a desktop shortcut 
	$WScriptShell = New-Object -ComObject WScript.Shell
	$Shortcut = $WScriptShell.CreateShortcut("$env:Administrator\Desktop\ESXi-$host.lnk")
	$Shortcut.TargetPath = "C:\OpenSSH\bin\ssh.exe -i C:\Users\Administrator\.ssh\id_rsa root@$host"
	$Shortcut.Save()

}
# Copy SSH key to VCSA
Write-Output '== Configuring VCSA ==================='

$publicKey = Get-Content C:\Users\Administrator\.ssh\id_rsa.pub
& ssh -i C:\Workspace\esxi_setup_key root@$host "echo '$publicKey' > /etc/ssh/keys-root/authorized_keys; exit"
#>

# =========================================================================================
# Code
# =========================================================================================

# Drop us into the PowerCLI environment
Write-Output '== Dropping into PowerCLI ============='
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope AllUsers -Confirm:$false

# Connect to the vCenter server we just made
Write-Output 'p= Connecting to vCenter =============='
Connect-VIServer -Server $Summary.state.vcenter.network.ipaddr -Protocol https -User $Summary.state.vcenter.credentials.username -Password $Summary.state.vcenter.credentials.password

# Make the datacenter
Write-Output 'p= Creating Datacenter ================'
$dcfolder = Get-Folder -NoRecursion
$DC = New-Datacenter -Location $dcfolder -Name 'Virtual DC'

Write-Output 'p= Creating Cluster ==================='
$Cluster = New-Cluster -Location $DC -Name Cluster

Write-Output 'p= Adding Hosts ======================='
New-Item -ItemType Directory -Path "$env:Public\Desktop\ESXi Nodes"

foreach ($node in $ESXiNodes) {
    
    Write-Output 'p== Adding DNS Record ================='
    $Name = "pvesxi-" + [string]($ESXiNodes.IndexOf($node) + 1)
    Add-DnsServerResourceRecord -Zone $DnsZone -A -Name $Name -IPv4Address $node

    Write-Output '=== Creating Shortcuts ================'
    # VpxClient
    $TargetFile = ${env:ProgramFiles(x86)} + '\VMware\Infrastructure\Virtual Infrastructure Client\Launcher\VpxClient.exe'
    $ShortcutFile = "$env:Public\Desktop\ESXi Nodes\" + $Name + " (VpxClient).lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.Arguments = "-s $node -u root -p student"
    $Shortcut.Save()

    # Firefox
    $TargetFile = ${env:ProgramFiles} + '\Mozilla Firefox\firefox.exe'
    $ShortcutFile = "$env:Public\Desktop\ESXi Nodes\" + $Name + " (WebUI).lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.Arguments = "https://" + $node + "/ui"
    $Shortcut.Save()

    # Add the host to vCenter
    Write-Output 'p== Adding Host to vCenter ============'
    $Check = Test-NetConnection $node -Port 443  # Test the https port
    if ($Check.TcpTestSucceeded -eq $false) {
        Write-Output 'Management port is not open. Sleeping for a bit'
        Start-Sleep -s 60
    }
    $__host = Add-VMHost -Name $node -Location $Cluster -User root -Password student -Force
    
    Write-Output 'p== Updating Hostname and Domain Name ='
    Get-VMHostNetwork $__host  | Set-VMHostNetwork -DomainName $DnsZone -HostName $Name
    Write-Output "DEBUG: $DnsZone / $Name"

    Write-Output '== Writing State ====================='
    $State.WriteStartElement('esxinode') # <esxinode>
        $State.WriteElementString('fqdn', "$Name.$DnsZone")
        $State.WriteElementString('ipaddr', $node)
    $State.WriteEndElement() # </esxinode>

}

$State.WriteEndElement()
$State.Flush()
$State.Flush()
$State.Close()

$global:LASTEXITCODE = $null
$error.clear()