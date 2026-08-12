#!/usr/bin/env bash
# tests/file.sh - argument handling for 'jroot file cp|mv'.
#
# Both sides of a copy can now be jails, which means twice as many places for a
# path to be resolved wrongly. Nothing here starts a jail: the command works on
# the rootfs directories directly, so a throwaway JROOT_HOME with two configs is
# enough to cover it.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
export JROOT_HOME="$root/.build/filehome"
work="$root/.build/filework"
fails=0

J() { bash "$root/jroot" "$@"; }

setup() {
    rm -rf "$JROOT_HOME" "$work"
    mkdir -p "$JROOT_HOME/configs" "$JROOT_HOME/roots/dev/root" \
             "$JROOT_HOME/roots/dev/etc" "$JROOT_HOME/roots/web/tmp" "$work"
    printf '%s\n' '{"name":"dev","image":"ubuntu:22.04","user":"root","ports":[],"mounts":[]}' \
        > "$JROOT_HOME/configs/dev.json"
    printf '%s\n' '{"name":"web","image":"ubuntu:22.04","user":"root","ports":[],"mounts":[]}' \
        > "$JROOT_HOME/configs/web.json"
    printf 'payload\n' > "$work/src.txt"
}

ok() {   # ok <what> <command...>
    local what="$1" out; shift
    if out="$("$@" 2>&1)"; then
        printf '  ok    %s\n' "$what"
    else
        printf '  FAIL  %s\n          %s\n' "$what" "$out"
        fails=$((fails + 1))
    fi
}

no() {   # no <what> <expected message fragment> <command...>
    local what="$1" want="$2" out; shift 2
    if out="$("$@" 2>&1)"; then
        printf '  FAIL  %s (it succeeded)\n          %s\n' "$what" "$out"
        fails=$((fails + 1))
    elif [[ "$out" != *"$want"* ]]; then
        printf '  FAIL  %s (wrong message)\n          wanted: %s\n          got:    %s\n' "$what" "$want" "$out"
        fails=$((fails + 1))
    else
        printf '  ok    %s\n' "$what"
    fi
}

exists() {
    if [ -e "$1" ]; then printf '  ok      landed: %s\n' "${1#"$JROOT_HOME/"}"
    else printf '  FAIL    missing: %s\n' "$1"; fails=$((fails + 1)); fi
}

gone() {
    if [ -e "$1" ]; then printf '  FAIL    should have moved away: %s\n' "$1"; fails=$((fails + 1))
    else printf '  ok      moved away: %s\n' "${1#"$JROOT_HOME/"}"; fi
}

echo "jail:path syntax"
setup
ok   'host -> jail'      J file cp "$work/src.txt" dev:/root/app.txt
exists "$JROOT_HOME/roots/dev/root/app.txt"
ok   'jail -> host'      J file cp dev:/root/app.txt "$work/back.txt"
exists "$work/back.txt"
ok   'jail -> jail'      J file cp dev:/root/app.txt web:/tmp/app.txt
exists "$JROOT_HOME/roots/web/tmp/app.txt"
ok   'jail -> jail (mv)' J file mv dev:/root/app.txt web:/tmp/moved.txt
exists "$JROOT_HOME/roots/web/tmp/moved.txt"
gone   "$JROOT_HOME/roots/dev/root/app.txt"
ok   'missing parents are created' J file cp "$work/src.txt" dev:/opt/deep/app.txt
exists "$JROOT_HOME/roots/dev/opt/deep/app.txt"

echo "older <jail> <src> <dst> form"
setup
ok   'host -> jail'          J file cp dev "$work/src.txt" :/root/legacy.txt
exists "$JROOT_HOME/roots/dev/root/legacy.txt"
ok   'jail -> host'          J file cp dev :/root/legacy.txt "$work/out.txt"
exists "$work/out.txt"
ok   'named jail on one side' J file mv dev :/root/legacy.txt web:/tmp/from-legacy.txt
exists "$JROOT_HOME/roots/web/tmp/from-legacy.txt"

echo "history"
setup
J file cp "$work/src.txt" dev:/root/app.txt >/dev/null 2>&1
if grep -q '	file	' "$JROOT_HOME/history/dev.log" 2>/dev/null; then
    printf '  ok    recorded: %s\n' "$(cut -f2,3 "$JROOT_HOME/history/dev.log" | tail -n1)"
else
    printf '  FAIL  the copy was not recorded in the jail history\n'
    fails=$((fails + 1))
fi

echo "refusals"
setup
no 'neither side is a jail'  'Neither'                 J file cp "$work/src.txt" "$work/other.txt"
no 'unknown jail'            "Jail 'nope' not found"   J file cp nope:/x "$work/y"
no 'bare colon, no context'  'does not say which jail' J file cp :/root/x "$work/y"
no 'a path containing ..'    "may not contain '..'"    J file cp dev:/root/../../etc/passwd "$work/y"
no 'relative jail path'      'must be absolute'        J file cp "$work/src.txt" dev:root/x
no 'source directory absent' 'No such directory'       J file cp dev:/nope/x "$work/y"
no 'too many arguments'      'needs <src> <dst>'       J file cp a b c d
no 'no operation'            'Missing operation'       J file
no 'unknown operation'       'Unknown file op'         J file frobnicate a b

echo "symlinks that leave the rootfs"
setup
outside="$root/.build/outside"
mkdir -p "$outside"
printf 'host-only\n' > "$outside/secret.txt"
if ln -s "$outside" "$JROOT_HOME/roots/dev/lib" 2>/dev/null && [ -L "$JROOT_HOME/roots/dev/lib" ]; then
    # /lib -> somewhere on the host is what Ubuntu's own absolute symlinks look
    # like from out here, and writing "into the jail" through one would land on
    # the host filesystem.
    no 'write through an escaping symlink' 'leaves the rootfs' \
        J file cp "$work/src.txt" dev:/lib/planted.txt
    ln -s "$outside/secret.txt" "$JROOT_HOME/roots/dev/root/leak" 2>/dev/null
    no 'read through an escaping symlink'  'pointing outside' \
        J file cp dev:/root/leak "$work/leak.txt"
else
    printf '  SKIP  this host cannot create symlinks (run these on Linux)\n'
fi

rm -rf "$JROOT_HOME" "$work" "$root/.build/outside"
echo
if [ "$fails" -eq 0 ]; then
    printf 'all file checks passed\n'
else
    printf '%s file check(s) failed\n' "$fails"
    exit 1
fi
