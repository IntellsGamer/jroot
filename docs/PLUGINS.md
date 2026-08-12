# JRoot Plugin Architecture & Development Guide

**Author:** Manus AI  
**Scope:** Production-grade plugin development, event-driven lifecycle hooks, state persistence, background process supervision, and advanced troubleshooting for the `jroot` rootless userspace platform.

---

## 1. Architectural Overview

The JRoot plugin system is designed around a strict security boundary and a zero-dependency host interface. Plugins operate as isolated host-side packages containing a declarative manifest (`plugin.json`), an entrypoint script (Python or Bash), and an optional assets directory. 

When lifecycle events occur inside core JRoot operations (such as jail initialization, limit changes, or snapshot creation), JRoot dispatches events via its internal hook dispatcher. The dispatcher provisions or refreshes the lightweight JRoot SDK (`jroot_sdk.py`), ensures correct Python path resolution, and invokes the plugin with a structured argument vector.

### 🛡️ Security & Isolation Principles
*   **Reserved Subcommand Protection:** Plugins are strictly prohibited from overriding core JRoot subcommands (such as `init`, `enter`, `exec`, `sync`, `checkpoint`, or `revert`). The plugin development validator (`jroot-dev.py`) and installer enforce these reserved identifiers at parse time [1].
*   **Scoped State Directories:** Every installed plugin receives an isolated private storage path at `~/.jroot/plugins/data/<plugin-name>/`. Plugins cannot read or write to other plugins' storage directories or manipulate host files outside their designated scope.
*   **Explicit Permissions:** Plugins must declare required capabilities in their manifest permissions array (e.g., `jails.read`, `state.read`, `state.write`). Undeclared operations are rejected by the SDK runtime.

---

## 2. Plugin Manifest Specification (`plugin.json`)

The manifest file defines the plugin metadata, API version compatibility, declared hooks, permissions, and external runtime requirements. Below is a comprehensive, production-grade `plugin.json` example.

```json
{
  "api_version": 1,
  "name": "enterprise-audit",
  "version": "1.2.0",
  "description": "Production telemetry, compliance logging, and automated snapshot auditing for JRoot.",
  "author": "Security Engineering Team",
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

### Manifest Fields Reference

| Field | Type | Description |
|---|---|---|
| `api_version` | Integer | Must match the runtime API version (currently `1`). |
| `name` | String | Lowercase identifier (1–64 characters, matching `[a-z0-9._-]+`). Cannot be a reserved command. |
| `version` | String | Semantic Versioning string (e.g., `1.2.0`). |
| `description` | String | Concise summary of the plugin's purpose. |
| `author` | String | Maintainer name or organization. |
| `entrypoint` | String | Executable file name relative to the plugin bundle root. |
| `hooks` | Array | List of supported lifecycle hooks. Only declared hooks will be dispatched. |
| `permissions` | Array | Authorized capabilities (`jails.read`, `state.read`, `state.write`). |
| `requires` | Object | Minimum runtime dependencies (`python` version string and required host `commands`). |

---

## 3. Complete Production-Grade Plugin Example

The following complete Python implementation demonstrates durable state management, structured logging, custom CLI subcommands, and hook routing.

```python
#!/usr/bin/env python3
"""
Enterprise Audit Plugin for JRoot
Provides compliance telemetry, event counting, and custom CLI reporting.
"""

import sys
from jroot_sdk import JRootContext

def update_audit_log(context: JRootContext, category: str, details: dict) -> int:
    """
    Safely record an event in the plugin's private persistent state store.
    Utilizes atomic writes provided by the JRootContext SDK.
    """
    state = context.read_plugin_state("audit_db.json", {"total_events": 0, "logs": []})
    state["total_events"] += 1
    state["logs"].append({"category": category, "details": details})
    
    # Keep only the last 1000 events to prevent unbounded growth
    if len(state["logs"]) > 1000:
        state["logs"] = state["logs"][-1000:]
        
    context.write_plugin_state(state, "audit_db.json")
    return state["total_events"]

def on_init(context: JRootContext, jail: str, image: str) -> None:
    total = update_audit_log(context, "init", {"jail": jail, "image": image})
    context.log.info(f"Compliance Audit: Initialized jail '{jail}' from '{image}'. Total events: {total}")

def on_limit(context: JRootContext, jail: str, limits: str) -> None:
    update_audit_log(context, "limit", {"jail": jail, "limits": limits})
    context.log.warning(f"Compliance Audit: Resource limits modified for jail '{jail}': {limits}")

def on_snapshot(context: JRootContext, jail: str, action_label: str) -> None:
    update_audit_log(context, "snapshot", {"jail": jail, "action": action_label})
    context.log.info(f"Compliance Audit: Snapshot operation '{action_label}' on jail '{jail}'.")

def handle_custom_cli(context: JRootContext) -> None:
    """
    Executed when a user runs: jroot enterprise-audit report
    """
    state = context.read_plugin_state("audit_db.json", {"total_events": 0, "logs": []})
    print(f"=== JRoot Enterprise Audit Report ===")
    print(f"Total Recorded Events: {state['total_events']}")
    print(f"Recent Activity (last 5 entries):")
    for entry in state["logs"][-5:]:
        print(f"  [{entry['category'].upper()}] {entry['details']}")

def main() -> int:
    context = JRootContext()
    if len(sys.argv) < 2:
        handle_custom_cli(context)
        return 0

    action = sys.argv[1]

    # Hook dispatch route
    if action.startswith("hook:"):
        hook_name = action.split(":", 1)[1]
        args = sys.argv[2:]
        
        if hook_name == "on_init" and len(args) >= 2:
            on_init(context, args[0], args[1])
        elif hook_name == "on_limit" and len(args) >= 2:
            on_limit(context, args[0], args[1])
        elif hook_name == "on_snapshot" and len(args) >= 2:
            on_snapshot(context, args[0], args[1])
        else:
            context.log.debug(f"Unhandled hook dispatched: {hook_name}")
        return 0

    # Direct CLI command route
    handle_custom_cli(context)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

---

## 4. Lifecycle Hooks & Event Payloads Reference

JRoot dispatches stable API version 1 hook payloads. When writing handlers, always inspect `sys.argv` to parse arguments corresponding to the event type [2].

| Hook Name | Trigger Condition | Invocation Shape (`sys.argv`) | Recommended Application |
|---|---|---|---|
| `on_init` | Jail successfully provisioned. | `hook:on_init <jail> <image>` | Register jail in external inventory databases. |
| `on_enter` | Shell or command about to start. | `hook:on_enter <jail> <shell\|command>` | Real-time session auditing and access logging. |
| `on_stop` | `jroot kill` terminates a jail. | `hook:on_stop <jail> user-request` | Release external network leases and clean up mounts. |
| `on_remove` | Jail deletion confirmed. | `hook:on_remove <jail>` | Purge remote telemetry records; rootfs is deleted next. |
| `on_sync` | `jroot sync` successfully completes. | `hook:on_sync <source> <destination>` | Trigger automated CI builds or workspace indexing. |
| `on_snapshot` | Snapshot or checkpoint created/restored. | `hook:on_snapshot <jail> create:<label>`, `restore:<label>`, `checkpoint-create:<label>`, or `restore-checkpoint:<label>` | Log compliance restore points. |
| `on_limit` | Resource limits saved. | `hook:on_limit <jail> mem=<val>,cpu=<val>,nofile=<val>` | Enforce resource quotas and alert operators. |
| Custom `on_*` | Long-running background daemon. | `hook:on_monitor <arguments...>` | Continuous telemetry reporting or health monitoring. |

---

## 5. Background Services & Daemons

Plugins can run continuous background services managed by JRoot's process supervisor. Declare a hook (such as `on_monitor`) and control it using the plugin service command suite.

### Service Commands
```bash
# Start the background service for an installed plugin targeting a jail
jroot plugin service start enterprise-audit on_monitor dev

# Check real-time service status and PID
jroot plugin service status enterprise-audit

# Stop the running background service cleanly
jroot plugin service stop enterprise-audit
```

When running as a service, the plugin entrypoint receives continuous hook iterations or acts as an asynchronous daemon, writing telemetry data directly through the JRoot SDK.

---

## 6. Comprehensive Error Handling & Troubleshooting

When developing and deploying JRoot plugins, certain failure modes are common. The table below outlines symptoms, root causes, and corrective actions.

| Symptom | Root Cause | Corrective Action |
|---|---|---|
| `ModuleNotFoundError: No module named 'jroot_sdk'` | Executing the plugin script directly without setting `PYTHONPATH`, or running on an older JRoot installation missing the SDK auto-provisioner. | Upgrade JRoot to commit `4c813e5` or later. The JRoot runtime automatically provisions `$JROOT_HOME/sdk/jroot_sdk.py` and exports `PYTHONPATH`. |
| `Refusing to install an invalid plugin bundle` | Manifest `name` uses uppercase letters, contains reserved commands, or `api_version` is incorrect. | Run `python3 jroot-dev.py validate --strict <plugin-dir>` to locate manifest errors prior to installation [3]. |
| Hook execution produces no output or state changes | The hook name is missing from the `hooks` array in `plugin.json`, or the entrypoint argument parser does not match `sys.argv`. | Verify that the hook is explicitly declared in `plugin.json` and inspect `~/.jroot/plugins/logs/<plugin-name>.log` for stderr exceptions. |
| `JSONDecodeError` when reading plugin state | Concurrent writes or manual file edits corrupted the JSON state store. | Use `context.read_plugin_state(filename, default)` exclusively; avoid raw file handling for state storage. |

---

## 7. Cross-Platform Development & Testing Workflow

JRoot provides `jroot-dev.py` as a cross-platform helper script (supporting Windows, macOS, and Linux) so developers can validate and test plugins locally before deploying them to a production Linux PRoot host.

### Step-by-Step Development Workflow

1.  **Initialize a plugin template:**
    ```bash
    python3 jroot-dev.py init my-new-plugin
    ```
2.  **Validate manifest strictness and syntax:**
    ```bash
    python3 jroot-dev.py validate --strict my-new-plugin
    ```
3.  **Simulate individual hook dispatches locally:**
    ```bash
    python3 jroot-dev.py simulate on_init --path my-new-plugin
    python3 jroot-dev.py simulate on_limit --path my-new-plugin
    ```
4.  **Execute the full local fixture test suite:**
    ```bash
    python3 jroot-dev.py test my-new-plugin
    ```
5.  **Install the validated plugin on your JRoot environment:**
    ```bash
    jroot plugin install ./my-new-plugin
    ```

---

## References

[1] IntellsGamer, *JRoot: A Rootless Userspace Container Platform Built on PRoot*, GitHub Repository, https://github.com/IntellsGamer/jroot.  
[2] Manus AI, *JRoot Architecture and Plugin SDK Specification*, Internal Engineering Notes, 2026.  
[3] Python Software Foundation, *Python 3 Standard Library: JSON and Subprocess Management*, https://docs.python.org/3/.
