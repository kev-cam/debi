# debi — dual-boot a Linux Mint machine into Debian 13

debi (the `mint2deb` toolkit, driver `m2d`) adds Debian 13 "trixie" to a
working Linux Mint machine without reinstalling Mint. The Mint root partition
is split in two. Mint keeps the front half, which is shrunk in place. Debian
goes in the freed tail and takes over Mint's identity: its hostname, users,
passwords, `/home` (as a copy), ssh host keys, network connections,
autofs/samba/NIS config, `/usr/local`, crontabs, bluetooth pairings, tuner
firmware, user-installed packages and enabled services. MythTV is optional.
Debian's GRUB then owns the boot and chains to Mint's own menu.

Everything runs as root from a Debian live USB with persistence, and can be
done over ssh. Per-machine state, logs and reports are kept on the stick, in
`/opt/mint2deb/hosts/<hostname>/`.

## Tested on

| Host    | Mint | Boot | Disk | Mint root | Notes |
|---------|------|------|------|-----------|-------|
| mediapc | 21.3 MATE | BIOS | GPT | `sda7` | MythTV backend, second data disk |
| zmc2    | 22.2 Cinnamon | UEFI via rEFInd | MBR | `sda5`, last logical | `/swapfile`, grub-pc and grub-efi both installed |

## Files

| File | Purpose |
|------|---------|
| `m2d` | Driver: `m2d status`, `m2d <step>`, `m2d all [--yes]` |
| `m2d-prep-usb` | Run on the Mint machine. Sets up the stick's persistence and reboots into it |
| `m2d-survey` | Finds the Mint root and records the layout and inventory. Read-only |
| `m2d-split` | Shrinks Mint's root and creates the Debian partition |
| `m2d-install` | debootstrap, kernel, firmware and the desktop matching Mint's edition |
| `m2d-migrate` | Users, `/home`, config, packages, services |
| `m2d-mythtv` | MythTV 35 from deb-multimedia, plus a copy of Mint's database |
| `m2d-boot` | Debian GRUB, the Mint chain entry and `m2d-bootctl` |
| `m2d-bootctl.in` | Template for the OS switcher installed in both systems |
| `lib.sh` | Shared helpers: state, mounts, chroot, apt |
| `pkgmap.txt` | Mint/Ubuntu to Debian package name map, with `-` meaning drop |

## Making the stick

1. Write a Debian 13 **live** image (for example
   `debian-live-13.*-amd64-cinnamon.iso`) to a USB stick of 16 GB or more,
   with a persistence partition. With Rufus on Windows, set the persistent
   partition size. On Linux, `dd` the hybrid ISO, then create an ext4
   partition in the free space and set it up:

       mkfs.ext4 -L persistence /dev/sdX2
       mount /dev/sdX2 /mnt && echo '/ union' > /mnt/persistence.conf && umount /mnt

   The partition must be labelled `persistence`. Rufus adds `persistence`
   to the stick's own boot menu. A `dd`-written stick keeps the ISO's menu,
   which doesn't pass it. Either way works with the next step, because the
   GRUB entry that `m2d-prep-usb` adds always passes `persistence`.
2. On the Mint machine, plug in the stick, clone this repo and run:

       sudo ./m2d-prep-usb --reboot

   This installs sshd, debootstrap, gdisk and efibootmgr into the
   persistence. It appends root's `authorized_keys` (or `--keys FILE`) to the
   stick's root account, and copies the toolkit to `/opt/mint2deb`. It then
   adds a "Debian Live USB (persistence)" entry to Mint's GRUB and boots it
   once. On UEFI it also sets the firmware's `BootNext` to Mint's own
   GRUB/shim entry, so a boot manager in front of GRUB, such as rEFInd,
   doesn't get in the way. If the stick can't be read, GRUB falls back to
   Mint.

   Without `--reboot` it only prepares the stick. `--grub-entry` adds the
   menu entry without rebooting.

## Before you start: export Firefox bookmarks and history

> **Warning:** on mediapc, Firefox bookmarks and history were lost in Debian.

Mint ships the current Firefox release. Debian 13 ships `firefox-esr`, which
is an older version. The profile copied with `/home` was written by the
newer Firefox, so Debian's Firefox doesn't use it, and the user appears to
start with an empty profile.

For each user, on Mint, before `m2d migrate`:

- **Bookmarks:** Bookmarks → Manage Bookmarks → Import and Backup →
  **Export Bookmarks to HTML**, or **Backup** for a JSON file. Import the
  file in Debian's Firefox.
- **History:** Firefox has no built-in history export, but history-export
  add-ons on addons.mozilla.org do it. Export on Mint and import in Debian's
  Firefox with the same add-on. Alternatively, sign in to a Firefox account on
  Mint and let it sync, and Debian's Firefox pulls bookmarks, history and
  passwords. As a fallback, keep a copy of `places.sqlite` from the profile
  directory under `~/.mozilla/firefox/`.
- **Passwords:** Settings → Passwords → ⋯ → **Export passwords** (a CSV
  file, so delete it after importing).

Mint's own `/home` isn't modified, so the original profile is still there
under Mint if something was missed.

## Procedure

In the live session, as root (for example `ssh root@<machine>`; the host key
differs from Mint's):

    m2d survey            # finds Mint and records the layout (read-only)
    m2d split             # prints the plan: half/half by default, Mint keeps at least used+25%+10G
    m2d split --yes       # does it (add --backup DIR on another disk to rsync Mint first)
    m2d install           # debootstrap + kernel + firmware + matching desktop
    m2d migrate           # users, home, config, packages, services
    m2d mythtv            # only acts if Mint had MythTV
    m2d boot              # Debian GRUB + Mint chain entry + m2d-bootctl

`m2d all --yes` runs the same steps in order and skips any that are done.
Without `--yes`, it stops after printing the split plan.

To change the split, use `m2d split --mint-size 32G` or `--deb-size 60G`.
Mint's filesystem can only be shrunk from its end, so Debian always gets the
tail of the old partition.

Reboot when `m2d status` lists `boot` as done. The menu shows Debian first,
then "Linux Mint … (Mint boot menu)". Then check the reports in
`hosts/<host>/`:

- `packages-skipped.txt` lists what couldn't be carried over.
- `etc-review.txt` lists modified or unowned `/etc` files that weren't copied.
- `mint-thirdparty-repos.txt` lists third-party repos, which are not migrated.

## Switching OS remotely

Both systems get `/usr/local/sbin/m2d-bootctl`:

    m2d-bootctl next mint && reboot      # once
    m2d-bootctl default debian           # permanently
    m2d-bootctl restore-mint             # on Mint: hand the boot back to Mint

On BIOS machines, `restore-mint` reinstalls Mint's GRUB to the disk. On UEFI
machines, it restores the firmware `BootOrder` saved by `m2d survey`.

## MythTV (independent copies)

- Debian gets MythTV 35 from deb-multimedia, pinned so that only `*myth*`
  packages come from dmo. The DB server is MariaDB.
- Mint's `mythconverg` is dumped once, using Mint's own mysqld in a chroot, and
  loaded into Debian with the same DB user and password. MythTV upgrades the
  schema on the first `mythbackend` start. **Mint's DB is never modified.**
- Recording directories on shared disks are the same on both OSes. From the
  copy onward the two databases diverge:
  - a recording made under one OS isn't listed under the other;
  - autoexpire or deletes on one side can remove files the other still lists.
- MariaDB's time-zone tables are loaded. Without them MythTV 35 starts in
  "Web App only" mode and never upgrades the schema.
- MythTV names differ between the two distros. `mythtv-transcode-utils`
  becomes `mythtv-transcode`, and `libmyth-python` becomes `python3-mythtv`.
  MythWeb is available from dmo; the built-in web app is on port 6544.
- Pinning: dmo's MythTV hard-depends on dmo builds of about 9 libraries
  (libass9, libbluray2, x265, ...). `m2d-mythtv` finds these from apt's error
  output and pins only those (see `hosts/<host>/dmo-pinned-extra.txt`).
- The numeric mythtv uid/gid in fstab and autofs mount options is remapped to
  Debian's IDs.

## Limits and assumptions

- Mint's root must be ext4. The split takes space from its tail, so the
  partition table needs GPT, a free msdos primary slot, or root as the last
  logical partition. A logical root gets the new partition 1 MiB further on,
  leaving room for the new partition's EBR.
- The machine needs network access during install (deb.debian.org and
  www.deb-multimedia.org).
- Swap is shared, and Debian never resumes from it (`RESUME=none`). Don't
  hibernate Mint and then boot Debian. A Mint `/swapfile` lives on Mint's
  root, so Debian gets its own `/swapfile` of the same size.
- Boot mode is how *Mint* boots. It is read from which GRUB platform directory
  Mint's `/boot/grub` holds, because Mint can have `grub-pc` and
  `grub-efi-amd64-signed` installed together. The live session should boot
  the same way.
- UEFI: `m2d boot` installs Debian's GRUB as `EFI/debian` and makes it first
  in the firmware order. The previous first entry is kept. When rEFInd is on
  the ESP, Debian's menu gets a "rEFInd Boot Manager" entry. Mint is told not
  to touch NVRAM on its own GRUB updates. Debian's menu may also show a
  separate os-prober entry for Mint's EFI loader.
- The stick's own GRUB menu has no timeout. Booting the stick directly, for
  example from the firmware menu, waits at that menu until someone picks an
  entry. `m2d-prep-usb --reboot` avoids this by booting the live kernel from
  Mint's GRUB.
- Disk names such as `/dev/sdb1` aren't stable. On mediapc, Debian numbered
  the two disks in the opposite order to Mint. `m2d-migrate` rewrites them to
  `/dev/disk/by-uuid`, but only after checking Mint's kern.log to confirm the
  live session names disks the same way Mint did. Otherwise it flags them in
  `etc-review.txt`.
- Debian 13's OpenSSH 10 has no DSA support. Any `+ssh-dss` option is
  stripped, since it would make the whole ssh config fatal, and hosts that
  only offer DSA (old NAS boxes) can't be reached over ssh or sshfs from
  Debian.
- **Not yet migrated: netplan-held connections.** Mint 22 (Ubuntu 24.04
  base) can store NetworkManager connections as netplan files,
  `/etc/netplan/90-NM-<uuid>.yaml`, instead of in
  `/etc/NetworkManager/system-connections/`. `m2d-migrate` copies only the
  latter. On zmc2 the Wi-Fi connection "scorpius5" was lost this way. Re-add
  it in Debian, or convert the YAML to a keyfile by hand.
- Rollback: `hosts/<host>/ptable-before-split.sfdisk` holds the original
  partition table. The shrunk Mint filesystem stays valid under either table
  and can be grown back with `resize2fs`.

## License

Copyright (c) 2026 D. Kevin Cameron.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).
