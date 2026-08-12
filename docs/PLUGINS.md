# 🔌 JRoot Production-Grade Plugin System

JRoot features an enterprise-grade, event-driven plugin extension architecture inspired by modern framework designs (such as `discord.py`). Plugins can intercept lifecycle events, query jail metadata, and register custom subcommands without risking core command collisions.

---

## Quickstart: Generating a Plugin SDK Template

Generate a starter Python plugin bundle instantly:

```bash
jroot plugin init-sdk
```

This creates a `./jroot-plugin-template/` directory containing:
1. **`plugin.json`**: Manifest declaring plugin metadata, version, and capabilities.
2. **`main.py`**: Event-driven entry point handling hook dispatches and custom arguments.

---

## Lifecycle Hooks & Events

Plugins can listen to core JRoot lifecycle events by reacting to `hook:<event_name>` arguments:

| Event Hook | Trigger Condition | Arguments Passed |
| :--- | :--- | :--- |
| **`on_init`** | Fired immediately after a new jail is successfully created. | `[jail_name, image]` |
| **`on_enter`** | Fired whenever a shell or command is launched inside a jail. | `[jail_name]` |
| **`on_remove`** | Fired when a jail is permanently deleted. | `[jail_name]` |

---

## Python SDK (`jroot_sdk`)

For advanced automation, import the helper SDK inside your plugins:

```python
from jroot_sdk import JRootContext

ctx = JRootContext()
for jail in ctx.list_jails():
    print(jail["name"], jail["image"], jail["limit_mem"])
```
