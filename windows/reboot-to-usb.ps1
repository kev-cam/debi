# reboot-to-usb.ps1 [-Stick E:] [-NoReboot]   (elevated)
# Boot the live stick once, without a keyboard: a firmware entry "debi USB"
# pointing at <Stick>\EFI\boot\bootx64.efi (shim, so Secure Boot is fine) is
# made from a copy of {bootmgr} if it isn't there yet, and set as the
# one-shot boot sequence.  The boot after that follows the normal order.
param([string] $Stick = 'E:', [switch] $NoReboot)
$ErrorActionPreference = 'Stop'
$Stick = $Stick.TrimEnd('\', ':') + ':'
if (-not (Test-Path "$Stick\EFI\boot\bootx64.efi")) { throw "$Stick\EFI\boot\bootx64.efi not found" }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "run this from an elevated PowerShell" }

$id = $null; $cur = $null
foreach ($line in (bcdedit /enum firmware)) {
    if ($line -match '^identifier\s+(\{[^}]+\})') { $cur = $Matches[1] }
    elseif ($line -match '^description\s+debi USB\s*$' -and $cur) { $id = $cur; break }
}
if (-not $id) {
    $out = bcdedit /copy '{bootmgr}' /d 'debi USB'
    if ($out -notmatch '(\{[0-9a-fA-F-]+\})') { throw "bcdedit /copy failed: $out" }
    $id = $Matches[1]
}
# (re)point it at the stick every time: drive letters move
bcdedit /set $id device "partition=$Stick" | Out-Null
bcdedit /set $id path '\EFI\boot\bootx64.efi' | Out-Null
bcdedit /set '{fwbootmgr}' bootsequence $id | Out-Null
if ($LASTEXITCODE) { throw "bcdedit bootsequence failed ($LASTEXITCODE)" }
Write-Output "next boot: debi USB $id ($Stick)"
if (-not $NoReboot) { shutdown /r /t 10 /c "Rebooting into the debi live stick" }
