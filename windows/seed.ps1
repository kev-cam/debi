# seed.ps1 -- run on the Windows machine to prepare 'm2d win' (no elevation).
#
#   powershell -ExecutionPolicy Bypass -File seed.ps1 -Stick E: -Sibling G `
#       [-User claude] [-Uid 1000] [-AuthorizedKeys file1,file2] [-Desktop cinnamon|mate|xfce|none]
#       [-Tz America/Los_Angeles] [-Kbd us]
#
# Writes <Stick>\debi\hosts\<COMPUTERNAME>\seed.env (+ authorized_keys) on the
# live stick's FAT partition; the live session sees it under
# /run/live/medium/debi and m2d-win imports it.  Nothing secret goes on the
# stick: the Debian password is asked at the console during 'm2d win'.
#
# -Sibling names the NTFS drive that shares a disk with the space meant for
# Debian (the empty partition, or free space, is found next to it).  Every
# NTFS drive's volume serial is recorded so Debian mounts them as /mnt/<letter>,
# the same paths WSL uses.
param(
    [Parameter(Mandatory)] [string] $Stick,
    [Parameter(Mandatory)] [string] $Sibling,
    [string]   $User = 'claude',
    [int]      $Uid = 1000,
    [string[]] $AuthorizedKeys = @(),
    [ValidateSet('cinnamon', 'mate', 'xfce', 'none')] [string] $Desktop = 'cinnamon',
    [string]   $Tz = '',
    [string]   $Kbd = 'us'
)
$ErrorActionPreference = 'Stop'
$Stick = $Stick.TrimEnd('\', ':') + ':'
$Sibling = $Sibling.TrimEnd('\', ':').ToUpper()
if (-not (Test-Path "$Stick\live")) { throw "$Stick doesn't look like the live stick (no \live)" }

# Windows zone -> IANA.  Windows PowerShell 5.1 has no converter, so the common ones.
$tzmap = @{
    'Pacific Standard Time' = 'America/Los_Angeles'; 'Mountain Standard Time' = 'America/Denver'
    'US Mountain Standard Time' = 'America/Phoenix'; 'Central Standard Time' = 'America/Chicago'
    'Eastern Standard Time' = 'America/New_York';    'Alaskan Standard Time' = 'America/Anchorage'
    'Hawaiian Standard Time' = 'Pacific/Honolulu';   'GMT Standard Time' = 'Europe/London'
    'W. Europe Standard Time' = 'Europe/Berlin';     'Romance Standard Time' = 'Europe/Paris'
    'AUS Eastern Standard Time' = 'Australia/Sydney'; 'UTC' = 'Etc/UTC'
}
if (-not $Tz) {
    $Tz = $tzmap[(Get-TimeZone).Id]
    if (-not $Tz) { throw "no IANA name known for '$((Get-TimeZone).Id)'; pass -Tz" }
}
$lang = ((Get-WinUserLanguageList)[0].LanguageTag -replace '-', '_') + '.UTF-8'

# NTFS volume serials: 'vol' prints the low 32 bits, which blkid shows as the
# last 8 hex digits of the NTFS UUID.
$ntfs = @()
foreach ($d in [IO.DriveInfo]::GetDrives()) {
    if ($d.DriveType -ne 'Fixed' -or $d.DriveFormat -ne 'NTFS') { continue }
    $l = $d.Name.Substring(0, 1)
    $s = (cmd /c "vol ${l}:" | Select-String 'Serial') -replace '.*is\s+', '' -replace '-', ''
    if ($s) { $ntfs += "${l}:$($s.Trim().ToUpper())" }
}
if (-not ($ntfs -match "^${Sibling}:")) { throw "$Sibling`: is not a fixed NTFS drive" }

$hostName = $env:COMPUTERNAME
$dir = Join-Path $Stick "debi\hosts\$hostName"
New-Item -ItemType Directory -Force $dir | Out-Null
$seed = @(
    "# made by seed.ps1 on $hostName $(Get-Date -Format s)"
    "SEED_HOST=$hostName"
    "SEED_USER=$User"
    "SEED_UID=$Uid"
    "SEED_GECOS=$User"
    "SEED_TZ=$Tz"
    "SEED_LANG=$lang"
    "SEED_KBD=$Kbd"
    "SEED_DESKTOP=$Desktop"
    "SEED_TARGET_SIBLING=$Sibling"
    "SEED_NTFS=`"$($ntfs -join ' ')`""
) -join "`n"
# LF endings: bash sources this file
[IO.File]::WriteAllText((Join-Path $dir 'seed.env'), $seed + "`n")

# 'powershell -File' passes "a,b" as one string, not an array
$keys = foreach ($k in ($AuthorizedKeys -split ',' | Where-Object { $_ })) { Get-Content $k | Where-Object { $_ -match '^(ssh|ecdsa|sk-)' } }
if ($keys) {
    $keys = $keys | Select-Object -Unique
    [IO.File]::WriteAllText((Join-Path $dir 'authorized_keys'), ($keys -join "`n") + "`n")
}
Write-Output "seed written to $dir"
Write-Output $seed
Write-Output "authorized_keys: $(@($keys).Count) key(s)"
