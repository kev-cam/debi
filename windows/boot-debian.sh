#!/bin/bash
# boot-debian.sh [--reboot] [--dry-run] -- Cygwin twin of boot-debian.ps1, for
# machines where PowerShell scripts are blocked.  Run it from an ELEVATED
# Cygwin terminal ("Run as administrator").
# Boots Debian once; the boot after that goes back to Windows.  Windows won't
# use grub's own 'debian' firmware entry ("A device which does not exist was
# specified"), so this makes "Debian (from Windows)", a copy of {bootmgr},
# which already points at the ESP, with path \EFI\debian\shimx64.efi, and
# sets it as the one-shot boot sequence.
# Every step is echoed and logged to /tmp/boot-debian.log.
set -u
NAME='Debian (from Windows)'
LOADER='\EFI\debian\shimx64.efi'
LOG=/tmp/boot-debian.log
REBOOT= DRY=
for a; do case $a in
    --reboot) REBOOT=1 ;; --dry-run) DRY=1 ;;
    *) sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 2 ;;
esac; done
exec > >(tee "$LOG") 2>&1
SYS=/cygdrive/c/Windows/System32
die() { echo "boot-debian: ERROR: $*"; exit 1; }
bcd() {   # bcd ARGS -- run bcdedit, echo the command and its output; status = bcdedit's
    echo "+ bcdedit $*"
    BCD_OUT=$("$SYS/bcdedit.exe" "$@" 2>&1 | tr -d '\r'); local rc=${PIPESTATUS[0]}
    printf '%s\n' "$BCD_OUT" | sed 's/^/    /'
    return "$rc"
}
echo "boot-debian $(date) user=$(whoami) groups=$(id -G)"
id -G | tr ' ' '\n' | grep -qx 544 || die "not elevated: run from a Cygwin terminal started with 'Run as administrator'"

# Debian's loader on the ESP?  (Only a warning: a missing loader just makes
# the firmware fall back to Windows.)
l=; for c in s t u v w x y z; do [ -d "/cygdrive/$c/" ] || { l=$c; break; }; done
if [ -n "$l" ] && "$SYS/mountvol.exe" "$l:" /S; then
    if [ -f "/cygdrive/$l/EFI/debian/shimx64.efi" ]; then echo "loader: $LOADER present on the ESP"
    else echo "WARNING: can't see $LOADER on the ESP ($(ls "/cygdrive/$l/EFI" 2>&1 | tr '\n' ' '))"; fi
    "$SYS/mountvol.exe" "$l:" /D
else echo "WARNING: couldn't mount the ESP to check the loader"; fi

bcd /enum firmware || die "bcdedit /enum firmware failed"
id=$(printf '%s\n' "$BCD_OUT" | awk -v n="$NAME" '
    /^identifier/ {cur=$2}
    /^description/ {sub(/^description[ \t]+/, ""); sub(/[ \t]+$/, ""); if ($0 == n && !id) id=cur}
    END {print id}')
echo "existing '$NAME' entry: ${id:-none}"
if [ -n "$DRY" ]; then
    if [ -n "$id" ]; then what="reuse $id"; else what="create it as a copy of {bootmgr}"; fi
    echo "dry run: would $what, set path $LOADER, and boot it once"
    exit 0
fi
if [ -z "$id" ]; then
    bcd /copy '{bootmgr}' /d "$NAME" || die "bcdedit /copy failed"
    id=$(grep -o '{[0-9a-fA-F-]*}' <<<"$BCD_OUT" | head -1)
    [ -n "$id" ] || die "bcdedit /copy printed no id"
fi
bcd /set "$id" path "$LOADER" || die "setting the path failed"
bcd /set '{fwbootmgr}' bootsequence "$id" || die "setting the boot sequence failed"
bcd /enum '{fwbootmgr}'
echo "next boot: '$NAME' $id"
if [ -n "$REBOOT" ]; then
    echo "+ shutdown /r /t 5"
    "$SYS/shutdown.exe" /r /t 5 || die "shutdown.exe failed ($?)"
    echo "rebooting in 5 s"
fi
