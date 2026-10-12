# boot-debian.ps1 [-Reboot] [-DryRun] -- from Windows, boot Debian once (elevated).
# Sets the firmware's one-shot BootNext to the 'debian' entry that m2d-win
# made; the boot after that goes back to the normal order (Windows first).
# Needs no USB stick.  -DryRun only shows the entry it would use.
# In Debian, 'win-bootctl next|default windows|debian' does the same.
param([switch] $Reboot, [switch] $DryRun)
$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "run this from an elevated PowerShell (bcdedit needs it)" }
$cur = $null; $deb = $null
foreach ($line in (bcdedit /enum firmware)) {
    if ($line -match '^identifier\s+(\{[^}]+\})') { $cur = $Matches[1] }
    elseif ($line -match '^description\s+debian\s*$' -and $cur) { $deb = $cur; break }
}
if (-not $deb) { throw "no 'debian' firmware entry (was m2d win run?)" }
if ($DryRun) { Write-Output "would boot once: debian $deb"; return }
$out = bcdedit /set '{fwbootmgr}' bootsequence $deb 2>&1
if ($LASTEXITCODE) { throw "bcdedit /set {fwbootmgr} bootsequence $deb failed ($LASTEXITCODE): $out" }
Write-Output "next boot: debian $deb"
if ($Reboot) { shutdown /r /t 5 /c "Rebooting into Debian" }
