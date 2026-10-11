# boot-debian.ps1 [-Reboot] -- from Windows, boot Debian once (elevated).
# Sets the firmware's one-shot BootNext to the 'debian' entry that m2d-win
# made; the boot after that goes back to the normal order (Windows first).
# In Debian, 'win-bootctl next|default windows|debian' does the same.
param([switch] $Reboot)
$ErrorActionPreference = 'Stop'
$cur = $null; $deb = $null
foreach ($line in (bcdedit /enum firmware)) {
    if ($line -match '^identifier\s+(\{[^}]+\})') { $cur = $Matches[1] }
    elseif ($line -match '^description\s+debian\s*$' -and $cur) { $deb = $cur; break }
}
if (-not $deb) { throw "no 'debian' firmware entry (needs an elevated shell; was m2d win run?)" }
bcdedit /set '{fwbootmgr}' bootsequence $deb | Out-Null
if ($LASTEXITCODE) { throw "bcdedit failed ($LASTEXITCODE)" }
Write-Output "next boot: debian $deb"
if ($Reboot) { shutdown /r /t 5 /c "Rebooting into Debian" }
