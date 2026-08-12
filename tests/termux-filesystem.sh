#!/usr/bin/env bash
# tests/termux-filesystem.sh - Android shared storage and other FUSE-backed
# filesystems can reject archive or rsync hard links. Every lifecycle path must
# still work by materializing independent private file copies.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-termux-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"
export JROOT_FORCE_NO_HARDLINKS=1
export JROOT_FORCE_LINK_SAFE_EXTRACT=1
export JROOT_SKIP_BOOTSTRAP=1

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

# Keep cmd_init deterministic while retaining the real get_ubuntu extraction
# path; the cached archive below contains a deliberate hard-link member.
ensure_runtime() { mkdir -p "$ROOTS_DIR" "$CONFIGS_DIR" "$CACHE_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"; }
install_proot() { :; }
config_apt() { :; }
write_sudoers() { :; }
verify_jail() { [ -f "$ROOTS_DIR/$1/etc/os-release" ]; }
record_event() { :; }
trigger_event_hooks() { :; }

fixture="$TMP/rootfs"
mkdir -p "$fixture/etc" "$fixture/bin" "$fixture/usr/bin"
printf 'NAME=Termux fixture\n' > "$fixture/etc/os-release"
printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/sh"
chmod +x "$fixture/bin/sh"
printf 'shared program data\n' > "$fixture/usr/bin/tool"
ln "$fixture/usr/bin/tool" "$fixture/usr/bin/tool-alias"
mkdir -p "$CACHE_DIR"
tar -czf "$CACHE_DIR/ubuntu-base-22.04-${ROOTFS_ARCH}.tar.gz" -C "$fixture" .

# This is a real cmd_init call. The normal tar extractor is intentionally
# bypassed, proving the archive hard-link fallback makes a bootable rootfs.
cmd_init ubuntu:22.04 --name=termux-init --user=root --build-essential=0 --mount-host=0 --mount-home=0 >/dev/null
rootfs="$ROOTS_DIR/termux-init"
[ "$(cat "$rootfs/usr/bin/tool")" = 'shared program data' ]
[ "$(cat "$rootfs/usr/bin/tool-alias")" = 'shared program data' ]
[ "$(stat -c '%i' "$rootfs/usr/bin/tool")" != "$(stat -c '%i' "$rootfs/usr/bin/tool-alias")" ]

# Checkpoints, restore, and checkpoint clones must avoid rsync --link-dest on a
# no-link filesystem and leave every mutable copy independent.
cmd_checkpoint termux-init termux-cp >/dev/null
checkpoint="$SNAPSHOTS_DIR/termux-init/checkpoints/termux-cp"
[ "$(stat -c '%i' "$rootfs/usr/bin/tool")" != "$(stat -c '%i' "$checkpoint/usr/bin/tool")" ]
printf 'changed live state\n' > "$rootfs/etc/state.txt"
cmd_clone checkpoint termux-init termux-cp termux-checkpoint-clone >/dev/null
[ ! -e "$ROOTS_DIR/termux-checkpoint-clone/etc/state.txt" ]
printf 'clone-only state\n' > "$ROOTS_DIR/termux-checkpoint-clone/etc/state.txt"
[ ! -e "$checkpoint/etc/state.txt" ]
restore_checkpoint_now termux-init termux-cp
[ ! -e "$ROOTS_DIR/termux-init/etc/state.txt" ]

# Snapshot clone exercises the same hard-link-safe archive extractor used by
# init, but through the public snapshot lifecycle.
cmd_snapshot termux-init termux-snapshot >/dev/null
cmd_clone snapshot termux-init termux-snapshot termux-snapshot-clone >/dev/null
[ "$(cat "$ROOTS_DIR/termux-snapshot-clone/usr/bin/tool")" = 'shared program data' ]
[ "$(stat -c '%i' "$ROOTS_DIR/termux-snapshot-clone/usr/bin/tool")" != "$(stat -c '%i' "$ROOTS_DIR/termux-snapshot-clone/usr/bin/tool-alias")" ]

printf '  ok    Termux-style no-hardlink init, checkpoints, restore, and clones work\n'
