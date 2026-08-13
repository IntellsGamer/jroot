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

# sshd itself stays virtual root and unrestricted; its post-login wrapper is
# where the unroot-only guard is installed before executing the remote command.
JROOT_SSH_UNROOT_RUNTIME=1 run_in_jail --root dev /bin/true
grep -qx -- '-0' "$WORK/args"
[ ! -s "$WORK/strict" ]
grep -qx '0' "$WORK/unroot"
grep -qF "$rootfs"$'\t'"$LANDLOCK_FULL" "$WORK/rules"
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
# families for direct unroot sessions.
grep -q 'DENY_CREDENTIAL_CHANGE' "$ROOT/jroot"
grep -q 'JROOT_UNROOT' "$ROOT/jroot"
grep -q 'JROOT_SSH_UNROOT_RUNTIME=1' "$ROOT/jroot"
printf '  ok    protected unroot direct and SSH policy keeps the system image immutable and preserves explicit root maintenance\n'
BASH
