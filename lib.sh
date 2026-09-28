# mint2deb shared helpers -- sourced by every m2d-* script.
# Runs as root inside the Debian live session (except m2d-prep-usb).

set -euo pipefail

M2D_HOME=${M2D_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
M2D_SUITE=${M2D_SUITE:-trixie}
M2D_MIRROR=${M2D_MIRROR:-http://deb.debian.org/debian}
M2D_LABEL=${M2D_LABEL:-deb13root}
MINT=/mnt/m2d-mint          # Mint root, mounted by mount_mint
TARGET=/mnt/m2d-target      # new Debian root, mounted by mount_target

die()  { echo "m2d: ERROR: $*" >&2; exit 1; }
warn() { echo "m2d: WARNING: $*" >&2; }
log()  { echo "== $*" >&2; }

[ "$(id -u)" = 0 ] || die "must run as root"

# nvme0n1 -> nvme0n1p3, sda -> sda3
part_dev() { case $1 in *[0-9]) echo "${1}p$2" ;; *) echo "$1$2" ;; esac; }

# ---- per-host state ------------------------------------------------------
# hosts/<minthostname>/state.env holds KEY=VALUE lines; hosts/current -> it.
HOSTDIR=
load_state() {
    local h=${M2D_HOST:-}
    if [ -n "$h" ]; then HOSTDIR=$M2D_HOME/hosts/$h
    elif [ -L "$M2D_HOME/hosts/current" ]; then HOSTDIR=$(readlink -f "$M2D_HOME/hosts/current")
    else die "no host surveyed yet -- run m2d-survey first"; fi
    [ -f "$HOSTDIR/state.env" ] || die "$HOSTDIR/state.env missing -- run m2d-survey"
    # shellcheck disable=SC1091
    . "$HOSTDIR/state.env"
}
set_state() {   # set_state KEY VALUE
    local f=$HOSTDIR/state.env
    touch "$f"
    grep -v "^$1=" "$f" > "$f.tmp" || true
    printf '%s=%q\n' "$1" "$2" >> "$f.tmp"
    mv "$f.tmp" "$f"
    eval "$1=\$2"
}
step_done() { grep -qx "$1" "$HOSTDIR/steps.done" 2>/dev/null; }
mark_done() { echo "$1" >> "$HOSTDIR/steps.done"; }

# ---- mounts ---------------------------------------------------------------
M2D_MOUNTS=()
cleanup_mounts() {
    local i
    for ((i=${#M2D_MOUNTS[@]}-1; i>=0; i--)); do
        umount -l "${M2D_MOUNTS[$i]}" 2>/dev/null || true
    done
    M2D_MOUNTS=()
}
trap cleanup_mounts EXIT

do_mount() {    # do_mount [opts...] src dir  -- tracked for cleanup
    local dir=${*: -1}
    mkdir -p "$dir"
    mountpoint -q "$dir" && return 0
    mount "$@"
    M2D_MOUNTS+=("$dir")
}
mount_mint() {  # mount_mint [ro|rw]
    do_mount -o "${1:-ro}" "$MINT_DEV" "$MINT"
    if [ -n "${MINT_BOOT_DEV:-}" ]; then do_mount -o "${1:-ro}" "$MINT_BOOT_DEV" "$MINT/boot"; fi
}
mount_target() {
    [ -n "${DEB_DEV:-}" ] || die "no Debian partition yet -- run m2d-split"
    do_mount "$DEB_DEV" "$TARGET"
}
chroot_mounts() {   # bind the API filesystems into a root
    local r=$1
    do_mount -t proc proc "$r/proc"
    do_mount -t sysfs sys "$r/sys"
    do_mount --bind /dev "$r/dev"
    do_mount --bind /dev/pts "$r/dev/pts"
    do_mount -t tmpfs tmpfs "$r/run"
    if [ -d /sys/firmware/efi/efivars ] && [ -d "$r/sys/firmware/efi/efivars" ]; then
        mount -t efivarfs efivarfs "$r/sys/firmware/efi/efivars" 2>/dev/null && M2D_MOUNTS+=("$r/sys/firmware/efi/efivars") || true
    fi
}
in_target() {
    chroot "$TARGET" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"
}
in_mint() {
    chroot "$MINT" /usr/bin/env LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin "$@"
}
target_setup() {    # mount target + API fs + resolv.conf + no service starts
    mount_target
    chroot_mounts "$TARGET"
    # resolv.conf may be a (relative) symlink into the target's /run tmpfs,
    # e.g. once resolvconf is installed -- write DNS where it points.
    local rc=/etc/resolv.conf t
    if [ -L "$TARGET$rc" ]; then
        t=$(readlink "$TARGET$rc"); case $t in /*) ;; *) t=/etc/$t ;; esac
        t=$(realpath -ms "$t"); mkdir -p "$TARGET$(dirname "$t")"; rc=$t
    fi
    cp -L /etc/resolv.conf "$TARGET$rc"
    printf '#!/bin/sh\nexit 101\n' > "$TARGET/usr/sbin/policy-rc.d"
    chmod +x "$TARGET/usr/sbin/policy-rc.d"
}
target_teardown() { rm -f "$TARGET/usr/sbin/policy-rc.d"; }

# apt in the target, non-interactive, keeping existing conffiles
tapt() {
    in_target apt-get -y -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold "$@"
}

# Install what we can from a list: bulk first, then one at a time on failure.
# Unavailable/uninstallable names are appended to $HOSTDIR/packages-skipped.txt
install_best_effort() {   # install_best_effort tag pkg...
    local tag=$1; shift
    local ok=() p
    for p in "$@"; do
        if in_target apt-get -s -qq install "$p" >/dev/null 2>&1; then ok+=("$p")
        else echo "$tag: $p (not installable on $M2D_SUITE)" >> "$HOSTDIR/packages-skipped.txt"; fi
    done
    [ ${#ok[@]} -eq 0 ] && return 0
    log "installing ${#ok[@]} $tag packages"
    if ! tapt install "${ok[@]}"; then
        warn "bulk install failed -- retrying one package at a time"
        for p in "${ok[@]}"; do
            tapt install "$p" || echo "$tag: $p (install failed)" >> "$HOSTDIR/packages-skipped.txt"
        done
    fi
}
