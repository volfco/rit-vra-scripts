<#
    Required Variables:
    - $ZoneTemplate     vsphere.%VRMOwner%.lab
#>

# =========================================================================================
# Dynamic Variables
# =========================================================================================

# Read in VRM Data
[xml]$VMAttrs = Get-Content -Path C:\VRMGuestAgent\site\workitem.xml
$VRMOwner = ( $VMAttrs.workitem.properties.property | Where {$_.name -eq 'virtualmachine.admin.owner'} ).value.split('@')[0]

# Figure out the Zone of this dns server
$DNSZone = $ZoneTemplate.Replace('%VRMOwner%', $VRMOwner)

$Summary = New-Object System.XMl.XmlTextWriter('C:\Component-DNS.xml',$Null)
$Summary.Formatting = 'Indented'
$Summary.Indentation = 1
$Summary.IndentChar = "`t"
$Summary.WriteStartDocument()
$Summary.WriteStartElement('state')

# =========================================================================================
# Code
# =========================================================================================
Write-Output '== Overview ============================'
Write-Output "= DNS Zone: $DNSZone"
Write-Output '========================================'
Write-Output '== Installing DNS Server ==============='
Install-WindowsFeature DNS -IncludeManagementTools

Write-Output '== Configuring Zone ===================='
Add-DnsServerPrimaryZone -Name $DNSZone -ZoneFile "$DNSZone.dns"

Write-Output '== Writing State ======================='
$Summary.WriteAttributeString('username', $VRMOwner)
    
    $Summary.WriteElementString('Zone', $DNSZone)
    $BaseZone = $DNSZone.split('.')[1..2]
    $Summary.WriteElementString('ServerFQDN', "$env:computername.$BaseZone")

$Summary.WriteEndDocument() # </state>
$Summary.Flush()
$Summary.Close()