# =========================================================================================
# Dynamic Variables
# =========================================================================================
$DomainUsername = "Administrator@$Domain"
$DomainPassword = "Student1!" | ConvertTo-SecureString -asPlainText -Force

# =========================================================================================
# Code
# =========================================================================================

Write-Output '== Joining to domain ==================='
Write-Output "= Domain: $Domain"
$credential = New-Object System.Management.Automation.PSCredential($DomainUsername, $DomainPassword)
Add-Computer -DomainName $Domain -Credential $credential -Force

Write-Output '== Configuring NIC for DNS ============='
(Get-WmiObject -Class Win32_NetworkAdapter -Filter "NetEnabled=True").GetRelated('Win32_NetworkAdapterConfiguration') | ForEach-Object {
    $_.SetDynamicDNSRegistration($true,$true)
}
