<#
    Windows Server - Deploy Subordinate CA

    This works in either an existing domain, or a standlone CA.
#>

Install-WindowsFeature AD-Certificate, ADCS-Online-Cert -IncludeManagementTools

# Server needs to be rebooted