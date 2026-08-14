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
printf 'nameserver 1.1.1.1\n' > "$TMP/host-resolv.conf"
export JROOT_HOST_RESOLV_CONF="$TMP/host-resolv.conf"

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

# Some Termux Python builds omit os.link rather than exposing a syscall that
# fails. Make the embedded extractor see that exact API surface.
mkdir -p "$TMP/python-no-link"
cat > "$TMP/python-no-link/sitecustomize.py" <<'PY'
import os
if hasattr(os, "link"):
    del os.link
PY
export PYTHONPATH="$TMP/python-no-link${PYTHONPATH:+:$PYTHONPATH}"

# Simulate Android's DNS-property interface when no readable resolver file is
# available; real Termux exposes this through getprop or /system/bin/getprop.
mkdir -p "$TMP/android-bin"
cat > "$TMP/android-bin/getprop" <<'SH'
#!/bin/sh
case "$1" in
  net.dns1) printf '10.23.0.1\n' ;;
  net.dns2) printf '10.23.0.2\n' ;;
esac
SH
chmod +x "$TMP/android-bin/getprop"
export PATH="$TMP/android-bin:$PATH"

# Keep cmd_init deterministic while retaining the real get_ubuntu extraction
# path; the cached archive below contains a deliberate hard-link member.
ensure_runtime() { mkdir -p "$ROOTS_DIR" "$CONFIGS_DIR" "$CACHE_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"; }
install_proot() { :; }
write_sudoers() { :; }
verify_jail() { [ -f "$ROOTS_DIR/$1/etc/os-release" ]; }
record_event() { :; }
trigger_event_hooks() { :; }

fixture="$TMP/rootfs"
mkdir -p "$fixture/etc" "$fixture/bin" "$fixture/usr/bin"
printf 'NAME=Termux fixture\n' > "$fixture/etc/os-release"
# Ubuntu base archives often carry this link, but /run does not yet exist when
# JRoot configures a fresh rootfs. Termux must receive a plain copied resolver.
ln -s /run/systemd/resolve/stub-resolv.conf "$fixture/etc/resolv.conf"
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
[ -f "$rootfs/etc/resolv.conf" ]
[ ! -L "$rootfs/etc/resolv.conf" ]
[ -s "$rootfs/etc/resolv.conf" ]

# Existing Termux jails created before the repair are healed on their next run
# only when their resolver remains the broken image-default symlink.
rm -f "$rootfs/etc/resolv.conf"
ln -s /run/systemd/resolve/stub-resolv.conf "$rootfs/etc/resolv.conf"
repair_jail_resolver termux-init
[ -f "$rootfs/etc/resolv.conf" ]
[ ! -L "$rootfs/etc/resolv.conf" ]
grep -qx 'nameserver 1.1.1.1' "$rootfs/etc/resolv.conf"

# When Termux has no readable resolver file, Android DNS properties supply the
# nameservers instead of leaving the jail without networking.
rm -f "$rootfs/etc/resolv.conf"
ln -s /run/systemd/resolve/stub-resolv.conf "$rootfs/etc/resolv.conf"
JROOT_HOST_RESOLV_CONF="$TMP/no-such-resolver" repair_jail_resolver termux-init
grep -qx 'nameserver 10.23.0.1' "$rootfs/etc/resolv.conf"
grep -qx 'nameserver 10.23.0.2' "$rootfs/etc/resolv.conf"

# A failed network update must return a failed bootstrap. The old script ignored
# apt-get update errors and reached its success marker regardless.
printf '%s\n' '{"name":"bootstrap-failure","build_essential":0}' > "$CONFIGS_DIR/bootstrap-failure.json"
if (
    run_in_jail() {
        local script="${@: -1}"
        apt-get() { return 1; }
        dpkg() { return 0; }
        export -f apt-get dpkg
        bash -c "$script"
    }
    bootstrap_ubuntu bootstrap-failure jammy
) >/dev/null 2>&1; then
    printf 'bootstrap accepted a failed apt-get update\n' >&2
    exit 1
fi

# A PRoot launch over this no-hardlink rootfs must use the native
# link-to-symlink compatibility flag so dpkg can create status-old safely.
cat > "$TMP/fake-proot" <<'SH'
#!/bin/sh
if [ "${1:-}" = "--help" ]; then
    printf '%s\n' '  -l, --link2symlink'
    exit 0
fi
printf '%s\n' "$@" > "$JROOT_TEST_PROOT_ARGS"
SH
chmod +x "$TMP/fake-proot"
export JROOT_TEST_PROOT_ARGS="$TMP/proot-args"
PROOT_BIN="$TMP/fake-proot" SECCOMP_LAUNCHER="$TMP/no-seccomp" \
    JROOT_SHIM_OFF=1 JROOT_LANDLOCK_OFF=1 run_in_jail termux-init /bin/true
grep -qx -- '--link2symlink' "$JROOT_TEST_PROOT_ARGS"

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

printf '  ok    Termux DNS, link-to-symlink dpkg support, no-hardlink init, bootstrap failure, checkpoints, restore, and clones work\n'
