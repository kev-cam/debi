# boot-debian.ps1 [-Reboot] [-DryRun] -- from Windows, boot Debian once (elevated).
# One-shot boot of the 'debian' firmware entry that grub-install made; the
# boot after that goes back to the normal order (Windows first).  Needs no
# USB stick.  In Debian, 'win-bootctl next|default windows|debian' does the
# same.  windows\boot-debian.sh is the Cygwin twin (for blocked PowerShell).
# bcdedit appends "A device which does not exist was specified." to every
# command while some entry's device is missing (e.g. "debi USB" with the stick
# out) and can exit 1 although it worked, so success is judged by reading the
# boot sequence back.
param([switch] $Reboot, [switch] $DryRun)
$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "run this from an elevated PowerShell (bcdedit needs it)" }
$cur = $null; $deb = $null
foreach ($line in (bcdedit /enum firmware 2>&1)) {
    if ("$line" -match '^identifier\s+(\{[^}]+\})') { $cur = $Matches[1] }
    elseif ("$line" -match '^description\s+debian\s*$' -and $cur) { $deb = $cur; break }
}
if (-not $deb) { throw "no 'debian' firmware entry (was m2d win run?)" }
if ($DryRun) { Write-Output "would boot once: debian $deb"; return }
bcdedit /set '{fwbootmgr}' bootsequence $deb 2>&1 | Out-Null
$seq = (bcdedit /enum '{fwbootmgr}' 2>&1) | Where-Object { "$_" -match '^bootsequence\s+(\{[^}]+\})' } |
    ForEach-Object { $Matches[1] } | Select-Object -First 1
if ($seq -ne $deb) { throw "boot sequence reads back as '$seq', not $deb" }
Write-Output "next boot: debian $deb (verified)"
if ($Reboot) { shutdown /r /t 5 /c "Rebooting into Debian" }
