# JRoot Plugin API Reference & Guide

Welcome to the official documentation for the JRoot plugin system. This guide covers everything from foundational concepts to advanced API reference tables and complete, production-ready examples.

---

## 1. Introduction

The JRoot plugin system is designed to allow developers to extend rootless userspace containers without modifying core runtime scripts. Plugins are self-contained directory bundles consisting of:
*   A declarative manifest file (`plugin.json`).
*   An executable entrypoint script (written in Python or Bash).
*   An isolated private state directory managed automatically by the JRoot SDK.

When core JRoot operations occur—such as jail initialization, limit configuration, or file synchronization—the runtime dispatches event hooks to all installed plugins registered for that event.

---

## 2. Getting Started

Creating your first JRoot plugin requires two files: `plugin.json` and `main.py`. 

### Step 1: Create the Plugin Directory
Create a new directory for your extension under a workspace folder:
```bash
mkdir -p my-plugin
cd my-plugin
```

### Step 2: Write the Manifest (`plugin.json`)
The manifest tells JRoot what your plugin is called, what version it runs, and which lifecycle hooks it wants to listen to.
```json
{
  "api_version": 1,
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "A simple getting started plugin for JRoot.",
  "author": "Developer",
  "entrypoint": "main.py",
  "hooks": ["on_init"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": ["python3"]
  }
}
```

### Step 3: Write the Entrypoint (`main.py`)
Your entrypoint script receives events via `sys.argv`. Argument one always indicates the action or hook being triggered.
```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext

def main():
    context = JRootContext()
    if len(sys.argv) > 1 and sys.argv[1] == "hook:on_init":
        jail_name = sys.argv[2]
        image_name = sys.argv[3]
        context.log.info(f"Hello from my-plugin! Jail created: {jail_name} using {image_name}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

### Step 4: Install and Test
Install your plugin into JRoot using the CLI:
```bash
jroot plugin install ./my-plugin
```
Verify it appears in your installed list:
```bash
jroot plugin list
```

---

## 3. Manifest API Reference (`plugin.json`)

The table below details every configuration key available inside `plugin.json`.

| Key | Type | Required | Description |
|---|---|---|---|
| `api_version` | Integer | Yes | Must match the runtime API version (currently `1`). |
| `name` | String | Yes | Lowercase identifier (1–64 characters). Must match `[a-z0-9._-]+`. Cannot collide with reserved JRoot commands. |
| `version` | String | Yes | Semantic Versioning string (e.g., `1.0.0`). |
| `description` | String | Yes | Brief summary of the plugin's functionality. |
| `author` | String | Yes | Maintainer name or team. |
| `entrypoint` | String | Yes | Executable file name relative to the plugin root (e.g., `main.py` or `run.sh`). |
| `hooks` | Array | Yes | List of lifecycle hooks this plugin implements. Unlisted hooks are ignored by the runtime. |
| `permissions` | Array | Yes | Required capability flags (`jails.read`, `state.read`, `state.write`). |
| `requires` | Object | Yes | Minimum Python version string and required host command binaries. |

---

## 4. SDK API Reference (`jroot_sdk.py`)

The JRoot SDK provides a typed helper library for interacting with the host environment.

### `Logger` Class
Instantiated automatically as `context.log`. Provides timestamped logging routed to `~/.jroot/plugins/logs/<plugin-name>.log`.

| Method | Parameters | Description |
|---|---|---|
| `info(msg)` | `msg: str` | Writes an `INFO` log entry. |
| `warn(msg)` | `msg: str` | Writes a `WARN` log entry. |
| `error(msg)` | `msg: str` | Writes an `ERROR` log entry. |
| `debug(msg)` | `msg: str` | Writes a `DEBUG` log entry. |

### `JRootContext` Class
Instantiated via `context = JRootContext()`. Provides complete control over jail querying, command execution, and state persistence.

| Method | Parameters | Return Type | Description |
|---|---|---|---|
| `list_jails()` | None | `list[dict]` | Returns a list of dictionaries detailing all provisioned jails, including images, active limits, config paths, and rootfs paths. |
| `get_jail(name)` | `name: str` | `dict \| None` | Loads and returns the raw JSON configuration dictionary for a specified jail, or `None` if it does not exist. |
| `run_in_jail(name, cmd)` | `name: str, cmd: str` | `tuple[int, str, str]` | Executes a shell command inside the specified jail via `jroot exec`. Returns `(exit_code, stdout, stderr)`. |
| `get_resource_usage(name)` | `name: str` | `dict \| None` | Inspects live process accounting via `/proc`, returning RSS memory in bytes/MB, CPU seconds, and active process count. |
| `read_plugin_state(file, default)` | `file: str, default: Any` | `Any` | Reads and parses a JSON state file from your private storage directory (`~/.jroot/plugins/data/<name>/`). Returns `default` if missing or corrupted. |
| `write_plugin_state(data, file)` | `data: Any, file: str` | `None` | Atomically writes JSON state using temporary file replacement semantics, preventing partial writes during concurrent executions. |

---

## 5. Events & Lifecycle Hooks Reference

When JRoot triggers an event, it executes your plugin entrypoint with `sys.argv[1]` set to `hook:<event-name>`.

| Hook Name | Trigger Event | Invocation Shape (`sys.argv`) | Description |
|---|---|---|---|
| `on_init` | Jail successfully provisioned | `hook:on_init <jail> <image>` | Triggered immediately after `jroot init` finishes bootstrapping a rootfs. |
| `on_enter` | Shell or command starting | `hook:on_enter <jail> <shell\|command>` | Triggered before `jroot enter` or `jroot exec` launches a process. |
| `on_stop` | Jail terminated | `hook:on_stop <jail> user-request` | Triggered when `jroot kill` terminates a running jail. |
| `on_remove` | Jail deletion confirmed | `hook:on_remove <jail>` | Triggered immediately before rootfs deletion during `jroot rm`. |
| `on_sync` | File synchronization complete | `hook:on_sync <source> <destination>` | Triggered when `jroot sync` successfully finishes copying files. |
| `on_snapshot` | State backup/restore | `hook:on_snapshot <jail> create:<label>` or `restore:<label>` | Triggered when creating or restoring snapshots/checkpoints. |
| `on_limit` | Resource limits updated | `hook:on_limit <jail> mem=<val>,cpu=<val>,nofile=<val>` | Triggered when `jroot limit` modifies governance rules. |
| `on_monitor` | Background daemon service | `hook:on_monitor <arguments...>` | Triggered when running continuous background services via `jroot plugin service start`. |

---

## 6. Runtime Environment Variables

JRoot injects several environment variables into the plugin execution context so SDK helpers resolve filesystem boundaries correctly.

| Variable Name | Default Value | Description |
|---|---|---|
| `JROOT_HOME` | `~/.jroot` | Base state directory for all JRoot data. |
| `JROOT_ROOTS` | `$JROOT_HOME/roots` | Directory containing jail root filesystems. |
| `JROOT_CONFIGS` | `$JROOT_HOME/configs` | Directory containing jail JSON configurations. |
| `JROOT_PLUGIN_DATA` | `$JROOT_HOME/plugins/data/<name>` | Isolated private state directory for the executing plugin. |
| `JROOT_PLUGIN_NAME` | `<name>` | Name of the executing plugin. |
| `JROOT_COMMAND` | `jroot` | Bound launcher command prefix used by SDK subprocess helpers. |

---

## 7. Full Real-World Example: Audit & Slack Notifier

Below is a complete, production-ready plugin (`audit-bridge`) demonstrating manifest declaration, state persistence, hook dispatch branching, resource usage inspection, and SDK logging.

### Directory Structure
```text
audit-bridge/
├── plugin.json
└── main.py
```

### `plugin.json`
```json
{
  "api_version": 1,
  "name": "audit-bridge",
  "version": "1.0.0",
  "description": "Records operational audit logs and tracks resource limit adjustments.",
  "author": "Platform Team",
  "entrypoint": "main.py",
  "hooks": ["on_init", "on_limit", "on_snapshot"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": ["python3"]
  }
}
```

### `main.py`
```python
#!/usr/bin/env python3
"""
Audit Bridge Plugin for JRoot
Demonstrates event handling, persistent state storage, and SDK logging.
"""

import sys
from jroot_sdk import JRootContext

def record_event(context: JRootContext, jail: str, event_type: str, details: dict):
    """Save an event into the plugin's isolated state store atomically."""
    state = context.read_plugin_state("audit_log.json", {"events": []})
    state["events"].append({"jail": jail, "type": event_type, "details": details})
    
    # Keep rolling window of last 200 events
    if len(state["events"]) > 200:
        state["events"] = state["events"][-200:]
        
    context.write_plugin_state(state, "audit_log.json")

def on_init(context: JRootContext, jail: str, image: str):
    context.log.info(f"Audit: New jail provisioned -> {jail} (Image: {image})")
    record_event(context, jail, "init", {"image": image})

def on_limit(context: JRootContext, jail: str, limits: str):
    context.log.warn(f"Audit: Limits adjusted for {jail}: {limits}")
    record_event(context, jail, "limit", {"limits": limits})
    
    # Inspect live resource usage using JRootContext
    usage = context.get_resource_usage(jail)
    if usage:
        context.log.info(f"Live telemetry for {jail}: {usage['mem_mb']} MB RSS, {usage['pids']} active PIDs")

def on_snapshot(context: JRootContext, jail: str, action_label: str):
    context.log.info(f"Audit: Snapshot operation '{action_label}' on jail '{jail}'")
    record_event(context, jail, "snapshot", {"action": action_label})

def print_report(context: JRootContext):
    """CLI report generator when invoked directly: jroot plugin invoke audit-bridge"""
    state = context.read_plugin_state("audit_log.json", {"events": []})
    print(f"=== JRoot Audit Bridge Report ===")
    print(f"Total Logged Events: {len(state['events'])}")
    for entry in state["events"][-10:]:
        print(f"  Jail: {entry['jail']} | Type: {entry['type']} | Details: {entry['details']}")

def main() -> int:
    context = JRootContext()
    if len(sys.argv) < 2:
        print_report(context)
        return 0

    action = sys.argv[1]
    if action.startswith("hook:"):
        hook_name = action.split(":", 1)[1]
        args = sys.argv[2:]
        
        if hook_name == "on_init" and len(args) >= 2:
            on_init(context, args[0], args[1])
        elif hook_name == "on_limit" and len(args) >= 2:
            on_limit(context, args[0], args[1])
        elif hook_name == "on_snapshot" and len(args) >= 2:
            on_snapshot(context, args[0], args[1])
        return 0

    print_report(context)
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

---

## 8. Testing & Development with `jroot-dev.py`

You do not need a full Linux PRoot environment to develop and test your plugins. JRoot includes a cross-platform helper script (`jroot-dev.py`) that runs on Windows, macOS, and Linux.

```bash
# Initialize a mock plugin workspace
python3 jroot-dev.py init my-plugin

# Validate manifest strictness and syntax
python3 jroot-dev.py validate --strict ./my-plugin

# Simulate a hook locally with mock payloads
python3 jroot-dev.py simulate on_limit --path ./my-plugin

# Run the complete fixture test suite
python3 jroot-dev.py test ./my-plugin
```
