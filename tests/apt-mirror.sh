#!/usr/bin/env bash
# tests/apt-mirror.sh - the Ubuntu archive mirror is configurable per jail, not
# hardcoded: `jroot apt config` shows/sets/resets it, any http(s) URL works
# (https is NOT forced), the default follows the host mirror when the host has
# an Ubuntu archive configured, else the builtin default. Invalid values fall
# back instead of poisoning APT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-mirror-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

ensure_runtime() { mkdir -p "$ROOTS_DIR" "$CONFIGS_DIR" "$CACHE_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"; }
record_event() { :; }
ensure_runtime

mkdir -p "$ROOTS_DIR/m1"
printf '{"name":"m1","image":"ubuntu:22.04","user":"root"}\n' > "$CONFIGS_DIR/m1.json"

# Fake host APT config: one Ubuntu mirror (http, not https) plus Debian noise
# and a commented-out line that must be ignored.
mkdir -p "$TMP/host-apt/sources.list.d"
cat > "$TMP/host-apt/sources.list" <<'EOF'
# deb http://commented.example/ubuntu/ jammy main
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted
EOF
cat > "$TMP/host-apt/sources.list.d/debian.list" <<'EOF'
deb https://deb.debian.org/debian/ bookworm main
EOF
export JROOT_HOST_APT_DIR="$TMP/host-apt"
unset JROOT_APT_MIRROR

# 1) host default is adopted (plain http, scheme not forced).
[ "$(host_apt_mirror)" = "http://archive.ubuntu.com/ubuntu" ]
[ "$(jail_apt_mirror m1)" = "http://archive.ubuntu.com/ubuntu" ]

# 2) Debian-only host config -> builtin default.
mkdir -p "$TMP/debian-apt/sources.list.d"
printf 'deb https://deb.debian.org/debian/ bookworm main\n' > "$TMP/debian-apt/sources.list"
JROOT_HOST_APT_DIR="$TMP/debian-apt" jail_apt_mirror m1 | grep -qx 'https://archive.ubuntu.com/ubuntu'
JROOT_HOST_APT_DIR="$TMP/debian-apt" host_apt_mirror && { printf 'debian host produced a mirror\n' >&2; exit 1; } || true
export JROOT_HOST_APT_DIR="$TMP/host-apt"

# 3) explicit jail setting beats the host default; trailing slash stripped.
set_config_field "$CONFIGS_DIR/m1.json" apt_mirror "https://mirror.example/ubuntu/"
[ "$(jail_apt_mirror m1)" = "https://mirror.example/ubuntu" ]
config_apt m1 jammy
grep -qx 'deb \[arch=amd64 trusted=yes\] https://mirror.example/ubuntu/ jammy main restricted universe multiverse' "$ROOTS_DIR/m1/etc/apt/sources.list"
grep -qx 'deb \[arch=amd64 trusted=yes\] https://mirror.example/ubuntu/ jammy-security main restricted universe multiverse' "$ROOTS_DIR/m1/etc/apt/sources.list"

# 4) env override beats everything (test seam, not persisted).
JROOT_APT_MIRROR="http://env.example/ubuntu" jail_apt_mirror m1 | grep -qx 'http://env.example/ubuntu'
unset JROOT_APT_MIRROR

# 5) non-http(s) garbage falls back to builtin, never poisons apt.
set_config_field "$CONFIGS_DIR/m1.json" apt_mirror "ftp://evil.example/ubuntu"
[ "$(jail_apt_mirror m1)" = "https://archive.ubuntu.com/ubuntu" ]

# 6) `jroot apt config` show/set/reset through the real CLI.
set_config_field "$CONFIGS_DIR/m1.json" apt_mirror ""
bash "$ROOT/jroot" apt config m1 | grep -qx 'mirror: http://archive.ubuntu.com/ubuntu'
bash "$ROOT/jroot" apt config m1 https://mirror.example/ubuntu/ >/dev/null
[ "$(config_field "$CONFIGS_DIR/m1.json" apt_mirror)" = "https://mirror.example/ubuntu" ]
grep -qx 'deb \[arch=amd64 trusted=yes\] https://mirror.example/ubuntu/ jammy main restricted universe multiverse' "$ROOTS_DIR/m1/etc/apt/sources.list"
bash "$ROOT/jroot" apt config m1 reset >/dev/null
[ -z "$(config_field "$CONFIGS_DIR/m1.json" apt_mirror)" ]
bash "$ROOT/jroot" apt config m1 | grep -qx 'mirror: http://archive.ubuntu.com/ubuntu'
if bash "$ROOT/jroot" apt config m1 gopher://x >/dev/null 2>&1; then
    printf 'invalid mirror was accepted\n' >&2
    exit 1
fi
if bash "$ROOT/jroot" apt config nosuchjail 2>/dev/null; then
    printf 'missing jail was accepted\n' >&2
    exit 1
fi

printf '  ok    apt mirror show/set/reset, host default, http + fallback work\n'
