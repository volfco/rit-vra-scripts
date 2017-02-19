<#

#>
Write-Output '== Setting up Fileshare ================'
net use \\itsnas01.main.ad.rit.edu\vRAscripts$\Components\ /user:vrauser Student1!

Write-Output '== Copying certsrv ====================='
& \\itsnas01.main.ad.rit.edu\vRAscripts$\Components\certsrv\certsrv_dist.exe -o"C:\certsrv"

$CAType = "StandaloneSubordinateCa"

Install-AdcsCertificationAuthority -CAType $CAType -CryptoProviderName "ECDSA_P256#Microsoft Software Key Storage Provider" -KeyLength 256 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 1 -Confirm:$false 

#-CACommonName
#-CADistinguishedNameSuffix

# Invoke certsrv.exe to download certificate
## Get the .req
$req = "C:\" + ( Get-ChildItem -File -Path C:\ | where { $_.Name -like '*req*'} ).Name
## Invoke 
& C:\certsrv\certsrv.exe --hostname=dcano1.ca.local --csr=$req --crt='C:\\tmp.crt'