<#

    Enable WinRM



    $Hostname
#>

$Cert = New-SelfSignedCertificate -DnsName ns.dot.lab -CertStoreLocation Cert:\LocalMachine\My

# Works under CMD
winrm create winrm/config/Listener?Address=*+Transport=HTTPS '@{Hostname=”' + $Hostname + '”; CertificateThumbprint=”' + $Cert.Thumbprint + '”}'
netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=5986
