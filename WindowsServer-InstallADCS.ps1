<#
    Windows Server - Deploy Subordinate CA

    This works in either an existing domain, or a standlone CA.
	
	$CertificateValidPeriod		Length of the CA Validaty Period
	$CAType						Certificate Authority Type. root or subordinate

	Special Thanks to: http://security-24-7.com/windows-2012-r2-certification-authority-installation-guide/

#>
Write-Output '== Installing ADCS ====================='
Install-WindowsFeature AD-Certificate, ADCS-Online-Cert -IncludeManagementTools

Write-Output '== Setting up Fileshare ================'
net use \\itsnas01.main.ad.rit.edu\vRAscripts$\Components\certsrv\dist /user:vrauser Student1!

Write-Output '== Copying certsrv ====================='
Copy-Item \\itsnas01.main.ad.rit.edu\vRAscripts$\Components\certsrv\dist\certsrv.exe C:\certsrv.exe

if ($CAType -eq "subordinate") {
	if((gwmi win32_computersystem).partofdomain -eq $true) {
		$CAType = "EnterpriseSubordinateCa"
	} else {
		$CAType = "StandaloneSubordinateCA"
	}
} else {
	if((gwmi win32_computersystem).partofdomain -eq $true) {
		$CAType = "EnterpriseRootCA"
	else {
		$CAType = "StandaloneRootCA"
	}
}
Write-Output "== CA Type: $CAType "
Write-Output '== Configuring ADCS ===================='
Install-AdcsCertificationAuthority -CAType EnterpriseSubordinateCa -KeyLength 256 -HashAlgorithmName SHA256

Write-Output '== Signing CA Certificate =============='
$req = "C:\" + ( Get-ChildItem -File -Path C:\ | where { $_.Name -like '*req*'} ).Name
& C:\certsrv.exe --hostname=dcano1.ca.local --csr=$req --crt='C:\\ca-certificate.crt' --no-ssl --verbose

Write-Output '== Importing Certificate ==============='
certutil.exe -installCert "C:\ca-certificate.crt"

Write-Output '== Cleaning up Crap ===================='
$crllist = Get-CACrlDistributionPoint
foreach ($crl in $crllist) {
	Remove-CACrlDistributionPoint $crl.uri -Force
}
$aialist = Get-CAAuthorityInformationAccess
foreach ($aia in $aialist) {
	Remove-CAAuthorityInformationAccess $aia.uri -Force
}

Write-Output '== Restarting Service =================='
Restart-Service certsvc