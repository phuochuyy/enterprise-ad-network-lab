# Runs on every CLONE during the sysprep specialize pass (answer/unattend-sysprep.xml.pkrtpl).
# Drops the template's temporary build IP, DNS and persistent default route so the clone starts
# clean; cloudbase-init then applies the Terraform-defined address (or DHCP).
#
# Kept as a file because unattend RunSynchronousCommand/Path is limited to 259 characters - the
# inline one-liner (467 chars) made specialize reject the whole answer file on the first clone.
# Never throws: a failure here must not block Setup. The transcript lands next to the Setup logs.
Start-Transcript -Path "$env:SystemRoot\Panther\reset-build-network.log" -Append | Out-Null

foreach ($nic in Get-NetAdapter) {
    $i = $nic.ifIndex
    Write-Output "resetting $($nic.Name) (ifIndex $i)"
    Remove-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $i -DestinationPrefix 0.0.0.0/0 -Confirm:$false -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $i -Dhcp Enabled -ErrorAction SilentlyContinue
    Set-DnsClientServerAddress -InterfaceIndex $i -ResetServerAddresses -ErrorAction SilentlyContinue
}

Stop-Transcript | Out-Null
exit 0
