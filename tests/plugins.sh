#!/usr/bin/env bash
# Plugin runtime regression tests. Runs without a rootfs download or PRoot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/jroot"
DEV_HELPER="$ROOT/jroot-dev.py"
WORK="$ROOT/.build/plugin-tests"
HOME_DIR="$WORK/home"
PLUGIN="$WORK/example-plugin"
LIB="$WORK/jroot-lib.sh"

fail() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok    %s\n' "$*"; }

rm -rf "$WORK"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$PLUGIN" "$HOME_DIR/configs" "$HOME_DIR/roots/sample-jail"
# Exercise lazy SDK provisioning rather than pre-seeding the isolated runtime.
export JROOT_SDK_SOURCE="$ROOT/jroot_sdk.py"
printf '%s\n' '{"name":"sample-jail","image":"ubuntu:22.04","user":"root"}' > "$HOME_DIR/configs/sample-jail.json"

cat > "$PLUGIN/plugin.json" <<'JSON'
{
  "api_version": 1,
  "name": "example-plugin",
  "version": "1.0.0",
  "description": "Plugin test fixture.",
  "author": "JRoot test suite",
  "entrypoint": "main.py",
  "hooks": ["on_init", "on_enter", "on_stop", "on_remove", "on_sync", "on_snapshot", "on_limit", "on_monitor"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {"python": ">=3.8", "commands": []}
}
JSON

cat > "$PLUGIN/main.py" <<'PY'
#!/usr/bin/env python3
import sys
import time
from jroot_sdk import JRootContext

context = JRootContext()
event = sys.argv[1].split(":", 1)[1]
state = context.read_plugin_state("events.json", [])
state.append({"event": event, "args": sys.argv[2:]})
context.write_plugin_state(state, "events.json")
context.log.info(f"handled {event}")
if event == "on_monitor":
    time.sleep(10)
PY

python3 "$DEV_HELPER" validate --strict "$PLUGIN" >/dev/null || fail "cross-platform strict validation"
ok "cross-platform strict validation"

# The generated Windows/macOS/Linux fixture runner executes all declared hooks.
TMP_TEMPLATE="$WORK/template"
python3 "$DEV_HELPER" init "$TMP_TEMPLATE" >/dev/null || fail "development template generation"
python3 "$DEV_HELPER" test "$TMP_TEMPLATE" >/dev/null || fail "development template hook test"
ok "development helper fixture test"

JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin install "$PLUGIN" >/dev/null || fail "plugin installation"
if JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin list | grep -qx 'data'; then
    fail "private data directory leaked into plugin list"
fi
if ! JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin list | grep -q '^example-plugin'; then
    fail "installed plugin omitted from list"
fi
ok "manifest installation and clean plugin listing"

# Source the command library once to call the non-networked hook dispatcher.
sed '$d' "$SCRIPT" > "$LIB"
JROOT_HOME="$HOME_DIR" bash -c '
    source "$1"
    for hook in on_init on_enter on_stop on_remove on_sync on_snapshot on_limit; do
        trigger_event_hooks "$hook" sample-jail fixture
    done
' _ "$LIB" || fail "lifecycle hook dispatcher"

STATE="$HOME_DIR/plugins/data/example-plugin/events.json"
[ -s "$HOME_DIR/sdk/jroot_sdk.py" ] || fail "automatic SDK provisioning"
python3 - "$STATE" <<'PY' || fail "lifecycle event state"
import json, sys
expected = {"on_init", "on_enter", "on_stop", "on_remove", "on_sync", "on_snapshot", "on_limit"}
with open(sys.argv[1], encoding="utf-8") as f:
    observed = {entry["event"] for entry in json.load(f)}
raise SystemExit(0 if expected <= observed else 1)
PY
ok "all documented lifecycle hooks dispatch with automatic SDK provisioning"

JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin service start example-plugin on_monitor sample-jail >/dev/null || fail "service startup"
STATUS_OUTPUT="$(JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin service status example-plugin)"
printf '%s\n' "$STATUS_OUTPUT" | grep -q 'on_monitor.*running' || fail "service status reports running"
JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin service stop example-plugin on_monitor >/dev/null || fail "service shutdown"
JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin inspect example-plugin | grep -q 'last_result: stopped (service:on_monitor' || fail "service stop status"
ok "background service lifecycle"

# Checkpoint and revert syntax
mkdir -p "$HOME_DIR/snapshots/sample-jail/checkpoints/pre-patch"
: > "$HOME_DIR/snapshots/sample-jail/checkpoints/pre-patch.json"
JROOT_HOME="$HOME_DIR" bash "$SCRIPT" checkpoints sample-jail | grep -q "pre-patch" || fail "checkpoint not listed"
JROOT_HOME="$HOME_DIR" bash "$SCRIPT" help revert | grep -q "snapshot" || fail "help syntax not updated"
ok "checkpoint and revert syntax verification"

BAD="$WORK/bad-plugin"
mkdir -p "$BAD"
printf '%s\n' '{"name":"bad","version":"1.0.0"}' > "$BAD/plugin.json"
if JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin install "$BAD" >/dev/null 2>&1; then
    fail "invalid manifest was accepted"
fi
ok "invalid plugin manifests rejected"

JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin verify example-plugin >/dev/null || fail "installed plugin verification"
JROOT_HOME="$HOME_DIR" bash "$SCRIPT" plugin remove example-plugin >/dev/null || fail "plugin removal"
ok "verification and removal"

printf 'all plugin checks passed\n'
