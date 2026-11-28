# Generalize the image. Uses /quit (not /shutdown) and waits for the reseal state, so the
# WinRM session ends cleanly and Packer itself powers the VM off and converts it to a template.
$ErrorActionPreference = 'Stop'

$unattend = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml'
if (-not (Test-Path $unattend)) { throw "missing $unattend" }

Set-Service -Name cloudbase-init -StartupType Automatic

# NOTE: the temporary build IP is NOT reset here - doing so cut Packer's own WinRM session
# before sysprep could run (build #2). Clones reset it in the specialize pass instead
# (answer/unattend-sysprep.xml.pkrtpl).

& "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /quit /quiet /mode:vm "/unattend:$unattend"

$stateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'
$deadline = (Get-Date).AddMinutes(20)
while ((Get-ItemProperty $stateKey).ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
    if ((Get-Date) -gt $deadline) {
        Get-Content "$env:SystemRoot\System32\Sysprep\Panther\setupact.log" -Tail 40
        throw 'sysprep did not reach IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE within 20 minutes'
    }
    Start-Sleep -Seconds 10
}
Write-Output 'sysprep complete - image generalized'
