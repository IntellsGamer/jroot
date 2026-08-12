#!/usr/bin/env bash
# jroot logs must remain a direct alias of jroot history.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-logs-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"
mkdir -p "$JROOT_HOME/configs" "$JROOT_HOME/history"
printf '{"name":"dev","image":"ubuntu:22.04"}\n' > "$JROOT_HOME/configs/dev.json"
printf '1700000000\tinit\tubuntu:22.04\n1700000010\tfile\tcopied app.py\n' > "$JROOT_HOME/history/dev.log"

bash "$ROOT/jroot" history dev > "$TMP/history.txt"
bash "$ROOT/jroot" logs dev > "$TMP/logs.txt"
diff -u "$TMP/history.txt" "$TMP/logs.txt"

bash "$ROOT/jroot" history dev --json > "$TMP/history.json"
bash "$ROOT/jroot" logs dev --json > "$TMP/logs.json"
diff -u "$TMP/history.json" "$TMP/logs.json"

printf '  ok    logs is an exact history alias\n'
