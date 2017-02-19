# =========================================================================================
# Dynamic Variables
# =========================================================================================
$DomainUsername = "Administrator@hyper-v"
$DomainPassword = "Student1!" | ConvertTo-SecureString -asPlainText -Force

# =========================================================================================
# Dynamic Variables
# =========================================================================================

# Read in VRM Data
[xml]$VMAttrs = Get-Contents -Path C:\VRMGuestAgent\site\workitem.xml
$VRMOwner = ( $VMAttrs.workitem.properties.property | Where {$_.name -eq 'virtualmachine.admin.owner'} ).value.split('@')[0]

# Figure out the Zone of this dns server
$DNSZone = $ZoneTemplate.Replace('%VRMOwner%', $VRMOwner)

# =========================================================================================
# Code
# =========================================================================================
Write-Output '========================================'
Write-Output '== Installing Hyper-V =================='
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools

Write-Output '== Joining to domain ==================='
Write-Output '= Domain: ' + $DNSZone
$credential = New-Object System.Management.Automation.PSCredential($DomainUsername, $DomainPassword)
Add-Computer -DomainName $DNSZone -Credential

Write-Output '== Removing Ethernet1 Configuration ===='
Remove-NetIPAddress -InterfaceAlias "Ethernet1" -Confirm:$false