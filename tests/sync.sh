#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
export JROOT_HOME="$root/.build/synchome"
work="$root/.build/syncwork"
fails=0

J() { bash "$root/jroot" "$@"; }

setup() {
    rm -rf "$JROOT_HOME" "$work"
    mkdir -p "$JROOT_HOME/configs" "$JROOT_HOME/roots/dev/root/project" "$work/hostproject"
    printf '%s\n' '{"name":"dev","image":"ubuntu:22.04","user":"root","ports":[],"mounts":[]}' \
        > "$JROOT_HOME/configs/dev.json"
    printf 'hello world\n' > "$work/hostproject/test.txt"
}

echo "Testing jroot sync"
setup

# Test host -> jail sync
J sync "$work/hostproject" dev:/root/project
if [ -f "$JROOT_HOME/roots/dev/root/project/test.txt" ]; then
    printf '  ok    host -> jail sync\n'
else
    printf '  FAIL  host -> jail sync failed (file not found in jail)\n'
    fails=$((fails + 1))
fi

# Modify file in jail and sync jail -> host
mkdir -p "$work/hostproject-back"
printf 'updated in jail\n' > "$JROOT_HOME/roots/dev/root/project/test.txt"
J sync dev:/root/project "$work/hostproject-back"
if grep -q 'updated in jail' "$work/hostproject-back/test.txt"; then
    printf '  ok    jail -> host sync\n'
else
    printf '  FAIL  jail -> host sync failed\n'
    fails=$((fails + 1))
fi

rm -rf "$JROOT_HOME" "$work"
if [ "$fails" -eq 0 ]; then
    printf 'all sync checks passed\n'
else
    printf '%s sync check(s) failed\n' "$fails"
    exit 1
fi
