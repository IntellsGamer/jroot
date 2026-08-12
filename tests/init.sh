#!/usr/bin/env bash
# tests/init.sh - guard the cmd_init distribution dispatch before any network work.
# A regression left `distro` empty after image parsing, which skipped get_ubuntu /
# get_alpine and then attempted to configure an empty rootfs. This test stubs the
# expensive operations and verifies the selected image reaches the correct rootfs
# bootstrap path with the expected version and codename.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/initwork"
LIB="$WORK/jroot-lib.sh"

rm -rf "$WORK"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

# Load functions without the final main "$@" invocation.
sed '$d' "$ROOT/jroot" > "$LIB"

JROOT_HOME="$WORK/home" JROOT_SKIP_BOOTSTRAP=1 bash -s "$LIB" <<'BASH'
set -euo pipefail
source "$1"

# Replace network/runtime/bootstrap behavior with deterministic local fixtures.
log() { :; }
warn() { :; }
ensure_runtime() { mkdir -p "$ROOTS_DIR" "$CONFIGS_DIR" "$CACHE_DIR"; }
install_proot() { :; }
config_apt() { printf '%s' "$2" > "$JROOT_HOME/apt-codename"; }
config_apk() { printf '%s' "$2" > "$JROOT_HOME/apk-version"; }
write_sudoers() { :; }
write_rootfs_niceties() { :; }
write_config() { printf '{"name":"%s"}\n' "$1" > "$CONFIGS_DIR/$1.json"; }
record_event() { :; }
trigger_event_hooks() { :; }
verify_jail() { return 0; }
show_config() { :; }

get_ubuntu() {
    local name="$1" version="$2" rootfs="$ROOTS_DIR/$name"
    printf '%s' "$version" > "$JROOT_HOME/ubuntu-version"
    mkdir -p "$rootfs/etc" "$rootfs/bin"
    printf 'NAME=Ubuntu\n' > "$rootfs/etc/os-release"
    ln -s /bin/sh "$rootfs/bin/sh"
}
get_alpine() {
    local name="$1" version="$2" rootfs="$ROOTS_DIR/$name"
    printf '%s' "$version" > "$JROOT_HOME/alpine-version"
    mkdir -p "$rootfs/etc" "$rootfs/bin"
    printf 'NAME=Alpine\n' > "$rootfs/etc/os-release"
    ln -s /bin/sh "$rootfs/bin/sh"
}

cmd_init ubuntu:22.04 --name=jammy --user=root --build-essential=0 --mount-host=0 --mount-home=0
[ "$(cat "$JROOT_HOME/ubuntu-version")" = "22.04" ]
[ "$(cat "$JROOT_HOME/apt-codename")" = "jammy" ]
[ -f "$ROOTS_DIR/jammy/etc/os-release" ]
[ -L "$ROOTS_DIR/jammy/bin/sh" ]
[ -f "$CONFIGS_DIR/jammy.json" ]

cmd_init alpine:3.22 --name=alpine --user=root --build-essential=0 --mount-host=0 --mount-home=0
[ "$(cat "$JROOT_HOME/alpine-version")" = "3.22" ]
[ "$(cat "$JROOT_HOME/apk-version")" = "3.22" ]
[ -f "$ROOTS_DIR/alpine/etc/os-release" ]
[ -L "$ROOTS_DIR/alpine/bin/sh" ]
[ -f "$CONFIGS_DIR/alpine.json" ]

# `diff` is the public compare alias. It must remain unavailable as a jail name
# across every workflow that can create or introduce a jail.
if (cmd_init ubuntu:22.04 --name=diff --user=root --build-essential=0 --mount-host=0 --mount-home=0) >/dev/null 2>&1; then
    printf 'reserved init name was accepted\n' >&2
    exit 1
fi
[ ! -e "$CONFIGS_DIR/diff.json" ]

context="$JROOT_HOME/build-context"
mkdir -p "$context"
printf 'FROM ubuntu:22.04\n' > "$context/JRootfile"
if (cmd_build --tag=diff "$context") >/dev/null 2>&1; then
    printf 'reserved build tag was accepted\n' >&2
    exit 1
fi
[ ! -e "$CONFIGS_DIR/diff.json" ]

if (cmd_rename jammy diff) >/dev/null 2>&1; then
    printf 'reserved rename target was accepted\n' >&2
    exit 1
fi
[ -f "$CONFIGS_DIR/jammy.json" ]

bundle="$JROOT_HOME/reserved-name-bundle.tar.gz"
mkdir -p "$JROOT_HOME/bundle/configs" "$JROOT_HOME/bundle/roots/source"
printf '{"name":"source"}\n' > "$JROOT_HOME/bundle/configs/source.json"
tar -czf "$bundle" -C "$JROOT_HOME/bundle" configs roots
if (cmd_deploy "$bundle" diff) >/dev/null 2>&1; then
    printf 'reserved deployment name was accepted\n' >&2
    exit 1
fi
[ ! -e "$CONFIGS_DIR/diff.json" ]
BASH

printf 'all init dispatch checks passed\n'
