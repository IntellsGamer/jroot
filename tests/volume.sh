#!/usr/bin/env bash
# Managed volumes are intentionally a thin layer above the existing mount
# config. Exercise their metadata and destructive semantics without creating a
# jail or starting PRoot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-volume-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"
export NONINTERACTIVE=1

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"
record_event() { :; }

name="dev"
mkdir -p "$CONFIGS_DIR" "$ROOTS_DIR/$name"
printf '%s\n' '{"name":"dev","image":"ubuntu:22.04","user":"root","mounts":[]}' > "$CONFIGS_DIR/$name.json"

# Creation owns the directory and attaches it read-write by default.
cmd_volume "$name" create appdata >/dev/null
path="$VOLUMES_DIR/$name/appdata"
[ -d "$path" ]
[ "$(volume_attached_mode "$name" appdata)" = "rw" ]
printf 'payload\n' > "$path/value"

# Detach only removes the config attachment; data stays untouched.
cmd_volume "$name" detach appdata >/dev/null
[ -d "$path" ]
[ "$(cat "$path/value")" = "payload" ]
! volume_attached_mode "$name" appdata >/dev/null 2>&1

# Attach and mode changes are delegated to the ordinary mount representation.
cmd_volume "$name" attach appdata ro >/dev/null
[ "$(volume_attached_mode "$name" appdata)" = "ro" ]
cmd_volume "$name" set appdata rw >/dev/null
[ "$(volume_attached_mode "$name" appdata)" = "rw" ]

info="$(cmd_volume "$name" info appdata)"
[[ "$info" == *"Size:"* ]]
[[ "$info" == *"Attached:   yes (rw at /mnt/appdata)"* ]]
list="$(cmd_volume "$name" list)"
[[ "$list" == *"appdata"* ]]

# rm is deliberately the only operation that destroys the owned data directory.
cmd_volume "$name" rm appdata >/dev/null
[ ! -e "$path" ]
! volume_attached_mode "$name" appdata >/dev/null 2>&1

printf '  ok    managed volume lifecycle delegates attachment to mount config\n'
