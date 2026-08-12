#!/usr/bin/env bash
# Verify that every public dispatcher token is advertised by Bash, Zsh, and Fish.
# Argument-level behavior belongs in completion.sh; this prevents future commands
# from being added to dispatch without being discoverable at the command prompt.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/jroot"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

sed -n '/^jroot_cmd()/,/^}$/p' "$script" \
    | sed -n 's/^[[:space:]]*\([^)]*\))[[:space:]]*shift;.*/\1/p' \
    | tr '|' '\n' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/\\//g' \
    | grep -E '^[a-z][a-z-]*$' \
    | sort -u > "$tmp/dispatch"

# shell is handled by main() before the normal dispatcher, but it is public.
printf '%s\n' shell >> "$tmp/dispatch"
sort -u -o "$tmp/dispatch" "$tmp/dispatch"

bash "$script" completion bash > "$tmp/bash"
bash "$script" completion zsh > "$tmp/zsh"
bash "$script" completion fish > "$tmp/fish"

fails=0
while IFS= read -r cmd; do
    for shell in bash zsh fish; do
        if ! grep -Fq "$cmd" "$tmp/$shell"; then
            printf 'missing %s in %s completion\n' "$cmd" "$shell" >&2
            fails=1
        fi
    done
done < "$tmp/dispatch"

[ "$fails" -eq 0 ]
printf 'completion dispatch coverage passed\n'
