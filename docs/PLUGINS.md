# 🔌 JRoot Production-Grade Plugin System (`discord.py` Grade)

JRoot features an enterprise-grade, event-driven plugin extension architecture. Inspired by robust event-driven frameworks like `discord.py`, plugins can intercept deep lifecycle hooks, manage private persistent state, query jail metadata, and register custom subcommands without risking core command collisions.

---

## Quickstart: Generating a Plugin SDK Template

Generate a starter Python plugin bundle instantly:

```bash
jroot plugin init-sdk
```

This creates a `./jroot-plugin-template/` directory containing:
1. **`plugin.json`**: Manifest declaring plugin metadata, version, and author.
2. **`main.py`**: Event-driven entry point handling hook dispatches and custom arguments.

---

## Lifecycle Hooks & Events (`discord.py` Style)

Plugins listen to core JRoot lifecycle events by reacting to `hook:<event_name>` arguments:

| Event Hook | Trigger Condition | Arguments Passed |
| :--- | :--- | :--- |
| **`on_init`** | Fired immediately after a new jail is created. | `[jail_name, image]` |
| **`on_enter`** | Fired whenever a shell or command is launched inside a jail. | `[jail_name]` |
| **`on_stop`** | Fired when stopping/killing a jail. | `[jail_name]` |
| **`on_remove`** | Fired when a jail is permanently deleted. | `[jail_name]` |
| **`on_sync`** | Fired when synchronizing files via `jroot sync`. | `[src, dst]` |
| **`on_snapshot`** | Fired when a snapshot is created or restored. | `[jail_name, action:label]` |
| **`on_limit`** | Fired when resource limits are updated. | `[jail_name]` |

---

## Private Plugin Data Stores

Every plugin is automatically assigned a private persistent storage directory (`$JROOT_PLUGIN_DATA`), enabling plugins to save configuration files, caches, or state databases without conflicting with other extensions.

---

## Python SDK (`JRootContext`)

Import `JRootContext` to interact cleanly with JRoot storage and execute commands inside jails:

```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext

def main():
    ctx = JRootContext()
    
    # Read/write private persistent state
    state = ctx.read_plugin_state("counter.json", {"runs": 0})
    state["runs"] += 1
    ctx.write_plugin_state(state, "counter.json")

    print(f"Plugin run count: {state['runs']}")
    for jail in ctx.list_jails():
        print(f"Jail: {jail['name']} ({jail['image']})")

if __name__ == "__main__":
    main()
```
