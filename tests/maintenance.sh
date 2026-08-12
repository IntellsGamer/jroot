#!/usr/bin/env bash
# Regression coverage for doctor --fix and safe update checkpoints.  No PRoot,
# network, package manager, or real jail is used.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-maintenance-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"
export NONINTERACTIVE=1

sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

ensure_runtime() {
    mkdir -p "$ROOTS_DIR" "$CONFIGS_DIR" "$SNAPSHOTS_DIR" "$BIN_DIR" "$CACHE_DIR" "$HISTORY_DIR" "$JROOT_HOME/pids"
}
build_port_shim() { :; }
kernel_features() { printf 'seccomp=yes landlock=1\n'; }

# Warnings alone do not cause normal doctor to recommend --fix.
doctor_clean="$(cmd_doctor 2>&1)"
[[ "$doctor_clean" != *'jroot doctor --fix'* ]]

# A stale PID is a fault and has a concrete safe repair.
printf '99999999\n' > "$JROOT_HOME/pids/stale.pid"
if doctor_bad="$(cmd_doctor 2>&1)"; then
    echo "doctor accepted a stale PID record" >&2
    exit 1
fi
[[ "$doctor_bad" == *'jroot doctor --fix'* ]]
cmd_doctor --fix >/dev/null
[ ! -e "$JROOT_HOME/pids/stale.pid" ]

# Stubs for a checkpoint-first update pass.
name="update-test"
mkdir -p "$ROOTS_DIR/$name/etc" "$ROOTS_DIR/$name/bin" "$SNAPSHOTS_DIR/$name" "$CONFIGS_DIR"
printf 'ID=ubuntu\nPRETTY_NAME="Update Test"\n' > "$ROOTS_DIR/$name/etc/os-release"
printf '#!/bin/sh\nexit 0\n' > "$ROOTS_DIR/$name/bin/sh"
chmod +x "$ROOTS_DIR/$name/bin/sh"
printf '{"name":"update-test","image":"ubuntu:22.04","user":"root","mount_host":0,"mount_home":0}\n' > "$CONFIGS_DIR/$name.json"

CHECKPOINTS=0
cmd_checkpoint() {
    local jail="$1" label="$2"
    CHECKPOINTS=$((CHECKPOINTS + 1))
    mkdir -p "$SNAPSHOTS_DIR/$jail/checkpoints/$label"
    cp "$CONFIGS_DIR/$jail.json" "$SNAPSHOTS_DIR/$jail/checkpoints/$label.json"
}
config_apt() { :; }
write_sudoers() { :; }
config_apk() { :; }
setup_unroot_user() { :; }
setup_unroot_alpine() { :; }
record_event() { :; }
trigger_event_hooks() { :; }
build_metadata_get() { return 1; }
UPDATE_PACKAGE_RC=0
UPDATE_HEALTH_RC=0
run_in_jail() {
    local args="$*"
    if [[ "$args" == *'test -r /etc/os-release'* ]]; then
        return "$UPDATE_HEALTH_RC"
    fi
    return "$UPDATE_PACKAGE_RC"
}

# Successful update has a checkpoint and health pass.
cmd_update "$name" >/dev/null
[ "$CHECKPOINTS" -eq 1 ]

# A package-manager failure with a healthy rootfs returns non-zero but never
# offers rollback; rollback prompts are reserved for failed rootfs health checks.
UPDATE_PACKAGE_RC=42
UPDATE_HEALTH_RC=0
if update_output="$(cmd_update "$name" 2>&1)"; then
    echo "update accepted a package-manager failure" >&2
    exit 1
fi
[[ "$update_output" == *'health check'* ]]
[[ "$update_output" != *'Restore checkpoint'* ]]

# A failed health check follows the catastrophic path. NONINTERACTIVE prevents
# an unattended test from accepting a rollback prompt.
UPDATE_PACKAGE_RC=0
UPDATE_HEALTH_RC=1
if catastrophic_output="$(cmd_update "$name" 2>&1)"; then
    echo "update accepted a failed post-update health check" >&2
    exit 1
fi
[[ "$catastrophic_output" == *'post-update rootfs health check failed'* ]]
[[ "$catastrophic_output" == *'Non-interactive session: no rollback was attempted'* ]]

printf '  ok    doctor repair advice and checkpoint-protected update flow\n'
