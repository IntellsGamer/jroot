# JRoot Plugin Architecture & Developer Reference

**Scope:** Comprehensive engineering specification for the JRoot event-driven plugin system, Python SDK (`jroot_sdk.py`), lifecycle hook dispatch, background daemon supervision, atomic state persistence, and cross-platform simulation workflows.

---

## 1. Architectural Foundation & Execution Model

The JRoot plugin system provides a robust extension architecture for rootless userspace containers. Designed around a strict security boundary and a zero-dependency host interface, plugins operate as isolated packages consisting of a declarative manifest (`plugin.json`), an executable entrypoint (Python or Bash), and private data storage.

When core JRoot operations occur—such as jail provisioning, resource limit modification, synchronization, or checkpointing—the host runtime dispatches event notifications through its internal hook dispatcher. 

### Core Execution Flow
1. **Manifest Validation:** During installation (`jroot plugin install`), JRoot validates the plugin manifest against semantic versioning rules, API compatibility levels, and reserved command lists.
2. **Runtime Provisioning:** The JRoot runtime automatically ensures that the importable SDK (`jroot_sdk.py`) is present in the plugin's environment and configures `PYTHONPATH` accordingly.
3. **Dispatch:** Hooks are dispatched as child processes with structured arguments (`sys.argv`), where argument one specifies the hook selector (e.g., `hook:on_init`), followed by event-specific payloads.
4. **State Persistence:** Plugins interact with isolated persistent stores via atomic file replacement (`os.replace`), preventing partial writes or file corruption during concurrent operations.

---

## 2. Manifest Specification (`plugin.json`)

The manifest file governs plugin installation, permissions, and hook registration. Every property is strictly validated by both the JRoot CLI installer and the cross-platform development helper (`jroot-dev.py`).

```json
{
  "api_version": 1,
  "name": "compliance-audit",
  "version": "1.4.2",
  "description": "Real-time security auditing, resource telemetry, and immutable snapshot logging for JRoot.",
  "author": "Platform Infrastructure Team",
  "entrypoint": "main.py",
  "hooks": [
    "on_init",
    "on_enter",
    "on_stop",
    "on_remove",
    "on_sync",
    "on_snapshot",
    "on_limit",
    "on_monitor"
  ],
  "permissions": [
    "jails.read",
    "state.read",
    "state.write"
  ],
  "requires": {
    "python": ">=3.8",
    "commands": ["python3"]
  }
}
```

### Complete Field Reference

| Field | Type | Required | Description |
|---|---|---|---|
| `api_version` | Integer | Yes | Must match runtime API version (`1`). |
| `name` | String | Yes | Lowercase identifier (1–64 characters, matching `[a-z0-9._-]+`). Cannot collide with reserved CLI commands. |
| `version` | String | Yes | Semantic Versioning string (e.g., `1.4.2`). |
| `description` | String | Yes | Concise functional summary. |
| `author` | String | Yes | Author or team attribution. |
| `entrypoint` | String | Yes | Executable file path relative to plugin bundle root. |
| `hooks` | Array | Yes | Array of enabled lifecycle hooks. Undeclared hooks are ignored. |
| `permissions` | Array | Yes | Capability authorizations (`jails.read`, `state.read`, `state.write`). |
| `requires` | Object | Yes | Minimum Python runtime version and required host command binaries. |

---

## 3. Python SDK API Reference (`jroot_sdk.py`)

The JRoot Python SDK provides a typed, robust interface for querying jail states, executing commands inside rootfs containers, collecting process telemetry, and maintaining persistent state.

### `Logger` Class
Provides structured, timestamped logging prefixed with the plugin name. Output is automatically captured in the plugin's dedicated log file under `~/.jroot/plugins/logs/<plugin-name>.log`.

*   `info(message: str)` — Log informational message.
*   `warn(message: str)` — Log warning condition.
*   `error(message: str)` — Log operational error.
*   `debug(message: str)` — Log diagnostic debug information.

### `JRootContext` Class
The primary entrypoint for plugin execution contexts. Automatically inspects environment variables to resolve paths and launcher bindings.

```python
from jroot_sdk import JRootContext
context = JRootContext()
```

#### Method Signatures & Descriptions

| Method | Return Type | Description |
|---|---|---|
| `list_jails()` | `list[dict]` | Returns a list of dictionaries describing all provisioned jails, including name, image, user mode, active resource limits, config paths, and rootfs paths. |
| `get_jail(name: str)` | `dict \| None` | Loads and returns the raw configuration dictionary for a specified jail name, or `None` if the jail does not exist. |
| `run_in_jail(jail_name: str, command: str)` | `tuple[int, str, str]` | Executes a shell command inside the specified jail via `jroot exec`. Returns a tuple of `(returncode, stdout, stderr)`. |
| `get_resource_usage(jail_name: str)` | `dict \| None` | Collects live process telemetry (RSS memory bytes/MB, CPU seconds, and active process count) by inspecting tracked launcher PIDs via `/proc`. |
| `read_plugin_state(filename="state.json", default=None)` | `Any` | Safely reads and parses a JSON state file from the plugin's isolated private data directory (`JROOT_PLUGIN_DATA`). Returns `default` if the file does not exist or is malformed. |
| `write_plugin_state(data: Any, filename="state.json")` | `None` | Atomically writes data to the plugin's private storage using write-to-temporary-file-then-rename semantics, preventing partial state corruption. |

---

## 4. Environment Variables Reference

When JRoot invokes a plugin hook or background service, it injects a comprehensive environment configuration so the SDK and script resolve host boundaries correctly.

| Environment Variable | Default Value | Description |
|---|---|---|
| `JROOT_HOME` | `~/.jroot` | Base directory for all JRoot state, roots, configs, and snapshots. |
| `JROOT_ROOTS` | `$JROOT_HOME/roots` | Absolute directory containing jail root filesystems. |
| `JROOT_CONFIGS` | `$JROOT_HOME/configs` | Absolute directory containing jail JSON configuration files. |
| `JROOT_BIN` | `$JROOT_HOME/bin` | Absolute directory containing static binaries (e.g., PRoot). |
| `JROOT_PLUGIN_DATA` | `$JROOT_HOME/plugins/data/<name>` | Isolated persistent storage directory for the specific plugin. |
| `JROOT_PLUGIN_NAME` | `<name>` | Name of the executing plugin. |
| `JROOT_COMMAND` | `jroot` (or active launcher path) | Bound command prefix used by SDK subprocess helpers to invoke JRoot commands correctly without relying on stale `PATH` lookups. |

---

## 5. Full-Featured Plugin Example

Below is a complete, production-ready plugin implementation demonstrating state persistence, resource monitoring, command execution, and hook multiplexing.

```python
#!/usr/bin/env python3
"""
System Telemetry & Resource Watchdog Plugin for JRoot
"""

import sys
from jroot_sdk import JRootContext

def record_metric(context: JRootContext, jail: str, event_type: str, details: dict) -> None:
    state = context.read_plugin_state("telemetry.json", {"events": []})
    state["events"].append({"jail": jail, "event": event_type, "details": details})
    # Maintain rolling window of 500 events
    if len(state["events"]) > 500:
        state["events"] = state["events"][-500:]
    context.write_plugin_state(state, "telemetry.json")

def on_init(context: JRootContext, jail: str, image: str) -> None:
    context.log.info(f"Watchdog: New jail provisioned -> {jail} (Image: {image})")
    record_metric(context, jail, "init", {"image": image})

def on_limit(context: JRootContext, jail: str, limits: str) -> None:
    context.log.warning(f"Watchdog: Limits adjusted for {jail}: {limits}")
    record_metric(context, jail, "limit", {"limits": limits})
    
    # Example SDK usage: Inspect live resource usage after limit change
    usage = context.get_resource_usage(jail)
    if usage:
        context.log.info(f"Watchdog telemetry for {jail}: {usage['mem_mb']} MB RSS, {usage['pids']} active PIDs")

def on_snapshot(context: JRootContext, jail: str, action_label: str) -> None:
    context.log.info(f"Watchdog: State saved/restored for {jail} [{action_label}]")
    record_metric(context, jail, "snapshot", {"action": action_label})

def handle_cli_report(context: JRootContext) -> None:
    state = context.read_plugin_state("telemetry.json", {"events": []})
    print("=== JRoot Watchdog Telemetry Report ===")
    print(f"Total Recorded Events: {len(state['events'])}")
    for item in state["events"][-10:]:
        print(f"  Jail: {item['jail']} | Event: {item['event']} | Details: {item['details']}")

def main() -> int:
    context = JRootContext()
    if len(sys.argv) < 2:
        handle_cli_report(context)
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

    handle_cli_report(context)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

---

## 6. Advanced Design Patterns

### Pattern A: Inter-Plugin Coordination via Shared Jails
While plugins cannot directly access other plugins' private data directories, they can inspect shared jail configurations or read global JRoot history logs (`~/.jroot/history/<jail>.log`) to correlate operational events across separate tooling extensions.

### Pattern B: Non-Blocking Background Daemon Supervision
When running a continuous daemon via `on_monitor`, use non-blocking sleeps and periodic polling intervals. Avoid infinite tight loops that consume CPU resources unnecessarily:
```python
import time

def run_daemon(context: JRootContext, jail_name: str) -> None:
    context.log.info(f"Starting background monitor daemon for {jail_name}")
    while True:
        usage = context.get_resource_usage(jail_name)
        if usage and usage["mem_mb"] > 200.0:
            context.log.error(f"Alert: Jail {jail_name} exceeded memory threshold! ({usage['mem_mb']} MB)")
        time.sleep(15) # Poll every 15 seconds
```

---

## 7. Comprehensive Troubleshooting & Error Reference

| Error Message / Symptom | Underlying Cause | Corrective Action |
|---|---|---|
| `ModuleNotFoundError: No module named 'jroot_sdk'` | The plugin execution environment lacked `PYTHONPATH` configuration. | Ensure JRoot is updated to commit `4c813e5` or later. The runtime automatically provisions `$JROOT_HOME/sdk/jroot_sdk.py` and exports the path before dispatching hooks. |
| `Refusing to install an invalid plugin bundle` | Manifest syntax violation, missing required keys, or `name` contains reserved command keywords. | Run `python3 jroot-dev.py validate --strict <plugin-dir>` to inspect detailed validation diagnostics. |
| Hook triggered but no log output produced | Hook name is omitted from the `hooks` array in `plugin.json`. | Add the hook name to the manifest `hooks` array and reinstall the plugin (`jroot plugin install ./plugin-dir`). |
| `JSONDecodeError` during `read_plugin_state()` | State file was modified externally or truncated during an abnormal termination. | Wrap state loading in try/except blocks or rely on the SDK's built-in fallback argument: `context.read_plugin_state("file.json", default={})`. |

---

## 8. Cross-Platform Local Simulation & Testing

You do not need a Linux PRoot environment to develop and test JRoot plugins. The cross-platform helper script `jroot-dev.py` runs natively on Windows, macOS, and Linux.

### Local Development Commands
```bash
# 1. Initialize a new plugin template
python3 jroot-dev.py init my-plugin

# 2. Validate manifest and entrypoint strictly
python3 jroot-dev.py validate --strict my-plugin

# 3. Simulate specific hook dispatches with mock payloads
python3 jroot-dev.py simulate on_init --path my-plugin
python3 jroot-dev.py simulate on_limit --path my-plugin

# 4. Run the complete fixture test suite
python3 jroot-dev.py test my-plugin
```

---

## 9. Frequently Asked Questions (FAQ)

**Q: Can a plugin modify the jail rootfs during an `on_enter` hook?**  
A: Yes. By using `context.run_in_jail(jail_name, "apt-get update")` inside a hook handler, plugins can automate setup tasks or configuration injections immediately before a user session begins.

**Q: Are plugins executed synchronously or asynchronously?**  
A: Standard lifecycle hooks (`on_init`, `on_limit`, `on_snapshot`, etc.) execute synchronously during the CLI operation flow to ensure state consistency. Background daemons (`on_monitor`) run asynchronously as supervised background processes.

**Q: How do I distribute my plugin to other users?**  
A: Package your plugin directory containing `plugin.json`, `main.py`, and any optional assets into a standard directory or zip archive. Users can install it directly via `jroot plugin install /path/to/plugin`.
