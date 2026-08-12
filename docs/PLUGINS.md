# JRoot Plugin Developer Manual & Cookbook

Welcome to the definitive guide for extending JRoot. If you want to write custom audit loggers, automated backup routines, webhook notifiers, or background telemetry daemons, this manual covers everything from core execution mechanics to advanced design patterns.

---

## 1. Core Mechanics: How JRoot Executes Plugins

JRoot is written in Bash, but plugins are designed to run as standalone processes (typically Python scripts or shell scripts) connected via a strict process boundary. Understanding how JRoot talks to your plugin will save you hours of debugging.

### The Dispatch Loop
When a lifecycle event occurs—such as `jroot sync` finishing or `jroot limit` updating—JRoot does the following:
1. **Scans Installed Plugins:** It looks inside `~/.jroot/plugins/installed/` for plugins that declare interest in that specific hook inside their `plugin.json`.
2. **Prepares the Environment:** It injects standard environment variables (`JROOT_HOME`, `JROOT_PLUGIN_DATA`, `JROOT_COMMAND`) and automatically configures `PYTHONPATH` so `jroot_sdk` imports successfully.
3. **Spawns the Entrypoint:** It invokes your entrypoint script as a subprocess, passing a structured argument vector (`sys.argv`).

```text
[JRoot Core Runtime] 
       │  (Event: on_sync)
       ▼
[Internal Dispatcher] ──(Injects PYTHONPATH & JROOT_PLUGIN_DATA)
       │
       ▼
[Plugin Entrypoint: main.py] 
       ├── sys.argv[1] == "hook:on_sync"
       ├── sys.argv[2] == "host:/src"
       └── sys.argv[3] == "dev:/dst"
```

### Process Isolation & Failure Handling
Plugins run in isolated subprocesses. **If your plugin crashes, exits with a non-zero status, or throws an unhandled exception, JRoot logs the error to `~/.jroot/plugins/logs/<plugin-name>.log` but does NOT crash the core JRoot operation.** Your plugin's failure will never prevent a user from entering a jail or syncing files.

---

## 2. The Plugin Cookbook (Common Patterns)

Here are real-world recipes for solving common architectural problems when writing JRoot plugins.

### Recipe 1: The Notifier Pattern (Webhook / Slack Alerts)
*Goal:* Send a notification whenever a jail resource limit is changed.

```python
#!/usr/bin/env python3
import sys
import urllib.request
import json
from jroot_sdk import JRootContext

def send_webhook(url: str, message: str):
    payload = json.dumps({"text": message}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass # Never let a network failure crash the hook

def main():
    context = JRootContext()
    # Read user configuration from private state or config file
    config = context.read_plugin_state("config.json", {"webhook_url": ""})
    
    if len(sys.argv) > 1 and sys.argv[1] == "hook:on_limit":
        jail, limits = sys.argv[2], sys.argv[3]
        context.log.info(f"Limit changed on {jail}: {limits}")
        
        if config["webhook_url"]:
            msg = f"⚠️ JRoot Alert: Limits adjusted for jail `{jail}` -> `{limits}`"
            send_webhook(config["webhook_url"], msg)
            
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

### Recipe 2: The Command Interceptor / Validator
*Goal:* Prevent users from running dangerous commands (like `rm -rf /`) during `jroot enter`.

```python
#!/usr/bin/env python3
sys
from jroot_sdk import JRootContext

def main():
    context = JRootContext()
    if len(sys.argv) > 1 and sys.argv[1] == "hook:on_enter":
        jail, command = sys.argv[2], sys.argv[3]
        context.log.info(f"Auditing enter on {jail} with command: {command}")
        
        # Simple security heuristic check
        dangerous_patterns = ["rm -rf /", "mkfs", ":(){ :|:& };:"]
        for pattern in dangerous_patterns:
            if pattern in command:
                context.log.error(f"BLOCKED DANGEROUS COMMAND: {command}")
                print(f"Error: JRoot security policy blocked command containing '{pattern}'", file=sys.stderr)
                sys.exit(1) # Returning non-zero aborts or flags the operation depending on the hook
                
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

### Recipe 3: Writing a Pure Bash Plugin (No Python Needed)
If you prefer shell scripting over Python, you can write plugins entirely in Bash. You just need a `plugin.json` and an executable shell script entrypoint.

**`plugin.json`:**
```json
{
  "api_version": 1,
  "name": "bash-audit",
  "version": "1.0.0",
  "description": "Simple bash-based audit logger.",
  "author": "Sysadmin",
  "entrypoint": "audit.sh",
  "hooks": ["on_init"],
  "permissions": ["jails.read"],
  "requires": {
    "python": ">=3.8",
    "commands": ["bash"]
  }
}
```

**`audit.sh`:**
```bash
#!/usr/bin/env bash
# Bash plugin entrypoint
ACTION="${1:-}"

if [ "$ACTION" = "hook:on_init" ]; then
    JAIL="$2"
    IMAGE="$3"
    echo "$(date) - Jail created: $JAIL from $IMAGE" >> "$JROOT_PLUGIN_DATA/audit.log"
fi
exit 0
```

---

## 3. Advanced SDK Reference (`jroot_sdk.py`)

The JRoot SDK exposes typed, robust helpers for inspecting host state and managing persistent storage.

### `JRootContext` Methods

*   **`list_jails() -> list[dict]`**  
    Scans `configs/` and returns metadata for every provisioned jail.
    ```python
    for jail in context.list_jails():
        print(f"Jail: {jail['name']} | Image: {jail['image']} | RSS: {jail['rootfs_path']}")
    ```

*   **`get_jail(name: str) -> dict | None`**  
    Loads the exact JSON config dictionary for a single jail. Returns `None` if the jail doesn't exist.

*   **`run_in_jail(jail_name: str, command: str) -> tuple[int, str, str]`**  
    Executes an arbitrary shell command inside the rootfs via `jroot exec`. Returns `(exit_code, stdout, stderr)`.

*   **`get_resource_usage(jail_name: str) -> dict | None`**  
    Inspects live process accounting via `/proc`, returning RSS memory and CPU ticks for active jail launcher processes:
    ```python
    usage = context.get_resource_usage("dev")
    print(f"Memory: {usage['mem_mb']} MB | Active PIDs: {usage['pids']}")
    ```

*   **`read_plugin_state(filename="state.json", default=None) -> Any`**  
    Loads JSON data from your private storage directory (`~/.jroot/plugins/data/<name>/`). Automatically handles missing files by returning your `default` value.

*   **`write_plugin_state(data: Any, filename="state.json") -> None`**  
    Atomically writes JSON state using tempfile replacement semantics (`os.replace`), preventing partial or corrupted writes if the plugin is interrupted.

---

## 4. Background Services & Daemon Management

Plugins can run continuous background processes supervised by JRoot. 

### Implementing a Daemon (`on_monitor`)
Declare `on_monitor` in your `plugin.json` hooks array. When started, your entrypoint will receive `hook:on_monitor` as `sys.argv[1]`, followed by any arguments passed to the start command.

```python
import sys
import time
from jroot_sdk import JRootContext

def main():
    context = JRootContext()
    if len(sys.argv) > 1 and sys.argv[1] == "hook:on_monitor":
        jail_name = sys.argv[2] if len(sys.argv) > 2 else "default"
        context.log.info(f"Watchdog daemon started for jail: {jail_name}")
        
        while True:
            usage = context.get_resource_usage(jail_name)
            if usage:
                context.log.debug(f"Daemon heartbeat: {usage['mem_mb']} MB used")
            time.sleep(30)
            
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

### Managing the Service Lifecycle
From the host terminal, manage your background service using standard JRoot commands:
```bash
# Start the background daemon
jroot plugin service start my-plugin on_monitor dev

# Check if it's running and inspect its PID
jroot plugin service status my-plugin

# Stop the daemon cleanly
jroot plugin service stop my-plugin
```

---

## 5. Security Best Practices for Plugin Authors

1.  **Never trust input payloads:** Jail names and file paths passed in `sys.argv` should be validated before passing them to shell commands or file operations.
2.  **Avoid blocking hooks:** Synchronous hooks (`on_init`, `on_limit`, `on_sync`, `on_snapshot`) execute directly inside the CLI request path. Keep them lightweight. Offload heavy network requests or slow operations to background services or asynchronous threads.
3.  **Use atomic state writes:** Always use `context.write_plugin_state()` rather than manual `open(file, 'w')` to prevent state corruption.
4.  **Respect permissions:** Declare only the permissions you actually need (`jails.read`, `state.read`, `state.write`) in your manifest.

---

## 6. Testing Your Plugin Locally

You don't need a Linux PRoot environment to test your plugin. Use the cross-platform development helper `jroot-dev.py` (which runs on Windows, macOS, and Linux):

```bash
# 1. Initialize a test template
python3 jroot-dev.py init my-plugin

# 2. Validate manifest strictness
python3 jroot-dev.py validate --strict ./my-plugin

# 3. Simulate a hook locally with mock data
python3 jroot-dev.py simulate on_sync --path ./my-plugin

# 4. Run the complete test fixture suite
python3 jroot-dev.py test ./my-plugin
```

Once verified, install it into your live environment with `jroot plugin install ./my-plugin`.
