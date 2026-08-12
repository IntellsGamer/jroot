# JRoot Plugin Developer Manual

This manual covers the JRoot event-driven plugin system. If you want to extend JRoot with custom audit loggers, automated backup routines, webhook bridges, or background resource monitors, this is your complete reference.

---

## 1. How the Plugin Engine Works Under the Hood

Before writing code, it helps to understand how JRoot manages plugins. JRoot is written in Bash, but plugins run as standalone scripts (usually Python 3) invoked through a strict process boundary.

When you install a plugin via `jroot plugin install ./my-plugin`, JRoot does the following:
1. **Reads and Validates `plugin.json`**: It checks that your plugin name is lowercase, has a valid semantic version, and **does not collide with any core JRoot command** (like `init`, `enter`, `sync`, or `checkpoint`).
2. **Copies the Bundle**: It places your plugin directory into `~/.jroot/plugins/installed/<plugin-name>/`.
3. **Allocates Data Storage**: It provisions an isolated state directory at `~/.jroot/plugins/data/<plugin-name>/` and a log file at `~/.jroot/plugins/logs/<plugin-name>.log`.

### Event Dispatch Mechanism
When a lifecycle event occurs—such as `jroot sync` completing or `jroot limit` updating—JRoot iterates over all installed plugins that declare interest in that hook. It spawns your entrypoint script with a command-line argument structure like this:

```bash
python3 main.py hook:on_sync host:/project dev:/root/project
```

Your script is responsible for inspecting `sys.argv[1]`, branching based on the hook name, parsing the remaining arguments, and executing your logic.

---

## 2. Complete SDK Method Reference (`jroot_sdk.py`)

Every plugin receives an isolated copy of `jroot_sdk.py` (or automatically references the runtime SDK). The SDK provides two main classes: `Logger` and `JRootContext`.

### `Logger(plugin_name)`
Instantiated automatically by the context. Prints timestamped log lines that are captured by JRoot.
*   `logger.info(msg)` — Writes an `INFO` level log.
*   `logger.warn(msg)` — Writes a `WARN` level log.
*   `logger.error(msg)` — Writes an `ERROR` level log.
*   `logger.debug(msg)` — Writes a `DEBUG` level log.

### `JRootContext`
The central utility class for interacting with the host JRoot environment.

| Method | Parameters | Return Type | Description |
|---|---|---|---|
| `list_jails()` | None | `list[dict]` | Returns metadata for all active jails, including rootfs paths and active resource limits. |
| `get_jail(name)` | `name: str` | `dict \| None` | Loads the JSON configuration dictionary for a specific jail. Returns `None` if it doesn't exist. |
| `run_in_jail(name, cmd)` | `name: str, cmd: str` | `tuple[int, str, str]` | Executes a shell command inside the specified jail via `jroot exec`. Returns `(exit_code, stdout, stderr)`. |
| `get_resource_usage(name)` | `name: str` | `dict \| None` | Inspects live process accounting via `/proc`, returning RSS memory in bytes/MB, CPU seconds, and active PID count. |
| `read_plugin_state(file, default)` | `file: str, default: Any` | `Any` | Reads a JSON file from your private plugin data directory. Returns `default` if missing or corrupted. |
| `write_plugin_state(data, file)` | `data: Any, file: str` | `None` | Atomically writes JSON data using tempfile replacement semantics to prevent partial writes. |

---

## 3. Real-World Example 1: Git Auto-Committer (`git-sync`)

Imagine you have a development jail where you edit code. You want a plugin that automatically runs `git commit` inside the jail whenever `jroot sync` finishes pushing changes from your host.

### Directory Structure
```text
git-sync/
├── plugin.json
└── main.py
```

### `plugin.json`
```json
{
  "api_version": 1,
  "name": "git-sync",
  "version": "1.0.0",
  "description": "Automatically commits changes inside a jail after a host-to-jail sync operation.",
  "author": "Developer",
  "entrypoint": "main.py",
  "hooks": ["on_sync"],
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
import sys
from jroot_sdk import JRootContext

def main():
    context = JRootContext()
    if len(sys.argv) < 2:
        print("git-sync plugin active.")
        return 0

    action = sys.argv[1]
    if action == "hook:on_sync":
        # sys.argv[2] is source, sys.argv[3] is destination (e.g. dev:/root/app)
        src, dst = sys.argv[2], sys.argv[3]
        context.log.info(f"Sync detected from {src} to {dst}")

        if ":" in dst:
            jail_name, jail_path = dst.split(":", 1)
            # Check if this path looks like a git repository
            code, out, err = context.run_in_jail(jail_name, f"cd {jail_path} && git rev-parse --is-inside-work-tree")
            if code == 0:
                context.log.info(f"Git repository found in {jail_name}:{jail_path}. Committing changes...")
                commit_cmd = "git add -A && git commit -m 'Auto-commit via jroot sync plugin' || true"
                c_code, c_out, c_err = context.run_in_jail(jail_name, f"cd {jail_path} && {commit_cmd}")
                if c_code == 0:
                    context.log.info("Auto-commit successful.")
                else:
                    context.log.error(f"Auto-commit failed: {c_err}")
            else:
                context.log.debug(f"Target {dst} is not a git repository. Skipping.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

---

## 4. Real-World Example 2: Resource Watchdog & Alerting (`jail-watchdog`)

This plugin hooks into `on_limit` and uses a background service (`on_monitor`) to watch active jail memory consumption, logging warnings if a jail exceeds safe thresholds.

### `plugin.json`
```json
{
  "api_version": 1,
  "name": "jail-watchdog",
  "version": "1.1.0",
  "description": "Monitors memory usage across active jails and records limit adjustments.",
  "author": "Sysadmin",
  "entrypoint": "main.py",
  "hooks": ["on_limit", "on_monitor"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": ["python3"]
  }
}
```

### `main.py`
```python
#!/usr/init/env python3
import sys
import time
from jroot_sdk import JRootContext

def handle_limit(context: JRootContext, jail: str, limits: str):
    context.log.info(f"Watchdog noticed limit change on '{jail}': {limits}")
    state = context.read_plugin_state("history.json", {"changes": []})
    state["changes"].append({"jail": jail, "limits": limits, "time": time.time()})
    context.write_plugin_state(state, "history.json")

def run_monitor_daemon(context: JRootContext, target_jail: str):
    context.log.info(f"Starting continuous watchdog monitor for jail: {target_jail}")
    while True:
        usage = context.get_resource_usage(target_jail)
        if usage:
            mem_mb = usage["mem_mb"]
            context.log.debug(f"Jail '{target_jail}' memory RSS: {mem_mb} MB ({usage['pids']} processes)")
            if mem_mb > 512.0:
                context.log.warn(f"HIGH MEMORY ALERT: Jail '{target_jail}' is consuming {mem_mb} MB!")
        time.sleep(10)

def main():
    context = JRootContext()
    if len(sys.argv) < 2:
        print("Usage: jroot plugin invoke jail-watchdog")
        return 0

    action = sys.argv[1]
    if action.startswith("hook:"):
        hook = action.split(":", 1)[1]
        args = sys.argv[2:]
        if hook == "on_limit" and len(args) >= 2:
            handle_limit(context, args[0], args[1])
        elif hook == "on_monitor" and len(args) >= 1:
            # When started as a service: jroot plugin service start jail-watchdog on_monitor <jail>
            run_monitor_daemon(context, args[0])
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

---

## 5. Testing, Debugging, and Simulation

Never guess whether your plugin works. JRoot includes a local cross-platform development helper (`jroot-dev.py`) that simulates the entire execution environment on Linux, macOS, or Windows without requiring PRoot or rootfs downloads.

### Step 1: Validate Manifest Strictness
```bash
python3 jroot-dev.py validate --strict ./jail-watchdog
```
If your manifest has missing keys, invalid semantic versioning, or uses a reserved command name, validation fails instantly with descriptive errors.

### Step 2: Simulate Hook Dispatches Locally
You can run individual hooks with mock payloads to verify your Python script parses `sys.argv` correctly:
```bash
python3 jroot-dev.py simulate on_limit --path ./jail-watchdog
```

### Step 3: Run the Full Fixture Test Suite
```bash
python3 jroot-dev.py test ./jail-watchdog
```
This automatically initializes a mock JRoot workspace, installs the plugin, triggers every declared lifecycle hook, verifies state persistence, and reports success or failure.

---

## 6. Installing and Managing Plugins in Production

Once tested locally, install your plugin into your live JRoot environment:

```bash
jroot plugin install ./jail-watchdog
```

### Useful Management Commands
*   **List installed plugins:** `jroot plugin list`
*   **Inspect plugin metadata & last run status:** `jroot plugin inspect jail-watchdog`
*   **Run verification checks:** `jroot plugin verify jail-watchdog`
*   **Start a background daemon service:** `jroot plugin service start jail-watchdog on_monitor dev`
*   **Check daemon status:** `jroot plugin service status jail-watchdog`
*   **Stop a running daemon:** `jroot plugin service stop jail-watchdog`
*   **Remove a plugin:** `jroot plugin remove jail-watchdog`

---

## 7. Troubleshooting Common Issues

### Issue: `ModuleNotFoundError: No module named 'jroot_sdk'`
*   **Cause:** Your script is being executed in an environment where `PYTHONPATH` does not point to the JRoot SDK directory.
*   **Fix:** Ensure your JRoot installation is up to date. The runtime automatically injects `PYTHONPATH` and provisions `jroot_sdk.py` inside `~/.jroot/sdk/` before invoking hooks.

### Issue: Plugin does not receive a specific hook
*   **Cause:** The hook name is missing from the `"hooks": [...]` array in your `plugin.json`.
*   **Fix:** Add the hook string to your manifest and re-run `jroot plugin install ./my-plugin`.

### Issue: State file corruption (`JSONDecodeError`)
*   **Cause:** Writing directly to state files using standard `open().write()` without atomic replacement while another process is reading.
*   **Fix:** Always use `context.write_plugin_state(data, filename)`, which utilizes temporary file rotation.
