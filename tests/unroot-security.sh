#!/usr/bin/env bash
# tests/unroot-security.sh - PRoot identity is virtual while the backing rootfs
# belongs to the host account. Verify that protected unroot sessions construct a
# kernel-enforced policy that makes /etc read-only and blocks identity changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/unroot-security"
LIB="$WORK/jroot-lib.sh"
rm -rf "$WORK"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/configs" "$WORK/home/roots/dev/etc" \
         "$WORK/home/roots/dev/home/jail" "$WORK/home/roots/dev/usr/bin" \
         "$WORK/home/roots/dev/var" "$WORK/home/bin"

cat > "$WORK/home/configs/dev.json" <<'JSON'
{"name":"dev","image":"ubuntu:22.04","user":"unroot","mount_host":0,"mount_home":0,"build_essential":1,"ports":[],"mounts":[]}
JSON
cat > "$WORK/home/roots/dev/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
jail:x:1000:1000:jail:/home/jail:/bin/sh
EOF
cat > "$WORK/home/roots/dev/etc/shadow" <<'EOF'
root:!:1:0:99999:7:::
jail:!:1:0:99999:7:::
EOF
: > "$WORK/home/bin/seccomp-launcher"
chmod 755 "$WORK/home/bin/seccomp-launcher"

# Load the command functions without invoking main.
sed '$d' "$ROOT/jroot" > "$LIB"
JROOT_HOME="$WORK/home" bash -s "$LIB" "$ROOT" "$WORK" <<'BASH'
set -euo pipefail
LIB="$1"
ROOT="$2"
WORK="$3"
source "$LIB"
SECCOMP_LAUNCHER="$WORK/home/bin/seccomp-launcher"
PROOT_BIN=/bin/true
PORT_SHIM="$WORK/home/bin/missing-shim"
REAL_HOME="$WORK/home/host-home"
mkdir -p "$REAL_HOME"

# Keep config parsing real, but intercept only the final launcher execution and
# capture the generated rule set and PRoot arguments.
python3() {
    if [ "$1" = "$SECCOMP_LAUNCHER" ]; then
        printf '%s' "${JROOT_LANDLOCK:-}" > "$WORK/rules"
        printf '%s' "${JROOT_LANDLOCK_STRICT:-}" > "$WORK/strict"
        printf '%s' "${JROOT_UNROOT:-}" > "$WORK/unroot"
        shift
        printf '%s\n' "$@" > "$WORK/args"
        return 0
    fi
    command python3 "$@"
}
unroot_protection_available() { return 0; }

rootfs="$ROOTS_DIR/dev"
run_in_jail dev /bin/true

grep -qx -- '-i' "$WORK/args"
grep -qx '1000:1000' "$WORK/args"
grep -qx '1' "$WORK/strict"
grep -qx '1' "$WORK/unroot"
grep -qF "$rootfs"$'\t'"$LANDLOCK_RX" "$WORK/rules"
grep -qF "$rootfs/home/jail"$'\t'"$LANDLOCK_FULL" "$WORK/rules"
grep -qF "$rootfs"$'\t'"$LANDLOCK_RX" "$WORK/rules"
grep -q '/\.unroot-dev\.' "$WORK/rules"
grep -qE '/\.unroot-dev\..*/tmp:/tmp' "$WORK/args"
for protected in "$rootfs/etc" "$rootfs/usr" "$rootfs/usr/bin" "$rootfs/usr/bin/sudo" "$rootfs/usr/bin/su" "$rootfs/bin" "$rootfs/lib"; do
    if grep -qF "$protected"$'\t'"$LANDLOCK_FULL" "$WORK/rules"; then
        printf 'unroot policy grants write access to protected system path: %s\n' "$protected" >&2
        exit 1
    fi
done

# Explicit maintenance remains virtual root and is intentionally outside the
# auth protection policy.
run_in_jail --root dev /bin/true
grep -qx -- '-0' "$WORK/args"
[ ! -s "$WORK/strict" ]
grep -qx '0' "$WORK/unroot"
grep -qF "$rootfs"$'\t'"$LANDLOCK_FULL" "$WORK/rules"
if grep -qF "$rootfs/etc"$'\t'"$LANDLOCK_RX" "$WORK/rules"; then
    printf 'explicit root maintenance unexpectedly received unroot auth policy\n' >&2
    exit 1
fi

# sshd starts as virtual root only to authenticate and drop privileges. Its
# persistent process tree must still inherit the immutable-system policy before
# any unroot login begins, or account files remain writable after authentication.
JROOT_SSH_UNROOT_RUNTIME=1 run_in_jail --root dev /bin/true
grep -qx -- '-0' "$WORK/args"
[ ! -s "$WORK/strict" ]
grep -qx '0' "$WORK/unroot"
grep -qF "$rootfs"$'\t'"$LANDLOCK_RX" "$WORK/rules"
grep -qF "$rootfs/home/jail"$'\t'"$LANDLOCK_FULL" "$WORK/rules"
! grep -qF "$rootfs"$'\t'"$LANDLOCK_FULL" "$WORK/rules"
# These sensitive files have no more-specific writable Landlock rule, so the
# read/execute rootfs rule above is their kernel-enforced effective policy.
for account_db in /etc/passwd /etc/shadow /etc/group /etc/gshadow; do
    ! grep -qF "$rootfs$account_db"$'\t'"$LANDLOCK_FULL" "$WORK/rules"
done
grep -qx "$SECCOMP_LAUNCHER:/usr/local/lib/jroot-unroot-guard" "$WORK/args"
grep -qE '/\.unroot-dev\..*/tmp:/tmp' "$WORK/args"
write_ssh_session_wrapper dev
wrapper="$rootfs/usr/local/bin/jroot-session"
sh -n "$wrapper"
grep -q "JROOT_UNROOT_GUARD='1'" "$wrapper"
grep -q 'JROOT_UNROOT=1' "$wrapper"
grep -q 'python3 /usr/local/lib/jroot-unroot-guard' "$wrapper"
! grep -q 'JROOT_UNROOT_LANDLOCK=' "$wrapper"
! grep -q 'JROOT_LANDLOCK_STRICT=1' "$wrapper"
grep -q '\$(id -u)' "$wrapper"

# A host that cannot enforce Landlock must not offer a protected unroot session.
if ( unroot_protection_available() { return 1; }; run_in_jail dev /bin/true ) >/dev/null 2>&1; then
    printf 'unroot session ran without Landlock capability\n' >&2
    exit 1
fi

# The generated launcher must reject all uid/gid/capability mutation syscall
# families for direct unroot sessions, including the user-namespace route to
# namespace-local CAP_NET_ADMIN. Ordinary fork/clone behavior must remain.
grep -q 'DENY_CREDENTIAL_CHANGE' "$ROOT/jroot"
grep -q 'CLONE_NEWUSER' "$ROOT/jroot"
grep -q 'AF_ALG' "$ROOT/jroot"
grep -q 'PR_SET_NO_NEW_PRIVS' "$ROOT/jroot"
grep -q 'JROOT_UNROOT' "$ROOT/jroot"
grep -q 'JROOT_SSH_UNROOT_RUNTIME=1' "$ROOT/jroot"
write_seccomp_launcher
command python3 -m py_compile "$SECCOMP_LAUNCHER"
JROOT_UNROOT=1 command python3 "$SECCOMP_LAUNCHER" /bin/sh -c '(exit 0) & wait'
if JROOT_UNROOT=1 command python3 "$SECCOMP_LAUNCHER" /usr/bin/unshare --user /bin/true >/dev/null 2>&1; then
    printf 'protected unroot launcher allowed user namespace creation\n' >&2
    exit 1
fi
if command python3 -c 'import socket; raise SystemExit(0 if hasattr(socket, "AF_ALG") else 1)' >/dev/null 2>&1; then
    cat > "$WORK/af_alg_probe.py" <<'PY'
import errno
import socket
import sys
try:
    socket.socket(socket.AF_ALG, socket.SOCK_SEQPACKET, 0)
except OSError as exc:
    raise SystemExit(0 if exc.errno == errno.EPERM else 1)
raise SystemExit(2)
PY
    JROOT_UNROOT=1 command python3 "$SECCOMP_LAUNCHER" /usr/bin/python3 "$WORK/af_alg_probe.py"
fi
printf '  ok    protected unroot direct and SSH policy keeps the system image immutable and preserves explicit root maintenance\n'
BASH
