# boot-debian.ps1 [-Reboot] [-DryRun] -- from Windows, boot Debian once (elevated).
# Needs no USB stick.  The boot after that goes back to the normal order
# (Windows first).  In Debian, 'win-bootctl next|default windows|debian' does
# the same.
#
# Windows refuses to use the 'debian' entry that grub-install/efibootmgr made
# ("A device which does not exist was specified"): it can't resolve that
# entry's device path.  So this script makes its own firmware entry, "Debian
# (from Windows)", as a copy of {bootmgr}.  That copy already points at the
# ESP, where shim lives as \EFI\debian\shimx64.efi.  It then sets that entry
# as the one-shot boot sequence, the same way reboot-to-usb.ps1 boots the
# stick.  -DryRun shows what it would do and changes nothing.
param([switch] $Reboot, [switch] $DryRun)
$ErrorActionPreference = 'Stop'
$Name = 'Debian (from Windows)'
$Loader = '\EFI\debian\shimx64.efi'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "run this from an elevated PowerShell (bcdedit needs it)" }

# Is Debian's loader on the ESP?  Mount the ESP on a free letter to look.
$letter = [char[]](83..90) | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
mountvol "${letter}:" /S
try {
    if (-not (Test-Path "${letter}:$Loader")) { throw "$Loader not found on the ESP (was m2d win run?)" }
} finally { mountvol "${letter}:" /D }

$cur = $null; $id = $null
foreach ($line in (bcdedit /enum firmware)) {
    if ($line -match '^identifier\s+(\{[^}]+\})') { $cur = $Matches[1] }
    elseif ($line -match "^description\s+$([regex]::Escape($Name))\s*$" -and $cur) { $id = $cur; break }
}
if ($DryRun) {
    if ($id) { Write-Output "would boot once: '$Name' $id ($Loader)" }
    else { Write-Output "would create '$Name' (copy of {bootmgr}, path $Loader) and boot it once" }
    return
}
if (-not $id) {
    $out = bcdedit /copy '{bootmgr}' /d $Name 2>&1
    if ($out -notmatch '(\{[0-9a-fA-F-]+\})') { throw "bcdedit /copy failed: $out" }
    $id = $Matches[1]
}
$out = bcdedit /set $id path $Loader 2>&1
if ($LASTEXITCODE) { throw "bcdedit /set $id path failed: $out" }
$out = bcdedit /set '{fwbootmgr}' bootsequence $id 2>&1
if ($LASTEXITCODE) { throw "bcdedit /set {fwbootmgr} bootsequence $id failed ($LASTEXITCODE): $out" }
Write-Output "next boot: '$Name' $id"
if ($Reboot) { shutdown /r /t 5 /c "Rebooting into Debian" }
