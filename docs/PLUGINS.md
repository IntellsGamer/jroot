# JRoot Plugin Development Guide

JRoot plugins are **host-side extensions** that react to jail lifecycle events, provide custom top-level commands, and keep private persistent state. A packaged plugin is a directory containing a `plugin.json` manifest and a Python or POSIX-shell entry point.

> **Security boundary:** A plugin runs with the same host-user permissions as the user who launches `jroot`. The manifest makes compatibility, dependencies, and requested access explicit, but it is not a sandbox. Review source code and its dependencies before installation.

## Plugin lifecycle

A packaged plugin should follow this layout:

```text
my-plugin/
├── plugin.json
└── main.py
```

The runtime validates a packaged plugin before installation and resolves the entry point from the manifest. Single-file `.py` and `.sh` plugins remain supported for compatibility, but cannot provide manifest validation, declared hooks, or dependency checks.

| Operation | Purpose |
|---|---|
| `jroot plugin init-sdk` | Create a standards-compliant Python plugin template. |
| `jroot plugin install <directory>` | Validate and install a packaged plugin. |
| `jroot plugin list` | List installed plugins without runtime data directories. |
| `jroot plugin inspect <name>` | Display the manifest and latest hook result. |
| `jroot plugin verify <name\|all>` | Revalidate installed manifests and host command dependencies. |
| `jroot plugin logs <name> [--follow]` | Read captured plugin stdout and stderr. |
| `jroot plugin remove <name>` | Stop managed services and uninstall the plugin. |

## Manifest contract

`api_version: 1` defines the current runtime contract. The validator requires a lowercase plugin name, a Semantic Versioning version, a safe relative entry point, and an explicit list of lifecycle hooks.

```json
{
  "api_version": 1,
  "name": "memory-audit",
  "version": "1.0.0",
  "description": "Records resource observations after jail activity.",
  "author": "Example Developer",
  "entrypoint": "main.py",
  "hooks": ["on_init", "on_limit"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": []
  }
}
```

| Field | Required | Contract |
|---|---:|---|
| `api_version` | Yes | Must be the integer `1`. |
| `name` | Yes | A lowercase identifier, up to 64 characters; core `jroot` command names and runtime directory names are reserved. |
| `version` | Yes | Semantic Versioning, such as `1.0.0`. |
| `entrypoint` | Yes | Relative `.py` or `.sh` path within the plugin directory. Absolute paths and parent-directory traversal are rejected. |
| `hooks` | Yes | Array of unique `on_*` event names that the plugin subscribes to. |
| `permissions` | No | Human-readable declaration of the access the plugin expects. It is disclosure metadata, not a sandbox. |
| `requires.commands` | No | Host commands that must be available when the plugin runs. Installation and `verify` reject unresolved commands. |
| `requires.python` | No | Enforced minimum host Python version in the form `>=MAJOR.MINOR`, such as `>=3.8`. |

The `name` becomes a custom top-level command. For example, installing a plugin named `memory-audit` allows `jroot memory-audit ...`. Names that would shadow built-in commands are rejected.

## Lifecycle hooks

JRoot invokes only the events declared in a packaged plugin’s `hooks` array. Each handler receives `hook:<event>` as its first command-line argument followed by the payload below. Hook failures are recorded in the plugin status file and log, while the completed core JRoot operation remains successful.

| Hook | Fired after | Payload after `hook:<event>` |
|---|---|---|
| `on_init` | A jail is successfully provisioned. | `<jail> <image>` |
| `on_enter` | A shell or command is about to start in a jail. | `<jail> <shell\|command>` |
| `on_stop` | `jroot kill` terminates a tracked jail process. | `<jail> user-request` |
| `on_remove` | Deletion is confirmed, immediately before the root filesystem is removed. | `<jail>` |
| `on_sync` | A `jroot sync` transfer completes. | `<source> <destination>` |
| `on_snapshot` | A snapshot is created or restored. | `<jail> create:<label>` or `<jail> restore:<label>` |
| `on_limit` | Resource settings are saved. | `<jail> mem=<value>,cpu=<value>,nofile=<value>` |
| Custom `on_*` | Only when explicitly started as a service. | Arguments supplied to `jroot plugin service start`. |

## Runtime environment and state

The plugin process receives the following variables. Paths are host paths; plugins should treat them as implementation details and use the SDK where possible.

| Variable | Meaning |
|---|---|
| `JROOT_PLUGIN_API` | Plugin contract version currently exposed by JRoot. |
| `JROOT_PLUGIN_NAME` | Installed plugin name. |
| `JROOT_PLUGIN_EVENT` | The event currently being handled. |
| `JROOT_PLUGIN_DATA` | Private persistent directory for that plugin. |
| `JROOT_PLUGIN_LOG` | Captured output log for that plugin. |
| `JROOT_HOME`, `JROOT_ROOTS`, `JROOT_CONFIGS`, `JROOT_BIN` | JRoot host storage locations. |

Output written to standard output or standard error is appended to `$JROOT_HOME/plugins/logs/<plugin>.log`. The latest event result is stored in `$JROOT_HOME/plugins/status/<plugin>.json` and displayed by `jroot plugin inspect <plugin>`.

## Python SDK

Installed JRoot copies the importable SDK to `$JROOT_HOME/sdk/jroot_sdk.py`; JRoot adds that directory to `PYTHONPATH` for Python plugins. Use the underscore module name:

```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext


def main() -> int:
    context = JRootContext()
    event = sys.argv[1] if len(sys.argv) > 1 else ""

    if event == "hook:on_limit":
        jail, limits = sys.argv[2:4]
        usage = context.get_resource_usage(jail)
        context.log.info(f"saved limits for {jail}: {limits}; current usage={usage}")

    state = context.read_plugin_state("state.json", {"runs": 0})
    state["runs"] += 1
    context.write_plugin_state(state, "state.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

`JRootContext` provides jail configuration inspection, plugin-scoped JSON state, captured logging, `run_in_jail()`, and `get_resource_usage()`. Resource observations report the tracked launcher processes available to a rootless PRoot deployment; they are not cgroup accounting or a kernel-enforced total.

## Background services

Use a service only for a genuinely long-running job such as a local monitor, queued exporter, or periodic reconciliation loop. The service hook must be declared in the manifest.

```bash
# Start a managed background process.
jroot plugin service start memory-audit on_monitor my-jail

# Inspect its recorded PID state.
jroot plugin service status memory-audit

# Stop one service hook, or omit the hook to stop every service for the plugin.
jroot plugin service stop memory-audit on_monitor
jroot plugin service stop memory-audit
```

JRoot prevents a duplicate running service for the same plugin and hook, stores its PID under `$JROOT_HOME/pids`, captures output in the regular plugin log, and stops services before removing a plugin.

## Development workflow

Developers can write and test plugins on Linux, macOS, or Windows without running JRoot itself. The `jroot-dev.py` helper creates a temporary mock runtime with a sample jail and isolated plugin state.

```bash
# From a checkout on any supported host:
python jroot-dev.py init memory-audit
python jroot-dev.py validate --strict memory-audit
python jroot-dev.py simulate on_init --path memory-audit
python jroot-dev.py test memory-audit

# On the Linux host that runs JRoot:
jroot plugin install memory-audit
jroot plugin verify memory-audit
```

`simulate` runs one declared event with a documented fixture or supplied arguments. `test` runs every declared hook against the mock runtime and fails on non-zero handler exits. The development helper validates plugin structure and Python syntax, but it cannot safely emulate Linux-only system behavior or sandbox code; final verification still belongs on the intended Linux host.

For Windows-specific setup and examples, see [Windows Plugin Development](WINDOWS_DEV.md).
