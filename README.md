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
| P620A   | none (Windows 11) | UEFI | GPT | none | `m2d win`, headless: fresh Debian in free space beside an NTFS data drive; Windows stays first, Debian booted with `boot-debian.sh` |

## Files

| File | Purpose |
|------|---------|
| `m2d` | Driver: `m2d status`, `m2d <step>`, `m2d all [--yes]`, `m2d fix-grub`, `m2d next`, `m2d update` |
| `m2d-prep-usb` | Run on the Mint machine. Sets up the stick's persistence and reboots into it |
| `m2d-survey` | Finds the Mint root and records the layout and inventory. Read-only |
| `m2d-split` | Shrinks Mint's root and creates the Debian partition |
| `m2d-install` | debootstrap, kernel, firmware and the desktop matching Mint's edition |
| `m2d-migrate` | Users, `/home`, config, packages, services |
| `m2d-mythtv` | MythTV 35 from deb-multimedia, plus a copy of Mint's database |
| `m2d-boot` | Debian GRUB, the Mint chain entry and `m2d-bootctl` |
| `m2d-bootctl.in` | Template for the OS switcher installed in both systems |
| `m2d-fix-grub` | Rescue: reinstall and regenerate Mint's GRUB from the stick. No survey needed |
| `m2d-update` | Updates the toolkit on the stick from GitHub over HTTPS. `hosts/` is kept |
| `m2d-next` | From the stick: find the GRUB that boots the machine, list its menu, set the next boot |
| `m2d-win` | Fresh Debian beside Windows on UEFI (no Mint): survey, format, install, user, GRUB |
| `windows/seed.ps1` | Run on Windows: writes the host seed for `m2d win` to the stick |
| `windows/boot-debian.ps1` | Run on Windows (elevated): boot Debian once |
| `m2d-auto`, `m2d-auto-hook` | Headless: run `m2d win` unattended from the stick, then reboot to Windows |
| `windows/stick-auto.ps1` | Run on Windows: set the stick to run `m2d win` (plan/yes) on its next boot |
| `windows/reboot-to-usb.ps1` | Run on Windows (elevated): boot the stick once via a firmware entry |
| `lib.sh` | Shared helpers: state, mounts, chroot, apt |
| `mount-chroot` | Standalone rescue tool: mounts an installed system, chroots into it, repairs GRUB |
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

## Windows machines: `m2d win`

`m2d win` installs a fresh Debian next to Windows on a UEFI machine. There is
no Mint, so nothing is split or migrated. Debian goes into an empty partition,
or into unallocated space that you free in Windows Disk Management. Either
must be at least 20 GiB and sit on the same disk as an NTFS drive that you
name. An existing partition is used only if it's empty.

1. On Windows, with the stick plugged in (no elevation needed):

       powershell -ExecutionPolicy Bypass -File windows\seed.ps1 -Stick E: -Sibling G `
           -AuthorizedKeys $HOME\.ssh\id_ed25519.pub

   This writes `debi\hosts\<COMPUTERNAME>\seed.env` to the stick's FAT
   partition. The seed holds the hostname, the user, the time zone, the
   locale, the desktop, and the serial of every NTFS volume. No password goes
   on the stick.
2. Boot the stick in **UEFI** mode from the firmware boot menu. As root, run:

       m2d update               # picks up m2d-win
       m2d win                  # plan only: target, ESP, NTFS mounts, boot order
       m2d win --yes            # partition/format, debootstrap, user, GRUB

   It asks for the Debian password at the console. `M2D_HOST=<name>` picks a
   seed when the stick carries several. `--step win-boot` (or any other step)
   reruns one step.
3. Remove the stick and reboot.

What you get:
- GRUB goes on the **Windows ESP** as `EFI/debian` (shim, so it boots with
  Secure Boot on). Windows stays first in the firmware BootOrder, with Debian
  second. `--default debian` reverses that.
  - From Windows, boot Debian once with `windows\boot-debian.ps1 -Reboot`
    from an elevated shell. Where PowerShell scripts are blocked, run the
    Cygwin twin `windows/boot-debian.sh --reboot` from an elevated Cygwin
    terminal. It logs every step to `/tmp/boot-debian.log`.
  - From Debian, use `win-bootctl next|default windows|debian` (or `win-bootctl show`).
    It finds the two firmware entries by their ESP path on every run, so it
    survives the firmware re-numbering or relabelling them.

  Debian's grub is told not to reorder NVRAM on its own updates. Debian's own
  menu gets a "Windows Boot Manager" entry that chainloads
  `\EFI\Microsoft\Boot\bootmgfw.efi` from the ESP by UUID. os-prober is off,
  because inside the install chroot it found nothing.
- `bcdedit` appends "A device which does not exist was specified." to every
  command while some firmware entry's device is missing. One example is
  "debi USB" with the stick unplugged. The message is noise, and it can make
  `bcdedit` exit 1 even though the command worked, so the boot scripts check
  success by reading the boot sequence back.
- Windows NTFS drives are mounted at `/mnt/c`, `/mnt/d` and so on, the same
  paths WSL uses, with `ntfs3,nofail`. They are **read-only** because
  Windows Fast Startup leaves them hibernated. Pass `--ntfs-rw` only after an
  elevated `powercfg /h off`.
- The RTC is kept in local time (`/etc/adjtime` LOCAL) to match Windows, and
  `systemd-timesyncd` is installed. The live session has the opposite problem:
  it reads the local-time RTC as UTC. On P620A (Pacific time) its clock was
  7 hours slow, and apt rejected the mirror's fresh signatures with "Not live
  until ...". So `m2d win` and `m2d-auto` set the live clock from the
  mirror's HTTP `Date` header before running apt. The RTC is left to Windows.
- There is an 8 GiB `/swapfile`, and `qemu-utils` is installed. A WSL
  `ext4.vhdx` on an NTFS drive can be opened read-only with
  `qemu-nbd -r -c /dev/nbd0 .../ext4.vhdx`.
- A record (state, efibootmgr before/after, the partition table before a
  partition was created) is copied back to the stick, to
  `debi\hosts\<host>\`, where Windows can read it.

### Headless Windows machines

When nobody is at the console, the stick can run `m2d win` by itself and then
reboot into Windows:

    powershell -ExecutionPolicy Bypass -File windows\seed.ps1 -Stick E: -Sibling G -User installer -Password installer
    powershell -ExecutionPolicy Bypass -File windows\stick-auto.ps1 -Stick E: -Mode plan
    # elevated:
    powershell -ExecutionPolicy Bypass -File windows\reboot-to-usb.ps1 -Stick E:

- `stick-auto.ps1` copies the toolkit to `debi\toolkit` on the stick. It adds
  a first boot entry with a 5 s timeout, which passes the `m2d-auto-hook`
  live-config hook (`hooks=file://...`), and writes the mode to
  `debi\auto\mode`. The stick's original `grub.cfg` and `config.cfg` are
  kept as `*.debi-orig`.
- `reboot-to-usb.ps1` creates a firmware entry, "debi USB", from a copy of
  `{bootmgr}`. The entry points at the stick's `\EFI\boot\bootx64.efi`, which
  is shim, so Secure Boot is fine. The script makes it the one-shot boot
  sequence and restarts.
- In the live session, `m2d-auto` waits for the network, installs
  debootstrap, efibootmgr and sshd, and runs `m2d win` (with `--yes` in `yes`
  mode). It writes `debi\auto\out\<mode>-<time>.log` and
  `debi\hosts\<host>\`. It then sets BootNext to Windows Boot Manager and
  reboots. The mode becomes `planned`, `done` or `failed`, so booting the
  stick again does nothing. After `done`, the stick's own menu is restored.
- It acts only if the seed's `-Sibling` NTFS volume is present, so the same
  stick can boot other machines safely.
- Read the plan log, then run `stick-auto.ps1 -Mode yes` and
  `reboot-to-usb.ps1` again. `-Mode off` restores the stick by hand.
  `windows/boot-debian.sh --usb E:` does the same job as `reboot-to-usb.ps1`
  from an elevated Cygwin terminal.
- After an install, `-Mode diag` records the firmware entries
  (`efibootmgr -v`), the ESP's `EFI/debian`, the Secure Boot state and
  Debian's own boot history, then returns to Windows. `-Mode debian` does
  the same, then boots Debian's entry with BootNext set from Linux, which
  takes Windows' `bcdedit` out of the picture.
- While it runs, the live session has sshd (user `user`, password `live`).
- `-Password` stores a throwaway password in clear on the stick. Change it
  after the first login.

`wsl --mount` puts a whole physical disk offline in Windows. If the WSL
distro's vhdx lives on the same disk as the Debian partition, WSL can't mount
that partition, but Debian can still read the vhdx.

## Updating the toolkit on the stick

In the live session, as root:

    m2d update --check           # is main newer than what's installed?
    m2d update                   # install the head of main
    m2d update --ref 6d964a4     # a specific commit, tag or branch (pin / roll back)
    m2d update --from debi.tar.gz   # offline, from a downloaded tarball
    m2d status                   # first line shows the installed commit

It downloads the GitHub tarball over plain HTTPS, so it needs no git and no
keys. Before replacing anything it unpacks the tarball into a scratch
directory and syntax-checks every script. `hosts/` is never touched. Files
from the previous update that the new version no longer has are removed,
except `m2d-update` itself, so a rollback can always roll forward again.

It never runs by itself. Updating in the middle of a conversion would swap
scripts under a half-finished run, so update between machines. `m2d-prep-usb`
records the commit it copied, and marks it `-dirty` if the checkout had local
changes.

## Rescue: Mint won't boot (GRUB broken)

Boot the stick and, as root, run:

    m2d fix-grub --dry-run      # shows the root, boot mode, target disk, kernels
    m2d fix-grub                # dpkg --configure -a, grub-install, update-grub

This needs no survey. It uses the root `m2d survey` recorded, or `--root`, or
finds the Mint/Ubuntu root itself and asks if there are several. The mounting
is done by `mount-chroot` (below), so a LUKS or LVM root works, Mint's whole
fstab is mounted, and the DNS that apt needs never overwrites Mint's
`/etc/resolv.conf`. `--dry-run` mounts everything read-only. It takes the boot mode from the platform directory grub-install last
populated in Mint's `/boot/grub`, falling back to Mint's GRUB packages. It
doesn't use how the stick booted. In UEFI mode, a boot manager that was first
in the firmware order, such as rEFInd, stays first. In BIOS mode it installs to the disk named in Mint's own
debconf (`grub-pc/install_devices`); `--disk` overrides that. If the GRUB
packages are missing it reinstalls them, which needs network access.

Extra options:
- `--initramfs` rebuilds the initramfs images, for example after
  graphics-driver surgery.
- `--nomodeset` boots past a broken GPU driver. Remove it again once
  graphics work.

On an m2d dual-boot, this hands the boot back to Mint's GRUB, and Debian stays
in Mint's menu.

## Repairing GRUB: `mount-chroot`

`mount-chroot` mounts an installed system from the live session and chroots
into it. It needs nothing else from the toolkit, so a copy on any rescue stick
works. `m2d-prep-usb` links it as `/usr/local/sbin/mount-chroot`.
Use `m2d fix-grub` for a Mint or Ubuntu system. It mounts through
`mount-chroot`, then also repairs half-configured packages, follows Mint's own
debconf and keeps rEFInd first. Use `mount-chroot --fix-grub` for any other
distribution, or plain `mount-chroot` when you just need a shell inside the
installed system.

    mount-chroot --dev /dev/nvme0n1 --fix-grub   # find the root on the disk, reinstall GRUB
    mount-chroot --dev /dev/sda6                 # mount that root and open a shell in it
    mount-chroot --list                          # every installed system on every disk

Given a disk, it looks for root filesystems, meaning ones with `/etc/fstab` and
`os-release`. It unlocks LUKS and activates LVM on the way, and asks which one
to use if it finds more than one. It then mounts everything else in that
system's fstab, deepest mount points last, skipping network, `noauto` and bind
entries. Finally it binds `/dev`, `/proc`, `/sys`, `efivarfs` and a fresh
`/run`. Everything is unmounted on exit unless `--keep` is given;
`mount-chroot --umount` then unmounts it and closes the LUKS and LVM devices
that run opened. For scripts, `--mount` only mounts, implies `--keep` and
opens no shell; `--ro` mounts read-only and `--os linuxmint,ubuntu` limits
the search to those `os-release` IDs. `m2d fix-grub` uses all three.

`--fix-grub` decides the boot mode from the GRUB platform directories in the
installed `/boot/grub`, the same test `m2d survey` uses. If both are present,
it goes by how the live session booted. `--bios` or `--uefi` overrides this.

- **BIOS:** it runs `grub-install` to the disk holding `/boot` and points
  Debian/Ubuntu's `grub-pc/install_devices` at that disk.
- **UEFI:** it runs `grub-install` to the ESP. If the live session booted in
  BIOS mode it can't write a firmware boot entry, so it adds the
  `EFI/BOOT/BOOTX64.EFI` fallback loader instead. `--removable` adds that
  fallback in any case.

Either way it then runs `update-grub` (`grub-mkconfig` on Arch). `--initramfs`
also rebuilds the initramfs.

On a machine converted by `m2d`, pick Debian's partition, because Debian's GRUB
owns the boot and chains to Mint's menu. Single dashes also work
(`mount-chroot -dev /dev/sda -fix-grub`).

## Choosing what boots next (from the live USB)

    m2d next                     # which GRUB boots this machine + its numbered menu
    m2d next 6                   # boot entry 6 once, then back to the default
    m2d next 79-generic          # or pick by a unique piece of the title
    m2d next --default 1         # change the default (only if GRUB_DEFAULT=saved)
    m2d next --clear

It finds the GRUB that actually boots the machine, rather than guessing from
disk names:
- **BIOS:** it matches the core image embedded after each disk's MBR against
  every `/boot/grub/i386-pc/core.img`.
- **UEFI:** it walks BootNext and then BootOrder to the first entry that is a
  GRUB (an `EFI/<id>/grub.cfg` beside it), and from there to the partition
  that file searches for. If something else starts first, such as rEFInd on
  zmc2 or the stick itself, a one-shot choice also sets the firmware's
  `BootNext` to that GRUB.

It then edits that GRUB's 1024-byte `grubenv` in place. Submenu entries such as
specific kernels work.

When you reboot, remove the stick or pick the disk in the firmware boot menu,
because the stick may be first in the boot order.

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
