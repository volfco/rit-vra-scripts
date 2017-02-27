<#
    Required Variables:
    - $ZoneTemplate     vsphere.%VRMOwner%.lab
#>

# =========================================================================================
# Dynamic Variables
# =========================================================================================
$SafeModePassword = "Student1!" | ConvertTo-SecureString -asPlainText -Force

# Read in VRM Data
[xml]$VMAttrs = Get-Content -Path C:\VRMGuestAgent\site\workitem.xml
$VRMOwner = ( $VMAttrs.workitem.properties.property | Where {$_.name -eq 'virtualmachine.admin.owner'} ).value.split('@')[0]

# Figure out the Zone of this dns server
$FQDN = $ZoneTemplate.Replace('%VRMOwner%', $VRMOwner)
if ($Domain -ne $null -or $Domain -ne "") {
    $FQDN = $FQDN.Replace('%Domain%', $Domain)
}

# =========================================================================================
# Code
# =========================================================================================

Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

# Why not use the recommended method for unattended install?
#  Good Question! Because it doesn't setup the DNS correctly in our setup. I think InstallADDS cmdlets expect the delegation to be setup before the cmdlet is run
#    We don't do that here. We setup the DNS after this Software Componet is run.
dcpromo /unattend /NewDomain:Forest /replicaOrNewDomain:Domain /ConfirmGC:Yes /ForestLevel:4 /InstallDNS:Yes /NewDomainDNSName:$FQDN /RebootOnCompletion:No /SafeModeAdminPassword:Password1!

# Um... 
# Ok. dcpromo exits with a code of 1 to 10 if it was successful. WTF, right? 10+ of there is an error.
#   Why?!? 
if ($LASTEXITCODE -le 10) {
    Write-Output 'dcpromo gucci. exiting cleanly'
    $LASTEXITCODE = 0
    $error.clear()
    exit 0
} else {
    Write-Output 'dcpromo not gucci'
    exit 1
}