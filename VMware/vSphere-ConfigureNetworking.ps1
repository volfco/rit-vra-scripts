# =========================================================================================
# Preflight Checks
# =========================================================================================

# Attempt to read in the Summary.xml
$Summary = [System.Xml.XmlDocument](Get-Content 'C:\Summary-vCenter.xml');
if ($Summary.state.vcenter.installed -ne "true") {
    Write-Output 'State could not be verified'
    exit 1
}

# Load Summary.xml

## For Writing
$State = New-Object System.XMl.XmlTextWriter('C:\Summary-DVS.xml',$Null)
$State.Formatting = 'Indented'
$State.Indentation = 1
$State.IndentChar = "`t"
$State.WriteStartDocument()
$State.WriteStartElement('state')

    $State.WriteStartElement('dvs')

# Allow End User to not configure 
if ($Configure_Networking -ne "True") {
    Write-Output 'Configure_Networking is not True. Cleanly exiting without doing anything.'

    
    $State.WriteAttributeString('installed', 'false')
    $State.WriteEndElement() # </dvs>
    $State.WriteEndElement() # </state>
    $State.Flush()
    $State.Flush()
    $State.Close()

    exit 0
}

# Drop into PowerCLI
Write-Output '== Dropping into PowerCLI ============='
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”

# Connect to 
Write-Output 'p= Connecting to vCenter =============='
Connect-VIServer -Server $Summary.state.vcenter.network.ipaddr -Protocol https -User $Summary.state.vcenter.credentials.username -Password $Summary.state.vcenter.credentials.password

foreach ($node in $ESXiNodes) {

    Write-Output 'p== Enabling VMotion and FTLogging ===='
    Get-VMHostNetworkAdapter | where {$_.ip -eq $node} | Set-VMHostNetworkAdapter -VMotionEnabled $true -FaultToleranceLoggingEnabled $true -Confirm:$false

}

Write-Output 'p= Creating dvS ======================='
$Ahosts = Get-VMHost
$DC = Get-Datacenter
$vds = New-VDSwitch -Name dvSwitch -Location $DC -Version 6.0.0 -MaxPorts 66 -MTU 6660 

foreach ($Ahost in $Ahosts ) {

    Add-VDSwitchVMHost -VMHost $Ahost -VDSwitch $vds
    $vmnic1 = Get-VMHostNetworkAdapter -Host $Ahost -Physical -Name vmnic1
    $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $vmnic1 -Confirm:$false

}

New-VDPortgroup -VDSwitch $vds -Name dvPortgroup -NumPorts 28

# iSCSI
<#
if ($Install_iSCSI -eq "True") {
    Write-Output 'p= Setting up iSCSI ==================='
    foreach ($ESXIhost in $ESXihosts) {
        # Enable software iSCSI
        Get-VMHostStorage -VMHost $ESXIhost | Set-VMHostStorage -SoftwareIScsiEnabled $True
        # Wait for the adapter to come up
        Start-Sleep -Seconds 10

        # Get our new paravirtual hba
        $hba = $esx | Get-VMHostHba -Type iScsi | Where {$_.Model -eq "iSCSI Software Adapter"}

        # Add the vmk0 to the paravirtual hba
        $esxcli = Get-EsxCli -VMhost $ESXIhost
        $esxcli.iscsi.networkportal.add($hba, $Null, 'vmk0')

        New-IScsiHbaTarget -IScsiHba $hba -Address $iSCSITarget  
        Get-VMHostStorage -VMHost $ESXIhost -RescanAllHba -RescanVmfs
    }
}
#>

$State.WriteEndElement() # </state>
$State.Flush()
$State.Flush()
$State.Close()

$global:LASTEXITCODE = $null
$error.clear()

exit 0