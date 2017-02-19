# =========================================================================================
# Dynamic Variables
# =========================================================================================
$DomainUser = "$DomainUsername@$Domain"
$DomainPass =  $DomainPassword | ConvertTo-SecureString -asPlainText -Force

# =========================================================================================
# Code
# =========================================================================================

Write-Output '== Leaving domain ======================'
Write-Output '= Domain: ' + $Domain
$credential = New-Object System.Management.Automation.PSCredential($DomainUser, $DomainPass)
Remove-Computer -Credential $credential -Force
