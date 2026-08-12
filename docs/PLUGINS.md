# JRoot Plugin System

JRoot provides an event-driven extension architecture designed for enterprise userspace container management. The plugin subsystem enables modular integration through lifecycle hook interception, isolated state persistence, and custom command registration without conflicting with core runtime operations.

---

## Architecture Overview

Plugins interface with JRoot via executable scripts or packages placed in the plugin search path. The runtime dispatches events to registered plugin handlers, passing relevant execution context and state parameters as command-line arguments.

---

## Quickstart: SDK Template Generation

To bootstrap a new plugin conforming to standard structure and SDK practices:

```bash
jroot plugin init-sdk
```

This generates a local `./jroot-plugin-template/` directory containing:
1. **`plugin.json`**: Manifest declaring plugin metadata, versioning, and author information.
2. **`main.py`**: Event-handling entry point demonstrating hook dispatches and SDK utilities.

---

## Lifecycle Hooks & Event Dispatch

Plugins subscribe to core runtime events using standard hook arguments (`hook:<event_name>`):

| Lifecycle Event | Trigger Condition | Parameter Payload |
| :--- | :--- | :--- |
| **`on_init`** | Executed immediately after a new jail instance is provisioned. | `[jail_name, image]` |
| **`on_enter`** | Executed when attaching a shell or running a command inside a jail. | `[jail_name]` |
| **`on_stop`** | Executed upon stopping or terminating a jail container. | `[jail_name]` |
| **`on_remove`** | Executed when a jail instance is permanently purged. | `[jail_name]` |
| **`on_sync`** | Executed during bidirectional filesystem synchronization (`jroot sync`). | `[src, dst]` |
| **`on_snapshot`** | Executed when creating or restoring container snapshots. | `[jail_name, action:label]` |
| **`on_limit`** | Executed when updating resource governance limits. | `[jail_name]` |

---

## Private Plugin Data Persistence

Each plugin is provisioned with a dedicated persistent storage directory (`$JROOT_PLUGIN_DATA`), isolating local state, configuration files, and caches to prevent state pollution across distinct plugins.

---

## Python SDK Reference (`JRootContext`)

The `JRootContext` library provides helper utilities for programmatic jail inspection, command execution, and state persistence:

```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext

def main():
    ctx = JRootContext()
    
    # Manage isolated persistent plugin state
    state = ctx.read_plugin_state("state.json", {"executions": 0})
    state["executions"] += 1
    ctx.write_plugin_state(state, "state.json")

    print(f"Total executions: {state['executions']}")
    for jail in ctx.list_jails():
        print(f"Container: {jail['name']} ({jail['image']})")

if __name__ == "__main__":
    main()
```
