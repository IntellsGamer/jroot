#!/usr/bin/env bash
# Progress must be based on bytes consumed or copied by real lifecycle commands,
# not timer-based output. This test forces rendering in a non-interactive test
# shell and covers every long-running path requested by the CLI contract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-progress-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"
export JROOT_PROGRESS=force
# Force the private-copy path so checkpoint creation and restoration expose the
# byte counter even on filesystems that support reflinks and rsync link-dest.
export JROOT_FORCE_NO_HARDLINKS=1

name="demo"
mkdir -p "$JROOT_HOME/configs" "$JROOT_HOME/roots/$name/etc" "$JROOT_HOME/roots/$name/home/jail"
printf '{"name":"demo","image":"ubuntu:22.04","user":"root"}\n' > "$JROOT_HOME/configs/$name.json"
dd if=/dev/zero of="$JROOT_HOME/roots/$name/home/jail/progress.bin" bs=1M count=3 status=none
printf 'before\n' > "$JROOT_HOME/roots/$name/etc/state"

checkpoint_output="$(bash "$ROOT/jroot" checkpoint "$name" before 2>&1)"
printf '%s\n' "$checkpoint_output" | grep -F 'Filesystem copy ['
printf '%s\n' "$checkpoint_output" | grep -F '100.0%'

snapshot_output="$(bash "$ROOT/jroot" snapshot "$name" progress-snapshot 2>&1)"
printf '%s\n' "$snapshot_output" | grep -F 'Snapshot archive ['
printf '%s\n' "$snapshot_output" | grep -F '100.0%'

bundle="$TMP/demo.tar.gz"
bundle_output="$(bash "$ROOT/jroot" bundle "$name" "$bundle" 2>&1)"
printf '%s\n' "$bundle_output" | grep -F 'Bundle archive ['
printf '%s\n' "$bundle_output" | grep -F '100.0%'

deploy_output="$(bash "$ROOT/jroot" deploy "$bundle" deployed 2>&1)"
printf '%s\n' "$deploy_output" | grep -F 'Bundle deployment extraction ['
printf '%s\n' "$deploy_output" | grep -F '100.0%'

# The archive fallback is used on Termux shared storage and must show a real
# payload counter too, not silently lose the progress behavior.
export JROOT_FORCE_LINK_SAFE_EXTRACT=1
fallback_output="$(bash "$ROOT/jroot" deploy "$bundle" fallback-deployed 2>&1)"
printf '%s\n' "$fallback_output" | grep -F 'Archive payload ['
printf '%s\n' "$fallback_output" | grep -F '100.0%'
unset JROOT_FORCE_LINK_SAFE_EXTRACT

printf 'changed\n' > "$JROOT_HOME/roots/$name/etc/state"
checkpoint_restore_output="$(printf 'y\n' | bash "$ROOT/jroot" revert checkpoint "$name" before 2>&1)"
printf '%s\n' "$checkpoint_restore_output" | grep -F 'Filesystem copy ['
printf '%s\n' "$checkpoint_restore_output" | grep -F '100.0%'
[ "$(cat "$JROOT_HOME/roots/$name/etc/state")" = "before" ]

printf 'changed-again\n' > "$JROOT_HOME/roots/$name/etc/state"
snapshot_restore_output="$(printf 'y\n' | bash "$ROOT/jroot" revert snapshot "$name" progress-snapshot 2>&1)"
printf '%s\n' "$snapshot_restore_output" | grep -F 'Snapshot restore extraction ['
printf '%s\n' "$snapshot_restore_output" | grep -F '100.0%'
[ "$(cat "$JROOT_HOME/roots/$name/etc/state")" = "before" ]

printf '  ok    byte-based progress reaches completion for checkpoint, snapshot, bundle, deploy, and restore paths\n'
