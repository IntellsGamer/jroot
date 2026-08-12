#!/usr/bin/env bash
# Checkpoints must remain immutable after ordinary writes in the live jail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-checkpoint-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

name="demo"
mkdir -p "$ROOTS_DIR/$name/etc" "$CONFIGS_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"
printf '{"name":"demo","image":"ubuntu:22.04","user":"root"}\n' > "$CONFIGS_DIR/$name.json"
printf 'original\n' > "$ROOTS_DIR/$name/etc/state.txt"
record_event() { :; }
trigger_event_hooks() { :; }

cmd_checkpoint "$name" baseline >/dev/null
printf 'first-change\n' > "$ROOTS_DIR/$name/etc/state.txt"
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]

# The second checkpoint may link unchanged files to the first checkpoint, but a
# changed file must be private to the newer checkpoint.
cmd_checkpoint "$name" changed >/dev/null
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/changed/etc/state.txt")" = "first-change" ]
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]
printf 'second-change\n' > "$ROOTS_DIR/$name/etc/state.txt"
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/changed/etc/state.txt")" = "first-change" ]
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]

# A restored jail must also be detached from the checkpoint before future writes.
restore_checkpoint_now "$name" baseline
[ "$(cat "$ROOTS_DIR/$name/etc/state.txt")" = "original" ]
printf 'after-restore\n' > "$ROOTS_DIR/$name/etc/state.txt"
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]

printf '  ok    checkpoint contents remain isolated from live-jail writes\n'
