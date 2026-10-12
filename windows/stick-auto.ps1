# stick-auto.ps1 -Stick E: -Mode plan|yes|diag|debian|off   (no elevation)
# Make the live stick run 'm2d win' unattended on its next boot (headless
# machines).  Copies this toolkit to <Stick>\debi\toolkit, adds a first boot
# entry "debi auto" to the stick's GRUB menu with a 5 s timeout, passing the
# m2d-auto live-config hook, and writes the mode to <Stick>\debi\auto\mode:
#   plan  survey only; the plan lands in debi\auto\out\plan-*.log
#   yes   partition/format/install/users/boot, log in debi\auto\out\yes-*.log
#   diag  record firmware entries, ESP, Secure Boot and Debian's boot history
#   debian  diag, then boot Debian's own firmware entry (BootNext set from Linux)
#   off   restore the stick's own boot menu
# Either way the live session then reboots into Windows.  Needs a seed
# (seed.ps1).  windows\reboot-to-usb.ps1 (elevated) boots the stick once.
param(
    [Parameter(Mandatory)] [string] $Stick,
    [Parameter(Mandatory)] [ValidateSet('plan', 'yes', 'diag', 'debian', 'off')] [string] $Mode
)
$ErrorActionPreference = 'Stop'
$Stick = $Stick.TrimEnd('\', ':') + ':'
$grub = "$Stick\boot\grub"
if (-not (Test-Path "$grub\grub.cfg")) { throw "$Stick has no boot\grub\grub.cfg" }
function Write-Lf([string] $path, [string] $text) {
    [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"))
}
foreach ($f in 'grub.cfg', 'config.cfg') {
    if (-not (Test-Path "$grub\$f.debi-orig")) { Copy-Item "$grub\$f" "$grub\$f.debi-orig" }
}
New-Item -ItemType Directory -Force "$Stick\debi\auto" | Out-Null
Write-Lf "$Stick\debi\auto\mode" "$Mode`n"

if ($Mode -eq 'off') {
    foreach ($f in 'grub.cfg', 'config.cfg') { Copy-Item -Force "$grub\$f.debi-orig" "$grub\$f" }
    Write-Output "stick boot menu restored; auto mode off"
    return
}
if (-not (Get-ChildItem "$Stick\debi\hosts\*\seed.env" -ErrorAction SilentlyContinue)) {
    throw "no seed on $Stick (run seed.ps1 first)"
}

# toolkit: everything in the repo except git and per-host records
$repo = Split-Path -Parent $PSScriptRoot
$dst = "$Stick\debi\toolkit"
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force $dst | Out-Null
Get-ChildItem $repo -Force | Where-Object { $_.Name -notin '.git', 'hosts' } |
    ForEach-Object { Copy-Item -Recurse -Force $_.FullName $dst }

# boot entry: the stick's own first live entry plus the hook
$orig = Get-Content -Raw "$grub\grub.cfg.debi-orig"
$m = [regex]::Match($orig, '(?m)^\s*linux\s+(\S+)\s+([^\r\n]*)\r?\n\s*initrd\s+(\S+)')
if (-not $m.Success) { throw "can't find the live kernel in grub.cfg" }
$kopts = $m.Groups[2].Value -replace '\s*findiso=\S+', '' -replace '\bquiet\b|\bsplash\b', ''
$entry = @"
menuentry "debi auto: m2d win ($Mode), then back to Windows" {
	linux	$($m.Groups[1].Value) $($kopts.Trim()) hooks=file:///run/live/medium/debi/toolkit/m2d-auto-hook
	initrd	$($m.Groups[3].Value)
}

"@
$first = $orig.IndexOf('menuentry')
Write-Lf "$grub\grub.cfg" ($orig.Substring(0, $first) + $entry + $orig.Substring($first))
$cfg = Get-Content -Raw "$grub\config.cfg.debi-orig"
Write-Lf "$grub\config.cfg" ($cfg.TrimEnd() + "`nset timeout=5`n")
Write-Output "stick set for '$Mode': first boot entry runs m2d win, 5 s timeout"
Write-Output "toolkit copied from $repo"
