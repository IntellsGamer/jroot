#!/usr/bin/env bash
# Bundle encryption must preserve plain archives while authenticated encrypted
# bundles deploy only with the right password and never leave a partial jail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-bundle-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

name="demo"
mkdir -p "$ROOTS_DIR/$name/etc" "$ROOTS_DIR/$name/home/jail" "$CONFIGS_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"
printf '{"name":"demo","image":"ubuntu:22.04","user":"root"}\n' > "$CONFIGS_DIR/$name.json"
printf 'bundle-payload\n' > "$ROOTS_DIR/$name/etc/bundle-state"
record_event() { :; }

# Bare names choose Zstandard when it is available.
default_bundle="$TMP/default"
cmd_bundle "$name" "$default_bundle" >/dev/null
default_bundle+=".tar.zst"
[ -f "$default_bundle" ]
cmd_deploy "$default_bundle" default-restored >/dev/null
[ "$(cat "$ROOTS_DIR/default-restored/etc/bundle-state")" = "bundle-payload" ]

# Explicit suffixes remain portable and select their exact compressor.
for codec in gz zst xz lz4; do
    plain="$TMP/plain.tar.$codec"
    cmd_bundle "$name" "$plain" >/dev/null
    cmd_deploy "$plain" "${codec}-restored" >/dev/null
    [ "$(cat "$ROOTS_DIR/${codec}-restored/etc/bundle-state")" = "bundle-payload" ]
done

# --format is the deterministic override when callers do not want suffixes.
format_bundle="$TMP/format-selected"
cmd_bundle "$name" "$format_bundle" --format=xz >/dev/null
[ -f "$format_bundle.tar.xz" ]
cmd_deploy "$format_bundle.tar.xz" format-restored >/dev/null
[ "$(cat "$ROOTS_DIR/format-restored/etc/bundle-state")" = "bundle-payload" ]

# No TTY and no Zstandard must never block for a question: bare output falls
# back deterministically to gzip unless --format explicitly overrides it.
fallback="$TMP/noninteractive"
JROOT_FORCE_NO_ZSTD=1 cmd_bundle "$name" "$fallback" </dev/null >/dev/null
[ -f "$fallback.tar.gz" ]
cmd_deploy "$fallback.tar.gz" fallback-restored >/dev/null
[ "$(cat "$ROOTS_DIR/fallback-restored/etc/bundle-state")" = "bundle-payload" ]

password='correct horse battery staple'
encrypted="$TMP/encrypted.tar.zst"
cmd_bundle "$name" "$encrypted" --encrypt "--password=$password" >/dev/null
[ "$(bundle_encrypted_codec "$encrypted")" = "zst" ]
[ "$(head -c 9 "$encrypted")" = "JROOTBND1" ]
! tar -tzf "$encrypted" >/dev/null 2>&1
cmd_deploy "$encrypted" encrypted-restored "--password=$password" >/dev/null
[ "$(cat "$ROOTS_DIR/encrypted-restored/etc/bundle-state")" = "bundle-payload" ]

wrong_log="$TMP/wrong-password.log"
if JROOT_HOME="$JROOT_HOME" JROOT_PROGRESS=force bash "$ROOT/jroot" deploy "$encrypted" rejected "--password=wrong password" >"$wrong_log" 2>&1; then
    printf 'encrypted bundle accepted a wrong password\n' >&2
    exit 1
fi
grep -F 'wrong password or bundle authentication failed' "$wrong_log" >/dev/null
grep -F $'\r\033[2K\njroot: encrypted bundle: wrong password or bundle authentication failed' "$wrong_log" >/dev/null
! grep -F 'processingjroot:' "$wrong_log" >/dev/null
[ ! -e "$CONFIGS_DIR/rejected.json" ]
[ ! -e "$ROOTS_DIR/rejected" ]

tampered="$TMP/tampered.jrootbundle"
cp "$encrypted" "$tampered"
printf 'x' | dd of="$tampered" bs=1 seek=40 conv=notrunc status=none
if JROOT_HOME="$JROOT_HOME" bash "$ROOT/jroot" deploy "$tampered" tampered-rejected "--password=$password" >/dev/null 2>&1; then
    printf 'encrypted bundle accepted a modified payload\n' >&2
    exit 1
fi
[ ! -e "$CONFIGS_DIR/tampered-rejected.json" ]
[ ! -e "$ROOTS_DIR/tampered-rejected" ]

stdin_bundle="$TMP/stdin-encrypted.tar.xz"
printf '%s\n' "$password" | cmd_bundle "$name" "$stdin_bundle" --encrypt --password-stdin >/dev/null
[ "$(bundle_encrypted_codec "$stdin_bundle")" = "xz" ]
printf '%s\n' "$password" | cmd_deploy "$stdin_bundle" stdin-restored --password-stdin >/dev/null
[ "$(cat "$ROOTS_DIR/stdin-restored/etc/bundle-state")" = "bundle-payload" ]

printf '  ok    multi-codec plain and authenticated encrypted bundle deployment round trips safely\n'
