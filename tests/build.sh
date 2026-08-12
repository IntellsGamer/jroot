#!/usr/bin/env bash
# JRootfile build regression tests.  Uses a temporary fake JROOT_HOME and stubs
# jail creation/launching, so it never downloads an image or creates a real jail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/jroot-build-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export JROOT_HOME="$TMP/home"
export NONINTERACTIVE=1

# Load function definitions without executing main.
sed '$d' "$ROOT/jroot" > "$TMP/jroot-lib.sh"
# shellcheck disable=SC1090
source "$TMP/jroot-lib.sh"

cmd_init() {
    local image="$1" name=""
    shift
    for arg in "$@"; do
        case "$arg" in --name=*) name="${arg#*=}" ;; esac
    done
    [ -n "$name" ] || return 1
    mkdir -p "$ROOTS_DIR/$name/etc" "$ROOTS_DIR/$name/bin"
    printf 'ID=ubuntu\nPRETTY_NAME="Build Test"\n' > "$ROOTS_DIR/$name/etc/os-release"
    : > "$ROOTS_DIR/$name/bin/sh"
    chmod +x "$ROOTS_DIR/$name/bin/sh"
    mkdir -p "$CONFIGS_DIR" "$SNAPSHOTS_DIR" "$HISTORY_DIR" "$JROOT_HOME/pids"
    printf '{"name":"%s","image":"%s","user":"root","mount_host":0,"mount_home":0,"build_essential":0}\n' "$name" "$image" > "$CONFIGS_DIR/$name.json"
}

run_in_jail() {
    local root=0 name
    if [ "${1:-}" = "--root" ]; then root=1; shift; fi
    name="$1"; shift
    printf 'root=%s jail=%s argv=%q\n' "$root" "$name" "$*" >> "$TMP/run.log"
    return 0
}

cmd_port() {
    [ "${2:-}" = "add" ] || return 1
    printf '%s\n' "$3" >> "$TMP/ports.log"
}

setup_unroot_user() { :; }
setup_unroot_alpine() { :; }
trigger_event_hooks() { :; }
record_event() { :; }

ctx="$TMP/context"
mkdir -p "$ctx/src"
printf 'hello from context\n' > "$ctx/src/hello.txt"
printf 'archive content\n' > "$ctx/archive.txt"
tar -cf "$ctx/payload.tar" -C "$ctx" archive.txt
cat > "$ctx/JRootfile" <<'EOF'
ARG GREETING=hello
FROM ubuntu:22.04
LABEL org.example.name=jroot-build org.example.mode=test
ENV APP_HOME=/srv/app GREETING=${GREETING}
WORKDIR /srv/app
COPY src/ ./
ADD payload.tar /opt/payload/
RUN printf '%s\n' "$GREETING" > greeting.txt
EXPOSE 8080/tcp 8443
VOLUME /var/lib/example
SHELL ["/bin/sh", "-c"]
CMD ["/bin/sh", "-c", "echo started"]
ENTRYPOINT ["/usr/local/bin/example"]
HEALTHCHECK test -f /etc/os-release
STOPSIGNAL SIGTERM
EOF

cmd_build --tag build-test --build-arg GREETING=hi "$ctx" >/dev/null

[ -f "$ROOTS_DIR/build-test/srv/app/hello.txt" ]
[ -f "$ROOTS_DIR/build-test/opt/payload/archive.txt" ]
grep -qx '8080' "$TMP/ports.log"
grep -qx '8443' "$TMP/ports.log"
grep -q 'jail=build-test' "$TMP/run.log"
python3 - "$JROOT_HOME/builds/build-test.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
assert m["source_image"] == "ubuntu:22.04"
assert m["cmd"] == '["/bin/sh", "-c", "echo started"]'
assert m["entrypoint"] == '["/usr/local/bin/example"]'
assert m["healthcheck"] == 'test -f /etc/os-release'
assert m["stopsignal"] == "SIGTERM"
assert m["labels"]["org.example.name"] == "jroot-build"
assert m["exposed_ports"] == ["8080", "8443"]
assert m["volumes"] == ["/var/lib/example"]
PY

# COPY may not read outside the declared context.
mkdir -p "$TMP/escape"
printf 'outside\n' > "$TMP/outside.txt"
cat > "$TMP/escape/JRootfile" <<'EOF'
FROM ubuntu:22.04
COPY ../outside.txt /inside.txt
EOF
if ( cmd_build --tag should-fail "$TMP/escape" >/dev/null 2>&1 ); then
    echo "build accepted a COPY source outside its context" >&2
    exit 1
fi

# build must be unavailable as a plugin name in both validator surfaces.
mkdir -p "$TMP/bad-plugin"
printf '{"api_version":1,"name":"build","version":"1.0.0","entrypoint":"main.py","hooks":["on_init"]}\n' > "$TMP/bad-plugin/plugin.json"
printf 'print("x")\n' > "$TMP/bad-plugin/main.py"
if plugin_validate_bundle "$TMP/bad-plugin" >/dev/null 2>&1; then
    echo "plugin runtime accepted reserved build name" >&2
    exit 1
fi
if python3 "$ROOT/jroot-dev.py" validate --strict "$TMP/bad-plugin" >/dev/null 2>&1; then
    echo "development helper accepted reserved build name" >&2
    exit 1
fi

printf '  ok    JRootfile build parsing, context safety, and metadata\n'
