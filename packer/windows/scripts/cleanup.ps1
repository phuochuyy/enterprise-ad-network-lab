# Last provisioning step before sysprep: shrink the image.
# WinRM hardening is NOT done here (it would cut Packer's own session); clones do it on first
# boot via cloudbase-init/LocalScripts/winrm-https.ps1.
$ErrorActionPreference = 'Stop'

Remove-Item -Path "$env:TEMP\*", 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
Start-Process -FilePath dism.exe -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup /ResetBase' -Wait -NoNewWindow
powercfg.exe /hibernate off

# Hand freed blocks back to LVM-thin (disks are attached with discard=on).
Optimize-Volume -DriveLetter C -ReTrim -Verbose
Write-Output 'cleanup complete'
