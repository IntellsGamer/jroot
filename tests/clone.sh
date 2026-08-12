#!/usr/bin/env bash
# tests/clone.sh - saved-state clones must be isolated from the source and safe
# to start as distinct host-facing jails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-clone-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

source_name="source"
mkdir -p "$ROOTS_DIR/$source_name/etc/ssh" "$CONFIGS_DIR" "$SNAPSHOTS_DIR"
printf '%s\n' 'checkpoint-state' > "$ROOTS_DIR/$source_name/etc/state.txt"
printf '%s\n' 'source-host-key' > "$ROOTS_DIR/$source_name/etc/ssh/ssh_host_ed25519_key"
printf '%s\n' '{"name":"source","image":"ubuntu:22.04","user":"root","mount_host":1,"mount_home":1,"mounts":[["workspace","/host/workspace","rw"]],"ports":[8080],"loopback":"127.2.0.9","limit_mem":"256M"}' > "$CONFIGS_DIR/$source_name.json"

# Keep the clone test focused on clone semantics rather than PRoot bootstrap.
ensure_runtime() { mkdir -p "$ROOTS_DIR" "$CONFIGS_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"; }
write_rootfs_niceties() {
    mkdir -p "$ROOTS_DIR/$1/etc"
    printf '%s\n' "$1" > "$ROOTS_DIR/$1/etc/jailname"
}
verify_jail() { [ -f "$ROOTS_DIR/$1/etc/state.txt" ]; }
record_event() { :; }
trigger_event_hooks() { :; }

cmd_checkpoint "$source_name" baseline >/dev/null
printf '%s\n' 'live-after-checkpoint' > "$ROOTS_DIR/$source_name/etc/state.txt"
cmd_clone checkpoint "$source_name" baseline checkpoint-copy >/dev/null

[ "$(cat "$ROOTS_DIR/checkpoint-copy/etc/state.txt")" = 'checkpoint-state' ]
[ "$(cat "$ROOTS_DIR/$source_name/etc/state.txt")" = 'live-after-checkpoint' ]
printf '%s\n' 'clone-write' > "$ROOTS_DIR/checkpoint-copy/etc/state.txt"
[ "$(cat "$SNAPSHOTS_DIR/$source_name/checkpoints/baseline/etc/state.txt")" = 'checkpoint-state' ]
[ ! -e "$ROOTS_DIR/checkpoint-copy/etc/ssh/ssh_host_ed25519_key" ]
[ "$(cat "$ROOTS_DIR/checkpoint-copy/etc/jailname")" = 'checkpoint-copy' ]

grep -q '"name": "checkpoint-copy"' "$CONFIGS_DIR/checkpoint-copy.json"
grep -q '"mount_host": 0' "$CONFIGS_DIR/checkpoint-copy.json"
grep -q '"mount_home": 0' "$CONFIGS_DIR/checkpoint-copy.json"
grep -q '"mounts": \[\]' "$CONFIGS_DIR/checkpoint-copy.json"
grep -q '"ports": \[\]' "$CONFIGS_DIR/checkpoint-copy.json"
! grep -q '"loopback"' "$CONFIGS_DIR/checkpoint-copy.json"
grep -q '"clone_source"' "$CONFIGS_DIR/checkpoint-copy.json"
grep -Eq '"loopback"[[:space:]]*:[[:space:]]*"127\.2\.0\.9"' "$CONFIGS_DIR/$source_name.json"

# A snapshot is intentionally taken from a different source state to prove the
# command uses the selected saved representation rather than the live rootfs.
printf '%s\n' 'snapshot-state' > "$ROOTS_DIR/$source_name/etc/state.txt"
cmd_snapshot "$source_name" archive-base >/dev/null
printf '%s\n' 'live-after-snapshot' > "$ROOTS_DIR/$source_name/etc/state.txt"
cmd_clone snapshot "$source_name" archive-base snapshot-copy >/dev/null
[ "$(cat "$ROOTS_DIR/snapshot-copy/etc/state.txt")" = 'snapshot-state' ]
[ "$(cat "$ROOTS_DIR/$source_name/etc/state.txt")" = 'live-after-snapshot' ]
printf '%s\n' 'snapshot-clone-write' > "$ROOTS_DIR/snapshot-copy/etc/state.txt"
# The archive is immutable and must retain the original content.
tar -xOzf "$SNAPSHOTS_DIR/$source_name/archive-base.tar.gz" "$source_name/etc/state.txt" | grep -qx 'snapshot-state'

# A failed post-copy validation must leave neither a rootfs nor a config behind.
if (
    verify_jail() { return 1; }
    cmd_clone checkpoint "$source_name" baseline validation-failure
) >/dev/null 2>&1; then
    printf 'clone unexpectedly succeeded despite failed validation\n' >&2
    exit 1
fi
[ ! -e "$ROOTS_DIR/validation-failure" ]
[ ! -e "$CONFIGS_DIR/validation-failure.json" ]

printf '  ok    checkpoint and snapshot clones are isolated, sanitized, and atomic\n'
