#!/bin/bash
# boot-debian.sh [--reboot] [--dry-run] [--copy | --usb [X:]]
# Cygwin twin of boot-debian.ps1, for machines where PowerShell scripts are
# blocked.  Run it from an ELEVATED Cygwin terminal ("Run as administrator").
# Boots Debian once; the boot after that goes back to Windows.
#   (default)  one-shot boot of the 'debian' firmware entry grub-install made
#   --copy     use "Debian (from Windows)" instead: a copy of {bootmgr} with
#              path \EFI\debian\shimx64.efi (on P620A it fell straight
#              through to Windows)
#   --usb [X:] boot the debi live stick (default E:) via "debi USB", re-pointed
#              at the stick every time (twin of reboot-to-usb.ps1)
# bcdedit appends "A device which does not exist was specified." to every
# command while an entry's device is missing (e.g. "debi USB" with the stick
# out) and may exit 1, so success is judged by reading the boot sequence back.
# Every step is echoed and logged to /tmp/boot-debian.log.
set -u
LOG=/tmp/boot-debian.log
REBOOT= DRY= HOW=grub USB=
while [ $# -gt 0 ]; do case $1 in
    --reboot) REBOOT=1 ;; --dry-run) DRY=1 ;; --copy) HOW=copy ;;
    --usb) HOW=usb; USB=E:; case ${2:-} in [A-Za-z]:) USB=${2^^}; shift ;; esac ;;
    *) sed -n '2,16s/^# \{0,1\}//p' "$0"; exit 2 ;;
esac; shift; done
case $HOW in
    grub) NAME='debian' ;;
    copy) NAME='Debian (from Windows)'; LOADER='\EFI\debian\shimx64.efi' ;;
    usb)  NAME='debi USB'; LOADER='\EFI\boot\bootx64.efi' ;;
esac
exec > >(tee "$LOG") 2>&1
SYS=/cygdrive/c/Windows/System32
die() { echo "boot-debian: ERROR: $*"; exit 1; }
bcd() {   # bcd ARGS -- run bcdedit, echo the command and its output into BCD_OUT
    echo "+ bcdedit $*"
    BCD_OUT=$("$SYS/bcdedit.exe" "$@" 2>&1 | tr -d '\r')
    printf '%s\n' "$BCD_OUT" | sed 's/^/    /'
}
echo "boot-debian $(date) user=$(whoami) groups=$(id -G) how=$HOW"
id -G | tr ' ' '\n' | grep -qx 544 || die "not elevated: run from a Cygwin terminal started with 'Run as administrator'"

if [ "$HOW" = usb ]; then
    d=/cygdrive/${USB%:}; d=${d,,}
    [ -f "$d/EFI/boot/bootx64.efi" ] || die "no $USB\\EFI\\boot\\bootx64.efi: is the debi stick plugged in at $USB?"
    echo "stick: $USB, auto mode $(cat "$d/debi/auto/mode" 2>/dev/null || echo none)"
fi

bcd /enum firmware
id=$(printf '%s\n' "$BCD_OUT" | awk -v n="$NAME" '
    /^identifier/ {cur=$2}
    /^description/ {sub(/^description[ \t]+/, ""); sub(/[ \t]+$/, ""); if ($0 == n && !id) id=cur}
    END {print id}')
echo "'$NAME' entry: ${id:-none}"
[ -n "$id" ] || [ "$HOW" != grub ] || die "no 'debian' firmware entry (was m2d win run?); try --copy"
if [ -n "$DRY" ]; then echo "dry run: would boot '$NAME' ${id:-(to be created)} once"; exit 0; fi

if [ "$HOW" != grub ]; then
    if [ -z "$id" ]; then
        bcd /copy '{bootmgr}' /d "$NAME"
        id=$(grep -o '{[0-9a-fA-F-]*}' <<<"$BCD_OUT" | head -1)
        [ -n "$id" ] || die "bcdedit /copy printed no id"
    fi
    [ "$HOW" = usb ] && bcd /set "$id" device "partition=$USB"
    bcd /set "$id" path "$LOADER"
fi
bcd /set '{fwbootmgr}' bootsequence "$id"
bcd /enum '{fwbootmgr}'
awk -v id="$id" '$1=="bootsequence" && $2==id {ok=1} END {exit !ok}' <<<"$BCD_OUT" \
    || die "the boot sequence does not read back as $id"
echo "next boot: '$NAME' $id (verified)"
if [ -n "$REBOOT" ]; then
    echo "+ shutdown /r /t 5"
    "$SYS/shutdown.exe" /r /t 5 || die "shutdown.exe failed ($?)"
    echo "rebooting in 5 s"
fi
