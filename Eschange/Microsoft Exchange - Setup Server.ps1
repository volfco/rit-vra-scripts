$SourcePath = "\\itsnas01.main.ad.rit.edu\vRAscripts$\Blueprints\Exchange"

# Mount Fileshare
Write-Output '== Setting up Fileshare ================'
net use $SourcePath /user:vrauser Student1!

# Build Credential Object to allow us to run the below program as the Domain Admin
$Domain = ( Get-ADDomain ).Name
$credential = New-Object System.Management.Automation.PSCredential "$DomainUsername@main", (ConvertTo-SecureString $DomainPassword -AsPlainText -Force)

# Invoke Exchange Installer
Write-Output '== Installing Mailbox Role ============='
Start-Process -Credential $credential -NoNewWindow "$SourcePath\Exchange2013\setup.exe" -ArgumentList "/Mode:Install /role:Mailbox /OrganizationName:$OrganizationName /IAcceptExchangeServerLicenseTerms"

Write-Output '== Installing ClientAccess Role ========'
Start-Process -Credential $credential -NoNewWindow "$SourcePath\Exchange2013\setup.exe" -ArgumentList "/Mode:Install /role:ClientAccess /IAcceptExchangeServerLicenseTerms"