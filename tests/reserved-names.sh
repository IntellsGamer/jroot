#!/usr/bin/env bash
# tests/reserved-names.sh - command words must never become ambiguous jail names.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$root/.build/reserved-name-work"
lib="$work/jroot-lib.sh"
rm -rf "$work"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"
sed '$d' "$root/jroot" > "$lib"

# Keep this derived from the dispatcher rather than a hand-maintained list: a
# future top-level command automatically becomes a reservation requirement.
mapfile -t names < <(
    sed -n '/^jroot_cmd()/,/^}$/p' "$root/jroot" \
        | sed -n 's/^[[:space:]]*\([^)]*\))[[:space:]]*shift;[[:space:]]*cmd_[^ ]*.*$/\1/p' \
        | tr '|' '\n' \
        | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/\\//g' \
        | grep -E '^[a-z][a-z-]*$' \
        | sort -u
)
names+=(shell data logs status registry)

JROOT_HOME="$work/home" bash -s "$lib" "${names[@]}" <<'BASH'
set -euo pipefail
source "$1"
shift

mkdir -p "$JROOT_HOME/configs"
for name in "$@"; do
    if ! is_reserved_command "$name"; then
        printf 'dispatcher or internal reserved word is absent from is_reserved_command: %s\n' "$name" >&2
        exit 1
    fi
    if jail_name_valid "$name"; then
        printf 'reserved word was accepted as a jail name: %s\n' "$name" >&2
        exit 1
    fi
    printf '{"name":"%s"}\n' "$name" > "$JROOT_HOME/configs/$name.json"
done

# Even a manually created legacy config must not be offered as a jail candidate.
eval "$(completion_bash)"
if leaked="$(_jroot_jails)"; [ -n "$leaked" ]; then
    printf 'reserved names leaked through Bash jail completion: %s\n' "$leaked" >&2
    exit 1
fi
BASH

printf 'all dispatcher and internal reserved words are rejected as jail names\n'
