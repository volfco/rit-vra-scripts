# =========================================================================================
# Dynamic Variables
# =========================================================================================
$DomainUser = "$DomainUsername@$Domain"
$DomainPass =  $DomainPassword | ConvertTo-SecureString -asPlainText -Force

# =========================================================================================
# Code
# =========================================================================================

Write-Output '== Joining to domain ==================='
Write-Output '= Domain: ' + $Domain
$credential = New-Object System.Management.Automation.PSCredential($DomainUser, $DomainPass)
Add-Computer -DomainName $Domain -Credential $credential -Force
