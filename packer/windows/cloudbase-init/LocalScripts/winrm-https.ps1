# cloudbase-init LocalScript - runs on the first boot of every clone (once per instance).
# Rebinds WinRM HTTPS to a fresh self-signed certificate for the clone's hostname and removes
# every build-time convenience: HTTP listener rule, Basic auth, unencrypted traffic.
# Ansible then connects with NTLM over HTTPS 5986.
$ErrorActionPreference = 'Stop'
Start-Transcript -Path 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\winrm-https.log' -Append

# Client SKUs (Windows 11) start WinRM delayed, so it is usually still stopped here. Touching
# WSMan:\ then asks "Start WinRM Service?", which fails in this non-interactive session.
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
(Get-Service -Name WinRM).WaitForStatus('Running', [TimeSpan]::FromMinutes(2))

# Client SKUs refuse WSMan service changes while any connection is Public ("WinRM firewall
# exception will not work..."), and the unattend NetworkLocation is ignored since Windows 10.
# Private suits the lab LANs; domain join later makes the profile DomainAuthenticated. Retry
# while the network is still "Identifying...".
for ($i = 0; $i -lt 24; $i++) {
    $public = Get-NetConnectionProfile | Where-Object NetworkCategory -eq 'Public'
    if (-not $public) { break }
    try { $public | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop } catch { Start-Sleep -Seconds 5 }
}

$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My `
    -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(5)

Get-ChildItem WSMan:\localhost\Listener |
    Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
    Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
    -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

if (-not (Get-NetFirewallRule -Name 'WinRM-HTTPS' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'WinRM-HTTPS' -DisplayName 'Windows Remote Management (HTTPS-In)' `
        -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any | Out-Null
}

# Hardening: HTTPS only, no Basic, no plaintext.
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $false
Remove-NetFirewallRule -Name 'WinRM-HTTP-Build' -ErrorAction SilentlyContinue
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule

Write-Output "WinRM HTTPS bound to $($cert.Thumbprint) for $env:COMPUTERNAME"
Stop-Transcript
