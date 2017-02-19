Write-Output '== Setup =============================='
Write-Output ' Hello...'

Import-Module VMware.VimAutomation.Core

Write-Output " It's Me..."

# Connect to the vCenter server we just made
Write-Output '== Connecting to vCenter =============='
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope AllUsers -Confirm:$false
Connect-VIServer -Server $VCSAIP -Protocol https -User Administrator@vSphere.local -Password Student1!

$Zones = Get-DnsServerZone | where { $_.IsReverseLookupZone -eq $false }
foreach ($Zone in $Zones) {

    # Get all DNS A Records
    $Records = $Zone | Get-DnsServerResourceRecord | where {$_.RecordType -eq 'A'}
    foreach ($Record in $Records) {
        Write-Output '  [QUERY    ] Looking for ' + $Record.Hostname

        Get-VM -Name $Record.HostName -ErrorAction Ignore
        if ($? -eq $false) {
            # VM was not found, remove record
            Write-Output '  [NOTFOUND ] VM Not Found, removing record...'
            # Remove NS Record
            $Zone | Get-DnsServerResourceRecord | where {$_.RecordType -eq 'NS' -and $_.RecordData.NameServer -eq $Record.HostName + "." + $Zone.ZoneName + "."} | Remove-DnsServerResourceRecord -ZoneName $Zone
            # Remove A Record
            $Record | Remove-DnsServerResourceRecord -ZoneName $Zone 
        } else {
            Write-Output '  [FOUND    ] VM Found. Not doing anything'
        }
    }


}




