# Install cloudbase-init so clones pick up hostname and static IP from the Proxmox
# cloud-init drive (configdrive2). URL and SHA-256 come from Packer environment_vars.
$ErrorActionPreference = 'Stop'
$Url = $env:CBI_URL
$Sha256 = $env:CBI_SHA256
if (-not $Url -or -not $Sha256) { throw 'CBI_URL and CBI_SHA256 must be set' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$msi = Join-Path $env:TEMP 'CloudbaseInitSetup.msi'
Invoke-WebRequest -Uri $Url -OutFile $msi -UseBasicParsing

$actual = (Get-FileHash -Path $msi -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $Sha256.ToLowerInvariant()) {
    throw "cloudbase-init checksum mismatch: expected $Sha256, got $actual"
}

# Run as LocalSystem; our own config files are uploaded by Packer afterwards.
$msiArgs = "/i `"$msi`" /qn /norestart /l*v C:\Windows\Temp\cloudbase-init-install.log RUN_SERVICE_AS_LOCAL_SYSTEM=1"
$p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "cloudbase-init install failed with exit code $($p.ExitCode)" }

# Keep it from running during the build; sysprep.ps1 sets it back to Automatic right before generalizing.
Set-Service -Name cloudbase-init -StartupType Manual
Remove-Item $msi -Force
Write-Output 'cloudbase-init installed'
