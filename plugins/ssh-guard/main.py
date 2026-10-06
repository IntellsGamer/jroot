#!/usr/bin/env python3
"""ssh-guard: jail SSH watchdog and brute-force monitor for JRoot.

Lifecycle:
  hook:on_stop <jail> <reason>  - remember intentional stops (no false alarm).
  hook:on_watch [interval]       - service loop: daemon health + offender scan.

Direct commands (jroot ssh-guard ...):
  status                        - daemon health plus current offenders.
  allowlist [add|rm|list] [ip]  - IPs never actioned on.
  threshold [N]                 - failures per interval before action (default 5).
  mode [alert|stop]             - alert only, or stop an attacked daemon.
  help                          - this message.

Only stdlib is used. Hooks stay short; the loop does bounded work per pass
and reads only newly appended log bytes (offset tracked in state).
"""

from __future__ import annotations

import os
import re
import sys
import time

from jroot_sdk import JRootContext

FAIL_RE = re.compile(
    r"Failed (?:password|publickey) for (?:invalid user )?(\S+) from "
    r"(\d{1,3}(?:\.\d{1,3}){3}) port \d+"
)
IP_RE = re.compile(r"^(\d{1,3}(?:\.\d{1,3}){3})$")
DEFAULT_THRESHOLD = 5
DEFAULT_INTERVAL = 60

STATE_FILE = "ssh-guard.json"


def default_state() -> dict:
    return {
        "threshold": DEFAULT_THRESHOLD,
        "mode": "alert",
        "allowlist": [],
        "stopped": {},
        "offsets": {},
        "offenders": {},
    }


def load_state(context: JRootContext) -> dict:
    state = context.read_plugin_state(STATE_FILE, default_state())
    if not isinstance(state, dict):
        return default_state()
    for key, factory in (("threshold", lambda: DEFAULT_THRESHOLD),
                         ("mode", lambda: "alert"),
                         ("allowlist", list),
                         ("stopped", dict),
                         ("offsets", dict),
                         ("offenders", dict)):
        if key not in state or not isinstance(state[key], type(factory())):
            state[key] = factory()
    try:
        state["threshold"] = max(1, int(state["threshold"]))
    except (TypeError, ValueError):
        state["threshold"] = DEFAULT_THRESHOLD
    if state["mode"] not in ("alert", "stop"):
        state["mode"] = "alert"
    return state


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return False
    except OSError:
        return False
    return True


def daemon_status(home: str, jail: str) -> tuple[bool, int]:
    """(running, port) for a jail's sshd, from jroot's own pid/port files."""
    pidfile = os.path.join(home, "pids", "%s.sshd" % jail)
    portfile = os.path.join(home, "pids", "%s.sshport" % jail)
    try:
        with open(pidfile) as handle:
            pid = int(handle.read().strip().split()[0])
    except (OSError, ValueError, IndexError):
        return False, 0
    try:
        with open(portfile) as handle:
            port = int(handle.read().strip().split()[0])
    except (OSError, ValueError, IndexError):
        port = 0
    return pid_alive(pid), port


def scan_log(home: str, jail: str, state: dict) -> dict[str, int]:
    """Count NEW auth failures per IP since the last scan (offset-tracked)."""
    logfile = os.path.join(home, "pids", "%s.sshlog" % jail)
    counts: dict[str, int] = {}
    try:
        st = os.stat(logfile)
    except OSError:
        return counts
    key = "%d:%d" % (st.st_ino, st.st_dev)
    last = state["offsets"].get(jail)
    offset = 0
    if isinstance(last, dict) and last.get("key") == key:
        try:
            offset = max(0, int(last.get("offset", 0)))
        except (TypeError, ValueError):
            offset = 0
    if offset >= st.st_size:
        state["offsets"][jail] = {"key": key, "offset": st.st_size}
        return counts
    try:
        with open(logfile, "rb") as handle:
            handle.seek(offset)
            chunk = handle.read()
            new_offset = handle.tell()
    except OSError:
        return counts
    for line in chunk.decode("utf-8", "replace").splitlines():
        match = FAIL_RE.search(line)
        if match:
            ip = match.group(2)
            counts[ip] = counts.get(ip, 0) + 1
    state["offsets"][jail] = {"key": key, "offset": new_offset}
    return counts


def jail_names(context: JRootContext) -> list[str]:
    return sorted(j["name"] for j in context.list_jails()
                  if isinstance(j, dict) and j.get("name"))


def watch_once(context: JRootContext, state: dict) -> int:
    home = context.home
    allow = set(state["allowlist"])
    threshold = state["threshold"]
    for jail in jail_names(context):
        running, port = daemon_status(home, jail)
        if not running:
            if jail in state["stopped"]:
                continue
            context.log.warn("sshd for '%s' is not running (was not stopped via jroot)" % jail)
            continue
        state["stopped"].pop(jail, None)
        fresh = scan_log(home, jail, state)
        for ip, count in sorted(fresh.items()):
            if ip in allow:
                continue
            total = state["offenders"].get(ip, 0) + count
            state["offenders"][ip] = total
            if count >= threshold:
                context.log.warn(
                    "brute-force? %d auth failures for '%s' from %s "
                    "since last scan (mode=%s)" % (count, jail, ip, state["mode"]))
                if state["mode"] == "stop":
                    context.log.warn("stopping sshd for '%s' (attack from %s)" % (jail, ip))
                    stop_cmd = (os.environ.get("JROOT_COMMAND", "jroot")
                                + " ssh %s stop" % jail)
                    rc = os.system(stop_cmd + " >/dev/null 2>&1")
                    if rc != 0:
                        context.log.error("could not stop sshd for '%s' (rc=%d)"
                                          % (jail, rc))
    context.write_plugin_state(state, STATE_FILE)
    return 0


def handle_stop(context: JRootContext, args: list[str]) -> int:
    if len(args) != 2:
        context.log.error("on_stop expected <jail> <reason>")
        return 2
    state = load_state(context)
    state["stopped"][args[0]] = {"reason": args[1], "at": int(time.time())}
    context.write_plugin_state(state, STATE_FILE)
    context.log.info("recorded intentional stop of '%s'" % args[0])
    return 0


def handle_watch(context: JRootContext, args: list[str]) -> int:
    once = bool(args) and args[0] == "once"
    rest = args[1:] if once else args
    interval = DEFAULT_INTERVAL
    if rest:
        try:
            interval = max(5, int(rest[0]))
        except ValueError:
            context.log.warn("ignoring non-integer interval %r, using %ds"
                             % (rest[0], DEFAULT_INTERVAL))
    state = load_state(context)
    context.log.info("watch loop started (interval %ds)" % interval)
    while True:
        state = load_state(context)
        watch_once(context, state)
        if once:
            return 0
        time.sleep(interval)


def cmd_status(context: JRootContext) -> int:
    state = load_state(context)
    watch_once(context, state)
    state = load_state(context)
    home = context.home
    print("sshd daemons:")
    for jail in jail_names(context):
        running, port = daemon_status(home, jail)
        print("  %-16s %s" % (jail, "up port %d" % port if running else "DOWN"))
    offenders = {ip: n for ip, n in state["offenders"].items()
                 if ip not in set(state["allowlist"]) and n > 0}
    print("offenders (failures seen):")
    if not offenders:
        print("  none")
    else:
        for ip in sorted(offenders, key=offenders.get, reverse=True)[:20]:
            print("  %-16s %d" % (ip, offenders[ip]))
    print("threshold: %d  mode: %s  allowlisted: %d" % (
        state["threshold"], state["mode"], len(state["allowlist"])))
    return 0


def cmd_allowlist(context: JRootContext, args: list[str]) -> int:
    state = load_state(context)
    if not args or args[0] == "list":
        for ip in sorted(state["allowlist"]):
            print(ip)
        return 0
    if len(args) != 2 or args[0] not in ("add", "rm"):
        print("Usage: jroot ssh-guard allowlist [add|rm|list] [ip]",
              file=sys.stderr)
        return 2
    action, ip = args
    if not IP_RE.match(ip):
        print("not an IPv4 address: %s" % ip, file=sys.stderr)
        return 2
    if action == "add":
        if ip not in state["allowlist"]:
            state["allowlist"].append(ip)
    else:
        state["allowlist"] = [x for x in state["allowlist"] if x != ip]
    context.write_plugin_state(state, STATE_FILE)
    print("%sed %s" % (action, ip))
    return 0


def cmd_threshold(context: JRootContext, args: list[str]) -> int:
    state = load_state(context)
    if not args:
        print(state["threshold"])
        return 0
    try:
        value = max(1, int(args[0]))
    except ValueError:
        print("threshold must be a positive integer", file=sys.stderr)
        return 2
    state["threshold"] = value
    context.write_plugin_state(state, STATE_FILE)
    print("threshold: %d" % value)
    return 0


def cmd_mode(context: JRootContext, args: list[str]) -> int:
    state = load_state(context)
    if not args:
        print(state["mode"])
        return 0
    if args[0] not in ("alert", "stop"):
        print("mode must be alert or stop", file=sys.stderr)
        return 2
    state["mode"] = args[0]
    context.write_plugin_state(state, STATE_FILE)
    print("mode: %s" % args[0])
    return 0


def print_help() -> int:
    print("Usage: jroot ssh-guard [status|allowlist|threshold|mode|help]")
    print("  status                 daemon health plus current offenders.")
    print("  allowlist [add|rm|list] [ip]  IPs never actioned on.")
    print("  threshold [N]          failures per scan before action (default 5).")
    print("  mode [alert|stop]      alert only, or stop an attacked daemon.")
    return 0


def main() -> int:
    context = JRootContext()
    argv = sys.argv[1:]
    if not argv:
        return cmd_status(context)
    action, args = argv[0], argv[1:]
    if action.startswith("hook:"):
        hook, payload = action.split(":", 1), args
        if hook[1] == "on_stop":
            return handle_stop(context, payload)
        if hook[1] == "on_watch":
            return handle_watch(context, payload)
        context.log.warn("ignoring unsupported hook: %s" % action)
        return 0
    if action == "status":
        return cmd_status(context)
    if action == "allowlist":
        return cmd_allowlist(context, args)
    if action == "threshold":
        return cmd_threshold(context, args)
    if action == "mode":
        return cmd_mode(context, args)
    if action in ("help", "--help", "-h"):
        return print_help()
    print("unknown ssh-guard command: %s" % action, file=sys.stderr)
    return print_help() or 2


if __name__ == "__main__":
    raise SystemExit(main())
