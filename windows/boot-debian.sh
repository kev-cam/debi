#!/bin/bash
# boot-debian.sh [--reboot] [--dry-run] -- Cygwin twin of boot-debian.ps1, for
# machines where PowerShell scripts are blocked.  Run it from an ELEVATED
# Cygwin terminal ("Run as administrator").
# Boots Debian once; the boot after that goes back to Windows.  Windows won't
# use grub's own 'debian' firmware entry ("A device which does not exist was
# specified"), so this makes "Debian (from Windows)", a copy of {bootmgr},
# which already points at the ESP, with path \EFI\debian\shimx64.efi, and
# sets it as the one-shot boot sequence.
set -euo pipefail
NAME='Debian (from Windows)'
LOADER='\EFI\debian\shimx64.efi'
REBOOT= DRY=
for a; do case $a in
    --reboot) REBOOT=1 ;; --dry-run) DRY=1 ;;
    *) sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2 ;;
esac; done
SYS=/cygdrive/c/Windows/System32
bcd() { "$SYS/bcdedit.exe" "$@" 2>&1 | tr -d '\r'; return "${PIPESTATUS[0]}"; }
id -G | tr ' ' '\n' | grep -qx 544 || { echo "boot-debian: run from an elevated Cygwin terminal (Run as administrator)" >&2; exit 1; }

# Debian's loader on the ESP?  Look via a free drive letter.  Only a warning
# if it can't be seen: a missing loader just makes the firmware fall back to
# Windows.
for l in s t u v w x y z; do [ -d "/cygdrive/$l/" ] || break; done
if "$SYS/mountvol.exe" "$l:" /S >/dev/null 2>&1; then
    if [ -f "/cygdrive/$l/EFI/debian/shimx64.efi" ]; then echo "loader: $LOADER present on the ESP"
    else echo "boot-debian: WARNING: can't see $LOADER on the ESP (was m2d win run?)" >&2; fi
    "$SYS/mountvol.exe" "$l:" /D >/dev/null 2>&1 || true
fi

id=$(bcd /enum firmware | awk -v n="$NAME" '
    /^identifier/ {cur=$2}
    /^description/ {sub(/^description[ \t]+/, ""); sub(/[ \t]+$/, ""); if ($0 == n) {print cur; exit}}')
if [ -n "$DRY" ]; then
    if [ -n "$id" ]; then echo "would boot once: '$NAME' $id"
    else echo "would create '$NAME' (copy of {bootmgr}, path $LOADER) and boot it once"; fi
    exit 0
fi
if [ -z "$id" ]; then
    out=$(bcd /copy '{bootmgr}' /d "$NAME") || { echo "bcdedit /copy failed: $out" >&2; exit 1; }
    id=$(grep -o '{[0-9a-fA-F-]*}' <<<"$out" | head -1)
    [ -n "$id" ] || { echo "bcdedit /copy gave no id: $out" >&2; exit 1; }
fi
out=$(bcd /set "$id" path "$LOADER") || { echo "bcdedit /set path failed: $out" >&2; exit 1; }
out=$(bcd /set '{fwbootmgr}' bootsequence "$id") || { echo "bcdedit bootsequence failed: $out" >&2; exit 1; }
echo "next boot: '$NAME' $id"
[ -n "$REBOOT" ] && "$SYS/shutdown.exe" /r /t 5 /c "Rebooting into Debian"
exit 0
