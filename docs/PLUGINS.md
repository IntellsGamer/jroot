# JRoot Enterprise Plugin Ecosystem

JRoot provides an event-driven extension architecture designed for enterprise userspace container management. The plugin subsystem enables modular integration through lifecycle hook interception, isolated state persistence, and custom command registration.

---

## Pro Features: Logging & Services

For production-grade extensions, JRoot includes advanced telemetry and background execution capabilities.

### Structured Logging
All plugin output (stdout/stderr) is automatically captured and routed to `$JROOT_HOME/plugins/logs/<plugin_name>.log`.

```bash
# View recent logs for a plugin
jroot plugin logs my-plugin
```

### Background Services
Plugins can register long-running background tasks (e.g., resource monitors, auto-cleanup daemons) using the `service` command.

```bash
# Run a plugin hook as a background service
jroot plugin service my-plugin on_monitor
```

---

## Python SDK Reference (`JRootContext`)

The `JRootContext` library provides enterprise-grade utilities for programmatic jail inspection, command execution, and telemetry:

```python
#!/usr/bin/env python3
from jroot_sdk import JRootContext

def main():
    ctx = JRootContext()
    
    # 1. Structured Logging
    ctx.log.info("Starting resource audit...")
    
    # 2. Real-time Resource Monitoring
    usage = ctx.get_resource_usage("production-jail")
    if usage and usage["mem_mb"] > 512:
        ctx.log.warn(f"Jail exceeding threshold: {usage['mem_mb']}MB")
    
    # 3. Persistent State
    state = ctx.read_plugin_state("audit.json", {"count": 0})
    state["count"] += 1
    ctx.write_plugin_state(state, "audit.json")

if __name__ == "__main__":
    main()
```

---

## Lifecycle Hooks Reference

| Lifecycle Event | Trigger Condition | Parameter Payload |
| :--- | :--- | :--- |
| **`on_init`** | Executed after a new jail instance is provisioned. | `[jail_name, image]` |
| **`on_enter`** | Executed when attaching a shell or running a command. | `[jail_name]` |
| **`on_stop`** | Executed upon stopping or terminating a jail. | `[jail_name]` |
| **`on_remove`** | Executed when a jail instance is purged. | `[jail_name]` |
| **`on_sync`** | Executed during bidirectional synchronization. | `[src, dst]` |
| **`on_snapshot`** | Executed when managing snapshots. | `[jail_name, action:label]` |
| **`on_limit`** | Executed when updating resource governance. | `[jail_name]` |
| **`on_monitor`** | Custom hook for background service monitoring. | `[jail_name]` |

---

## Development Workflow

1.  **Initialize**: `jroot plugin init-sdk`
2.  **Validate**: `python jroot-dev.py validate .`
3.  **Simulate**: `python jroot-dev.py simulate on_init myjail ubuntu:22.04`
4.  **Install**: `jroot plugin install .`
5.  **Service**: `jroot plugin service my-plugin on_monitor myjail`
