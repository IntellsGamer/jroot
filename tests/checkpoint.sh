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
mkdir -p "$ROOTS_DIR/$name/etc" "$ROOTS_DIR/$name/var/cache" "$ROOTS_DIR/$name/usr/local/bin" "$CONFIGS_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR"
printf '{"name":"demo","image":"ubuntu:22.04","user":"root","limit_mem":"256M"}\n' > "$CONFIGS_DIR/$name.json"
printf 'original\n' > "$ROOTS_DIR/$name/etc/state.txt"
printf 'obsolete\n' > "$ROOTS_DIR/$name/var/cache/old-index"
record_event() { :; }
trigger_event_hooks() { :; }

cmd_checkpoint "$name" baseline >/dev/null
printf 'first-change\n' > "$ROOTS_DIR/$name/etc/state.txt"
rm -f "$ROOTS_DIR/$name/var/cache/old-index"
printf 'new tool\n' > "$ROOTS_DIR/$name/usr/local/bin/new-tool"
set_config_field "$CONFIGS_DIR/$name.json" limit_mem "512M"
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]

# The second checkpoint may link unchanged files to the first checkpoint, but a
# changed file must be private to the newer checkpoint.
cmd_checkpoint "$name" changed >/dev/null
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/changed/etc/state.txt")" = "first-change" ]
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]
diff_output="$(cmd_checkpoint diff "$name" baseline changed)"
printf '%s\n' "$diff_output" | grep -qx $'M\t/etc/state.txt'
printf '%s\n' "$diff_output" | grep -qx $'D\t/var/cache/old-index'
printf '%s\n' "$diff_output" | grep -qx $'A\t/usr/local/bin/new-tool'
printf '%s\n' "$diff_output" | grep -qx $'C\t@config.limit_mem'
printf '%s\n' "$diff_output" | grep -q '^Summary: 1 added, 1 removed, 1 modified, 0 type changed, 1 config changed$'
printf 'second-change\n' > "$ROOTS_DIR/$name/etc/state.txt"
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/changed/etc/state.txt")" = "first-change" ]
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]

# A restored jail must also be detached from the checkpoint before future writes.
restore_checkpoint_now "$name" baseline
[ "$(cat "$ROOTS_DIR/$name/etc/state.txt")" = "original" ]
printf 'after-restore\n' > "$ROOTS_DIR/$name/etc/state.txt"
[ "$(cat "$SNAPSHOTS_DIR/$name/checkpoints/baseline/etc/state.txt")" = "original" ]

printf '  ok    checkpoint contents remain isolated from live-jail writes and checkpoint diff output\n'
