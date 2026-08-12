# JRoot Plugin Developer Manual

JRoot plugins are **trusted host-side extensions**. They let you observe JRoot operations, keep plugin-owned state, run commands in a jail through the SDK, add a small direct CLI, and launch long-running helper processes.

This manual is deliberately organised in the order most plugin authors need it:

1. understand what a plugin is and is not;
2. build and test a minimal plugin;
3. learn the manifest, hook, SDK, runtime, and service contracts;
4. understand failure modes, security limits, and operational constraints; and
5. assemble a complete working plugin at the end.

> **Important:** A JRoot plugin runs as the **host user**. It is not sandboxed by PRoot and it is not confined to a jail. Only install code that you have reviewed and trust.

---

## Contents

| Section | What it answers |
|---|---|
| [1. Mental model](#1-mental-model) | What code runs where, and what happens after an event fires? |
| [2. Quick start](#2-quick-start) | How do I make, validate, install, and exercise a minimal plugin? |
| [3. Plugin files and lifecycle](#3-plugin-files-and-lifecycle) | Where do installed code, logs, state, and status records live? |
| [4. Manifest reference](#4-pluginjson-manifest-reference) | Which `plugin.json` fields are required and what does JRoot validate? |
| [5. Hook reference](#5-lifecycle-hook-reference) | Which events exist, and what exact arguments does each receive? |
| [6. SDK reference](#6-python-sdk-reference) | How do I query jails, run commands, inspect usage, and store state? |
| [7. Runtime environment](#7-runtime-environment) | Which environment variables are available to an entrypoint? |
| [8. Direct plugin commands](#8-direct-plugin-commands) | How can `jroot my-plugin ...` expose plugin-specific output? |
| [9. Services](#9-background-plugin-services) | How do I run and supervise a long-lived helper process? |
| [10. Testing workflow](#10-development-testing-and-installation-workflow) | What should I run before and after installing a plugin? |
| [11. Reliability and limits](#11-reliability-ordering-and-current-limits) | What happens on failure, and which things are intentionally not supported? |
| [12. Troubleshooting](#12-troubleshooting) | How do I diagnose common installation, runtime, and state problems? |
| [13. Full example](#13-full-example-jail-audit) | What does a complete plugin look like from source files to use? |

---

## 1. Mental model

A plugin is a directory containing a manifest and an entrypoint. JRoot does not load plugin code into its Bash process. Instead, it starts the plugin as a child process and passes an event selector plus event-specific arguments.

```text
jroot sync ./site dev:/srv/site
        │
        ├── finishes the requested JRoot operation
        │
        └── for every installed bundle that declares on_sync:
              ├── prepares JROOT_* environment variables
              ├── makes jroot_sdk.py importable for Python entrypoints
              ├── starts main.py or main.sh with hook:on_sync arguments
              ├── appends stdout and stderr to the plugin log
              └── records the last result in the plugin status file
```

A plugin therefore has two possible entry modes.

| Entry mode | Trigger | First argument | Typical use |
|---|---|---|---|
| Lifecycle hook | JRoot finishes a supported operation | `hook:on_<name>` | Audit events, record state, submit notifications, kick off lightweight automation. |
| Direct command | A user enters an unknown core command matching an installed plugin name | Plugin-defined | Print a report, expose a diagnostic command, inspect the plugin's own state. |
| Service | User starts `jroot plugin service start` | `hook:on_<name>` | A long-lived monitor, worker, or bridge process. |

### What plugins can do

The SDK gives a plugin access to JRoot metadata and a controlled way to launch a command inside an existing jail. A plugin can also read and write its own state directory and write ordinary host-side files allowed by the host user's permissions.

| Capability | Supported approach |
|---|---|
| List configured jails | `context.list_jails()` |
| Read one jail configuration | `context.get_jail("dev")` |
| Run a command inside an existing jail | `context.run_in_jail("dev", "id")` |
| Observe tracked process usage | `context.get_resource_usage("dev")` |
| Store plugin-owned JSON | `context.read_plugin_state()` / `context.write_plugin_state()` |
| Provide a direct command | Handle non-hook arguments in the entrypoint and run `jroot <plugin-name> ...` |
| Run a persistent helper process | `jroot plugin service start <plugin> <on_hook> [args...]` |

### What plugins cannot currently do

The distinction matters because a lifecycle hook is an **observer**, not a policy gate.

| Desired behaviour | Current behaviour |
|---|---|
| Abort `jroot enter`, `jroot exec`, or another core operation by returning non-zero | **Not supported.** JRoot records hook failures and continues the core operation. |
| Receive the literal command submitted to `jroot exec` | **Not supported.** `on_enter` receives `command`, not the user command line. |
| Obtain a sandbox, restricted filesystem, or jail-only permissions | **Not supported.** The plugin is host-side trusted code. |
| Install Python packages automatically from `requirements.txt` | **Not supported.** JRoot only checks declared command and Python-version requirements. |
| Receive automatic service restart after a crash | **Not supported.** A service has one process; check status and start it again if necessary. |
| Use a transactional shared state database across plugins | **Not supported.** Each plugin owns a JSON directory; there is no locking or event bus. |
| Impose a live-runtime hook timeout | **Not supported.** Keep normal hooks short yourself. The development helper has a configurable simulation timeout. |

These constraints are intentional documentation points, not workarounds. Design a plugin around observation and side effects that are safe to retry.

---

## 2. Quick start

This first plugin records each real `on_limit` event in its private JSON state. It is small enough to understand line by line, but uses the same manifest and SDK path as a larger plugin.

### 2.1 Create a starting directory

You can create a template in either of two ways.

| Command | When to use it | Result |
|---|---|---|
| `jroot plugin init-sdk` | You are on the JRoot host and want a standard local template | Creates `./jroot-plugin-template/`. |
| `python3 jroot-dev.py init limit-notes` | You are developing on Windows, macOS, or Linux and want a named template | Creates `./limit-notes/`. |

For this walkthrough, create the files manually:

```bash
mkdir limit-notes
cd limit-notes
```

### 2.2 Add `plugin.json`

```json
{
  "api_version": 1,
  "name": "limit-notes",
  "version": "0.1.0",
  "description": "Records resource limit changes.",
  "author": "Your name",
  "entrypoint": "main.py",
  "hooks": ["on_limit"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": ["python3"]
  }
}
```

The only hook in this bundle is `on_limit`, so JRoot will not start this plugin for syncs, snapshots, or shell launches.

### 2.3 Add `main.py`

```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext


def main() -> int:
    context = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    if action == "hook:on_limit":
        jail, limits = sys.argv[2:4]
        state = context.read_plugin_state("events.json", {"events": []})
        state["events"].append({"jail": jail, "limits": limits})
        context.write_plugin_state(state, "events.json")
        context.log.info(f"Recorded limits for {jail}: {limits}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

The code first reads the event selector. It only unpacks `jail, limits` after confirming that the hook is `on_limit`, which avoids treating direct-command arguments as lifecycle payloads.

### 2.4 Validate before installing

Run strict validation locally:

```bash
python3 ../jroot-dev.py validate --strict .
```

Then exercise the declared hook in an isolated mock runtime:

```bash
python3 ../jroot-dev.py simulate on_limit --path .
python3 ../jroot-dev.py test .
```

`simulate` runs one named hook; `test` runs every hook declared in `plugin.json`. Neither command starts a PRoot jail or modifies the user's real JRoot directory.

### 2.5 Install and use it on a JRoot host

```bash
jroot plugin install ./limit-notes
jroot plugin verify limit-notes
jroot limit dev --mem=256M --cpu=30 --nofile=1024
jroot plugin logs limit-notes
jroot plugin inspect limit-notes
```

After the limit operation, the plugin's state file is stored at:

```text
~/.jroot/plugins/data/limit-notes/events.json
```

Use the SDK to access this path instead of relying on that concrete location in your own source code.

---

## 3. Plugin files and lifecycle

JRoot stores installed plugin code and its runtime artefacts below `JROOT_HOME`. The usual value of `JROOT_HOME` is `~/.jroot`, but it can be overridden for portable installs, CI, or test environments.

```text
$JROOT_HOME/
├── plugins/
│   ├── <plugin-name>/              # installed packaged plugin bundle
│   │   ├── plugin.json
│   │   └── main.py or main.sh
│   ├── <legacy-plugin>.py          # optional legacy single-file plugin
│   ├── data/<plugin-name>/          # private plugin-owned state
│   ├── logs/<plugin-name>.log       # combined plugin stdout and stderr
│   └── status/<plugin-name>.json    # most recent result for that plugin
├── pids/plugin-<name>-<hook>.service.pid
└── sdk/jroot_sdk.py                 # importable Python SDK
```

### Packaged bundles versus legacy single-file plugins

JRoot still accepts a single `.py` or `.sh` script for quick local experiments. Packaged bundles are the normal format and should be used for anything shared, maintained, or deployed repeatedly.

| Property | Packaged bundle | Legacy single-file plugin |
|---|---|---|
| Installed form | `$JROOT_HOME/plugins/<name>/` | `$JROOT_HOME/plugins/<name>.py` or `.sh` |
| `plugin.json` | Required | None |
| Hook filtering | Only hooks listed in `hooks` are dispatched | No manifest filtering; receives lifecycle dispatches |
| Dependency verification | Available | Not available |
| `plugin inspect` metadata | Manifest fields plus latest result | Entry point and `version: legacy` only |
| Recommended for | Maintained plugins | Short local scripts or migration only |

> **Recommendation:** Start with a packaged bundle even if your plugin has only one file. The manifest gives JRoot enough information to validate names, hook declarations, entrypoint paths, and host dependencies.

### Installation, update, removal, and backup

Installing an existing plugin name replaces the installed bundle after stopping any services with the same name. This is useful for updates, but it means a production plugin should keep any user-controlled settings and state outside the source bundle.

| Task | Command | Notes |
|---|---|---|
| Install or replace a bundle | `jroot plugin install ./my-plugin` | Validates the manifest and declared host requirements first. |
| List installed plugins | `jroot plugin list` | Shows name, version, and description. |
| Inspect manifest and last result | `jroot plugin inspect my-plugin` | Shows the last status record if one exists. |
| Validate installed plugin and dependencies | `jroot plugin verify my-plugin` | Use `all` to verify every installed packaged plugin. |
| Read recent output | `jroot plugin logs my-plugin` | Shows the last 50 log lines. |
| Follow output | `jroot plugin logs my-plugin --follow` | Runs `tail -f` against the plugin log. |
| Remove a plugin | `jroot plugin remove my-plugin` | Stops services and removes bundle, data, status, and logs. |

Before removing a plugin whose state matters, back up its data directory:

```bash
cp -a "$HOME/.jroot/plugins/data/my-plugin" ./my-plugin-state-backup
jroot plugin remove my-plugin
```

---

## 4. `plugin.json` manifest reference

The manifest is parsed by the JRoot installer and by `jroot-dev.py`. The runtime checks some fields strictly, while several fields are descriptive metadata.

### 4.1 Complete field table

| Field | Required by installer | Type and accepted form | How JRoot uses it |
|---|---:|---|---|
| `api_version` | Yes | Integer equal to `1` | Rejects incompatible bundle formats. |
| `name` | Yes | Lowercase identifier, 1–64 chars, matching `[a-z0-9][a-z0-9._-]{0,63}` | Bundle directory name, data/log/status namespace, direct command name. |
| `version` | Yes | Semantic Version string such as `1.2.0` | Displayed by `plugin list` and `plugin inspect`. |
| `entrypoint` | Yes | Relative `.py` or `.sh` path inside the bundle; cannot be absolute or contain `..` | Python files are run with `python3`; shell files are run with `bash`. |
| `hooks` | Yes | Unique array of names matching `on_[a-z][a-z0-9_]*` | Selects lifecycle events to receive; custom names are usable with services. |
| `description` | No | String recommended | Shown in `jroot plugin list`. |
| `author` | No | String recommended | Shown by `jroot plugin inspect` when present. |
| `permissions` | No | Array of strings | Descriptive manifest metadata; it is **not** a runtime sandbox or capability-enforcement mechanism. |
| `requires.commands` | No | Array of host command names containing letters, digits, `.`, `_`, `+`, or `-` | Checked during installation and `plugin verify`. |
| `requires.python` | No | String in the exact form `>=MAJOR.MINOR`, for example `>=3.8` | Checked against the host Python version during installation and verification. |

### 4.2 Name rules and reserved commands

Plugin names become JRoot commands, so they cannot overlap core commands. The following names are currently reserved:

```text
init enter exec shell install file sync limit bundle deploy monitor compose
port net mnt mount config list ls info history compare diff which size update
clean snapshot snapshots clone checkpoint checkpoints revert rm-snapshot rm-checkpoint
doctor rm delete rename kill stop ps ssh completion completions plugin help
data logs status registry
```

For example, `jail-audit`, `audit.log`, and `resource_watch` are valid names. `sync`, `MyPlugin`, `plugin!`, and `a name with spaces` are not.

### 4.3 Minimal valid manifest

```json
{
  "api_version": 1,
  "name": "hello-jroot",
  "version": "0.1.0",
  "entrypoint": "main.py",
  "hooks": ["on_init"]
}
```

This is enough for the JRoot installer. Add a description, author, permissions, and requirements when the plugin is intended to be shared or maintained by someone other than its author.

### 4.4 Requirement checks do not install dependencies

A declaration such as the following does **not** create a virtual environment or run `pip install`:

```json
"requires": {
  "python": ">=3.10",
  "commands": ["git", "curl"]
}
```

It only means that `jroot plugin install` and `jroot plugin verify` will fail if the host lacks an adequate `python3`, `git`, or `curl`. If a plugin needs third-party Python packages, document the installation procedure clearly and keep it under the host administrator's control.

---

## 5. Lifecycle hook reference

For a packaged plugin, JRoot calls only the lifecycle hooks listed in the manifest's `hooks` array. Each dispatch begins with `hook:<event-name>`.

### 5.1 Core hooks

| Hook | When it is dispatched | Exact argument shape after program name | Notes |
|---|---|---|---|
| `on_init` | A jail has completed initialization | `hook:on_init <jail> <image>` | Runs after a successful `jroot init`. |
| `on_enter` | A shell or command is about to launch | `hook:on_enter <jail> shell` or `hook:on_enter <jail> command` | It does **not** receive the actual command text. A failing hook does not veto the launch. |
| `on_stop` | `jroot kill` terminates a tracked jail | `hook:on_stop <jail> user-request` | Does not fire for every natural process exit. |
| `on_remove` | Jail removal has been confirmed | `hook:on_remove <jail>` | Runs before the rootfs is deleted. |
| `on_sync` | `jroot sync` completes successfully | `hook:on_sync <source> <destination>` | Source and destination are the user-facing JRoot path arguments. |
| `on_snapshot` | A snapshot or checkpoint is created or restored | See the state-event table below | One hook covers both storage mechanisms. |
| `on_limit` | Resource limits have been saved | `hook:on_limit <jail> mem=<v>,cpu=<v>,nofile=<v>` | Unchanged fields are represented as `unchanged`. |

### 5.2 Snapshot and checkpoint state event values

The second payload argument of `on_snapshot` identifies the exact operation.

| Operation | Invocation value |
|---|---|
| `jroot snapshot <name> <label>` | `create:<label>` |
| `jroot checkpoint <name> <label>` | `checkpoint-create:<label>` |
| `jroot revert snapshot <name> <label>` | `restore-snapshot:<label>` |
| `jroot revert checkpoint <name> <label>` | `restore-checkpoint:<label>` |

A correct handler should treat the value as a string protocol rather than assuming only ordinary snapshots exist:

```python
def on_snapshot(context, jail: str, action: str) -> None:
    if action.startswith("checkpoint-create:"):
        label = action.removeprefix("checkpoint-create:")
        context.log.info(f"Checkpoint created for {jail}: {label}")
    elif action.startswith("restore-"):
        context.log.info(f"Restored saved state for {jail}: {action}")
    else:
        context.log.info(f"Snapshot event for {jail}: {action}")
```

### 5.3 Custom hook names and services

Manifest hook names must have the `on_` prefix, but they do not have to be one of the core names above. A custom hook is not fired automatically by the JRoot runtime. It becomes useful when started as a service:

```json
"hooks": ["on_monitor", "on_export_metrics"]
```

```bash
jroot plugin service start metrics-agent on_monitor dev
jroot plugin service start metrics-agent on_export_metrics /tmp/jroot-metrics.txt
```

### 5.4 A safe hook router

Most plugins use one entrypoint for multiple hooks. Route each hook explicitly and check payload length before accessing it.

```python
import sys
from jroot_sdk import JRootContext


def main() -> int:
    context = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    args = sys.argv[2:]

    if action == "hook:on_init" and len(args) == 2:
        jail, image = args
        context.log.info(f"Created {jail} from {image}")
    elif action == "hook:on_sync" and len(args) == 2:
        source, destination = args
        context.log.info(f"Sync complete: {source} -> {destination}")
    elif action.startswith("hook:"):
        context.log.warn(f"Ignored unsupported hook or malformed payload: {action} {args!r}")
    else:
        print("This plugin has no direct command help yet.")

    return 0
```

---

## 6. Python SDK reference

Python plugins import the SDK as follows:

```python
from jroot_sdk import JRootContext

context = JRootContext()
```

JRoot prepares `PYTHONPATH` before executing packaged Python plugins. Do not copy the SDK into your bundle and do not change Python's import path manually in a normal JRoot hook.

### 6.1 `JRootContext` attributes

| Attribute | Meaning |
|---|---|
| `context.home` | JRoot home directory from `JROOT_HOME`. |
| `context.roots_dir` | Rootfs directory from `JROOT_ROOTS`. |
| `context.configs_dir` | Config directory from `JROOT_CONFIGS`. |
| `context.bin_dir` | Binary directory from `JROOT_BIN`. |
| `context.plugin_data` | Private data directory from `JROOT_PLUGIN_DATA`. |
| `context.plugin_name` | Current plugin name from `JROOT_PLUGIN_NAME`. |
| `context.log` | `Logger` instance for the current plugin. |

### 6.2 Jail inspection methods

| Method | Return value | Behaviour | Small example |
|---|---|---|---|
| `list_jails()` | `list[dict]` | Reads every JSON file in `configs_dir`. Each item includes `name`, `image`, `user`, `limit_mem`, `limit_cpu`, `limit_nofile`, `config_path`, and `rootfs_path`. | `for jail in context.list_jails(): print(jail["name"])` |
| `get_jail(name)` | `dict` or `None` | Reads `<name>.json`, adds `name` and `rootfs_path`, or returns `None` if absent. | `cfg = context.get_jail("dev")` |
| `run_in_jail(name, command)` | `(exit_code, stdout, stderr)` | Invokes `jroot exec <name> /bin/sh -c <command>` with the launcher bound by the runtime. | `code, out, err = context.run_in_jail("dev", "id")` |

Check the exit code returned by `run_in_jail`; the SDK intentionally does not raise on a command that exits non-zero.

```python
code, stdout, stderr = context.run_in_jail("dev", "test -f /etc/os-release")
if code == 0:
    context.log.info("dev is a Linux rootfs")
else:
    context.log.error(stderr.strip() or "jail command failed")
```

### 6.3 Resource telemetry

`get_resource_usage(name)` observes the tracked host-side launcher PIDs reported by `jroot ps --json`. It is useful for dashboards and logging, but it is not cgroup accounting and should not be treated as a kernel-enforced aggregate container limit.

| Key | Type | Meaning |
|---|---|---|
| `mem_bytes` | Integer | Sum of observed resident memory for tracked launcher PIDs. |
| `mem_mb` | Float | `mem_bytes` converted to MiB and rounded to two decimals. |
| `cpu_seconds` | Float | Cumulative user and system CPU time observed from `/proc`. |
| `pids` | Integer | Number of tracked live launcher PIDs contributing to the result. |

If no process is currently tracked for the jail, the SDK returns zero-valued telemetry. If it cannot query JRoot or parse process data, it writes an error log and returns `None`.

```python
usage = context.get_resource_usage("dev")
if usage is None:
    context.log.warn("Telemetry unavailable")
elif usage["pids"] == 0:
    context.log.info("dev is not currently tracked as running")
else:
    context.log.info(f"dev: {usage['mem_mb']} MiB RSS, {usage['cpu_seconds']} CPU seconds")
```

### 6.4 Plugin state methods

State is JSON stored beneath the current plugin's private directory. The write operation is atomic for a single final-file replacement: the SDK writes `<filename>.tmp` and then replaces the original file.

| Method | Behaviour | Use it for |
|---|---|---|
| `read_plugin_state(filename="state.json", default=None)` | Parses JSON. Returns the supplied default if the file is missing or unreadable. | Counters, small audit records, user-supplied JSON configuration. |
| `write_plugin_state(data, filename="state.json")` | Serializes JSON with indentation and atomically replaces the final path. | Persisting a complete new state value. |

```python
state = context.read_plugin_state("settings.json", {
    "warning_memory_mb": 512,
    "notifications_enabled": False,
})
state["notifications_enabled"] = True
context.write_plugin_state(state, "settings.json")
```

> **Concurrency note:** Atomic replacement prevents a partial JSON file, but it does not lock a read-modify-write cycle. Two simultaneous hook processes can still overwrite each other's independently updated copy. Keep state updates simple, use one writer where possible, or use an external store if strict multi-writer consistency is needed.

### 6.5 Logging methods

`context.log` writes timestamped lines to standard output. JRoot captures both standard output and standard error in the plugin log.

| Method | Typical use |
|---|---|
| `context.log.info(message)` | Normal operation, state changes, successful work. |
| `context.log.warn(message)` | Recoverable condition, skipped work, unexpected but safe input. |
| `context.log.error(message)` | Failed command, invalid state, external dependency failure. |
| `context.log.debug(message)` | Verbose internal diagnostics. |

Do not write credentials, access tokens, private keys, or raw sensitive file content to the log. Plugin logs are normal host-user files and are not encrypted.

---

## 7. Runtime environment

JRoot exports the following variables to a packaged plugin during a hook, direct invocation, or service startup.

| Variable | Value | Why it matters |
|---|---|---|
| `JROOT_HOME` | Current JRoot home directory | Lets the SDK find the runtime tree. |
| `JROOT_ROOTS` | `$JROOT_HOME/roots` | Root filesystem directory. |
| `JROOT_CONFIGS` | `$JROOT_HOME/configs` | Jail JSON configuration directory. |
| `JROOT_BIN` | `$JROOT_HOME/bin` | JRoot binary directory. |
| `JROOT_PLUGIN_API` | Current API number, presently `1` | Allows a plugin to record the runtime API it was started under. |
| `JROOT_PLUGIN_NAME` | Installed plugin name | Used by `JRootContext` and logger labels. |
| `JROOT_PLUGIN_EVENT` | Event name without `hook:` | Set during hook and service invocation. |
| `JROOT_PLUGIN_DATA` | `$JROOT_HOME/plugins/data/<name>` | Plugin-owned JSON or other private files. |
| `JROOT_PLUGIN_LOG` | `$JROOT_HOME/plugins/logs/<name>.log` | Log file selected by the runtime. |
| `JROOT_COMMAND` | A command prefix pointing at the active JRoot launcher | Used internally by SDK subprocess helpers, preventing an older `jroot` on `PATH` from being selected. |
| `PYTHONPATH` | Includes `$JROOT_HOME/sdk` for Python plugins | Makes `from jroot_sdk import JRootContext` work. |

A shell plugin can use these variables directly:

```bash
#!/usr/bin/env bash
set -eu

echo "plugin=$JROOT_PLUGIN_NAME event=$JROOT_PLUGIN_EVENT" >> "$JROOT_PLUGIN_DATA/events.log"
```

---

## 8. Direct plugin commands

A packaged plugin name can act as a JRoot command when it does not collide with a core command. JRoot passes any remaining arguments directly to the entrypoint.

For a plugin named `jail-audit`:

```bash
jroot jail-audit
jroot jail-audit summary
jroot jail-audit tail 20
```

This is different from `jroot plugin inspect jail-audit`, which is a core management command that displays manifest and runtime status rather than executing plugin-defined behaviour.

### A direct-command router

```python
import sys
from jroot_sdk import JRootContext


def main() -> int:
    context = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else "summary"

    if action.startswith("hook:"):
        # Lifecycle routing belongs here.
        return 0
    if action == "summary":
        state = context.read_plugin_state("events.json", {"events": []})
        print(f"Recorded events: {len(state['events'])}")
        return 0
    if action == "help":
        print("Usage: jroot jail-audit [summary|help]")
        return 0

    print(f"Unknown command: {action}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
```

Treat direct-command input as untrusted user input. Validate names, labels, and paths before interpolating any values into a command passed to `run_in_jail`.

---

## 9. Background plugin services

A plugin service is a single background child process managed with a PID file under `$JROOT_HOME/pids/`. The service can use any declared `on_...` hook, including a custom name such as `on_monitor`.

### 9.1 Starting, checking, and stopping

```bash
# Start a monitor process for jail dev.
jroot plugin service start jail-audit on_monitor dev

# Print hook name, PID, and running/stale state.
jroot plugin service status jail-audit

# Stop one service hook.
jroot plugin service stop jail-audit on_monitor

# Stop all running services for this plugin.
jroot plugin service stop jail-audit
```

A service must stay alive itself. JRoot confirms that it survived initial startup, writes a PID file, and records a `running` status. It does not restart a service that exits later.

### 9.2 Minimal service implementation

```python
import sys
import time
from jroot_sdk import JRootContext


def monitor(context: JRootContext, jail: str) -> int:
    context.log.info(f"monitor started for {jail}")
    while True:
        usage = context.get_resource_usage(jail)
        if usage is None:
            context.log.warn("could not collect telemetry")
        else:
            context.log.debug(f"{jail}: {usage['mem_mb']} MiB, {usage['pids']} tracked PID(s)")
        time.sleep(30)


def main() -> int:
    context = JRootContext()
    if sys.argv[1:2] == ["hook:on_monitor"]:
        if len(sys.argv) < 3:
            context.log.error("on_monitor requires a jail name")
            return 2
        return monitor(context, sys.argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Keep the polling interval reasonable. A tight loop that calls `jroot ps --json` continuously wastes host CPU and produces a noisy log.

---

## 10. Development, testing, and installation workflow

`jroot-dev.py` is a cross-platform development helper. It deliberately does not run JRoot itself; instead it creates a temporary mock JRoot home and executes the plugin entrypoint with fixture payloads. It supports Python plugins on Windows, macOS, and Linux. Shell-plugin simulation requires `bash` (for example WSL or Git Bash on Windows).

### 10.1 Development helper command reference

| Command | Purpose | What it does not prove |
|---|---|---|
| `python3 jroot-dev.py init <directory>` | Create a template bundle | It does not install anything into JRoot. |
| `python3 jroot-dev.py validate [path]` | Validate manifest syntax and entrypoint presence | It does not check third-party Python imports or host commands. |
| `python3 jroot-dev.py validate --strict [path]` | Reject legacy manifests lacking modern API metadata | It still runs only local validation. |
| `python3 jroot-dev.py simulate <hook> --path <path>` | Run one hook in a temporary mock runtime | It does not start PRoot or use your real JRoot state. |
| `python3 jroot-dev.py simulate <hook> <args...> --path <path>` | Test a custom payload | Use this for edge cases such as unusual labels or paths. |
| `python3 jroot-dev.py test <path>` | Run every declared hook against fixtures | A long-running service hook should not be declared for this test unless it exits. |

The helper gives each simulation a default timeout of ten seconds. Override it with `--timeout` when testing a legitimately slower handler:

```bash
python3 jroot-dev.py simulate on_sync host:/project dev:/root/project \
  --path ./jail-audit --timeout 20
```

### 10.2 Suggested development sequence

| Step | Command | Expected result |
|---:|---|---|
| 1 | `python3 jroot-dev.py init jail-audit` | Creates template files. |
| 2 | Edit `plugin.json` and `main.py` | Implement only the hooks you need. |
| 3 | `python3 jroot-dev.py validate --strict jail-audit` | Catch manifest and entrypoint problems. |
| 4 | `python3 jroot-dev.py simulate on_limit --path jail-audit` | Confirm one exact payload route. |
| 5 | `python3 jroot-dev.py test jail-audit` | Exercise every declared non-service hook. |
| 6 | `jroot plugin install ./jail-audit` | Install on a real JRoot host. |
| 7 | `jroot plugin verify jail-audit` | Re-check manifest and declared host dependencies. |
| 8 | Trigger a real JRoot operation | Validate output with `plugin logs`, `plugin inspect`, and stored state. |

### 10.3 Real-host verification checklist

Mock tests are useful, but they cannot test the PRoot command path, the active `JROOT_COMMAND` launcher binding, or real file synchronization. Before publishing a plugin, perform an end-to-end pass against an existing safe jail.

```bash
# Inspect plugin installation and declared hooks.
jroot plugin inspect jail-audit
jroot plugin verify jail-audit

# Trigger a real hook.
jroot limit dev --mem=256M --cpu=30 --nofile=1024

# Read its output and state.
jroot plugin logs jail-audit
jroot jail-audit summary

# If the plugin has a service, test its lifecycle too.
jroot plugin service start jail-audit on_monitor dev
jroot plugin service status jail-audit
jroot plugin service stop jail-audit on_monitor
```

---

## 11. Reliability, ordering, and current limits

### 11.1 Failure handling

JRoot appends plugin output to a log and writes a per-plugin JSON status record for every dispatch. If a hook exits non-zero, JRoot prints a warning naming the plugin and hook, but continues executing the core JRoot operation. This behaviour protects normal jail operations from optional extension failures.

| Situation | Core JRoot operation | Plugin status | Where to look |
|---|---|---|---|
| Hook exits `0` | Continues normally | `ok`, exit code `0` | `jroot plugin inspect <name>` |
| Hook exits non-zero | Continues normally | `failed`, non-zero exit code | `jroot plugin logs <name>` |
| Python import fails | Continues normally after warning | `failed` | `jroot plugin logs <name>` |
| Service exits during startup | Start command fails | `failed` | `jroot plugin logs <name>` |
| Service exits after startup | Core JRoot continues | PID becomes stale when status is checked | `jroot plugin service status <name>` |

### 11.2 Ordering

Do not build a correctness requirement around the order in which multiple plugins observe a given hook. Keep each plugin idempotent where possible: if the same sync or limit event is handled twice, the state should remain valid.

### 11.3 Keep lifecycle hooks short

Normal hooks run synchronously from the JRoot command that triggered them. Do not perform a ten-minute build or an unbounded network request in `on_sync` or `on_enter`. Prefer one of these designs instead:

| Need | Better pattern |
|---|---|
| Record an event for later work | Save a small JSON job record with `write_plugin_state`. |
| Poll a resource or external system | Start a service with `plugin service start`. |
| Run a one-off expensive job | Start a deliberately detached host process from the plugin only if you can log and clean it up responsibly. |
| Notify an external system | Use a short network timeout and tolerate delivery failure. |

### 11.4 State consistency

A plugin may be invoked from two different JRoot commands close together. Atomic state writes preserve parseable JSON, but a read-modify-write workflow is still susceptible to lost updates. For counters that must be exact, use a service as the single writer or an external database designed for concurrent access.

---

## 12. Troubleshooting

### 12.1 Installation and validation problems

| Symptom | Likely cause | Fix |
|---|---|---|
| `Missing plugin.json manifest file.` | You passed a directory that is not a packaged bundle. | Add `plugin.json`, or install a deliberate legacy `.py`/`.sh` script. |
| `name must be a lowercase identifier...` | Uppercase letters, spaces, or unsupported characters in `name`. | Use a name like `jail-audit` or `resource_watch`. |
| `name 'sync' is reserved by jroot.` | Plugin collides with a core command. | Rename the plugin; do not shadow JRoot commands. |
| `entrypoint must end in .py or .sh.` | Unsupported entrypoint extension. | Use a Python or POSIX shell file. |
| `entrypoint ... does not exist.` | Manifest path does not match bundle contents. | Correct the relative `entrypoint` path. |
| `Plugin dependency missing: 'git'.` | A required host command is not on `PATH`. | Install the host command or remove it from `requires.commands` if it is not genuinely required. |
| `Plugin requires Python >= ...` | Host Python is too old. | Upgrade Python or lower the stated requirement after testing compatibility. |

### 12.2 Runtime problems

| Symptom | Likely cause | Fix |
|---|---|---|
| `ModuleNotFoundError: No module named 'jroot_sdk'` | Running `main.py` directly outside JRoot, or an incomplete old installation. | Use `jroot-dev.py` for local simulation; on the host, rerun the JRoot installer or set `JROOT_SDK_SOURCE` to a valid `jroot_sdk.py` source for a portable runtime. |
| Hook never appears in logs | Hook missing from `hooks`, or the triggering JRoot command did not complete successfully. | Add the hook to the manifest, reinstall, then use `jroot plugin inspect` and perform the operation again. |
| `on_enter` cannot see the original command | This is the current hook contract. | Treat `shell`/`command` as mode metadata only; do not design a command-filtering plugin around it. |
| Plugin action fails but JRoot command succeeds | JRoot isolates extension failure from core operations. | Inspect `jroot plugin logs <name>` and the last result from `jroot plugin inspect <name>`. |
| Plugin service is `stale` | Process stopped or crashed after startup. | Read the log, correct the error, then start the service again. |
| Direct command says unknown command | The plugin is not installed, name differs from the manifest, or a core command has the same name. | Check `jroot plugin list`; use the manifest name exactly. |

### 12.3 State and log problems

| Symptom | Likely cause | Fix |
|---|---|---|
| `JSONDecodeError` in your own code | State was read directly and is malformed. | Use `read_plugin_state(filename, default)` and validate the returned value. |
| State disappears after uninstall | `jroot plugin remove` deliberately removes plugin data. | Back up `$JROOT_HOME/plugins/data/<name>/` before removal. |
| Log is empty | Hook has not run, or plugin only writes state and never logs. | Trigger a known event and add `context.log.info()` at the beginning of the handler while debugging. |
| Sensitive values appear in log | Plugin logged secrets, shell command lines, or full external responses. | Rotate credentials if necessary and remove sensitive logging from the plugin. |

---

## 13. Full example: `jail-audit`

This example is intentionally complete rather than clever. It records core lifecycle events, stores a bounded history in plugin-owned JSON, exposes a direct report command, and keeps the hook router explicit. It has no third-party dependencies and is suitable for local mock tests followed by a real installed run.

### 13.1 Directory layout

```text
jail-audit/
├── plugin.json
└── main.py
```

### 13.2 `plugin.json`

```json
{
  "api_version": 1,
  "name": "jail-audit",
  "version": "1.0.0",
  "description": "Records JRoot jail lifecycle events in plugin-owned JSON state.",
  "author": "Example maintainer",
  "entrypoint": "main.py",
  "hooks": [
    "on_init",
    "on_enter",
    "on_stop",
    "on_remove",
    "on_sync",
    "on_snapshot",
    "on_limit"
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

### 13.3 `main.py`

```python
#!/usr/bin/env python3
"""A complete lifecycle audit plugin for JRoot."""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from typing import Any

from jroot_sdk import JRootContext


STATE_FILE = "audit.json"
MAX_EVENTS = 250


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_state(context: JRootContext) -> dict[str, Any]:
    state = context.read_plugin_state(STATE_FILE, {"events": []})
    # A defensive type check makes manually corrupted state recoverable.
    if not isinstance(state, dict) or not isinstance(state.get("events"), list):
        context.log.warn("Audit state had an unexpected shape; starting a fresh event list")
        return {"events": []}
    return state


def record(context: JRootContext, event: str, payload: dict[str, str]) -> None:
    state = load_state(context)
    state["events"].append({
        "timestamp": timestamp(),
        "event": event,
        "payload": payload,
    })
    # Bound the history so an active plugin does not grow forever.
    state["events"] = state["events"][-MAX_EVENTS:]
    context.write_plugin_state(state, STATE_FILE)
    context.log.info(f"recorded {event}: {payload}")


def handle_hook(context: JRootContext, hook: str, args: list[str]) -> int:
    if hook == "on_init":
        if len(args) != 2:
            context.log.error("on_init expected <jail> <image>")
            return 2
        record(context, hook, {"jail": args[0], "image": args[1]})

    elif hook == "on_enter":
        if len(args) != 2:
            context.log.error("on_enter expected <jail> <shell|command>")
            return 2
        record(context, hook, {"jail": args[0], "mode": args[1]})

    elif hook == "on_stop":
        if len(args) != 2:
            context.log.error("on_stop expected <jail> <reason>")
            return 2
        record(context, hook, {"jail": args[0], "reason": args[1]})

    elif hook == "on_remove":
        if len(args) != 1:
            context.log.error("on_remove expected <jail>")
            return 2
        record(context, hook, {"jail": args[0]})

    elif hook == "on_sync":
        if len(args) != 2:
            context.log.error("on_sync expected <source> <destination>")
            return 2
        record(context, hook, {"source": args[0], "destination": args[1]})

    elif hook == "on_snapshot":
        if len(args) != 2:
            context.log.error("on_snapshot expected <jail> <action>")
            return 2
        record(context, hook, {"jail": args[0], "action": args[1]})

    elif hook == "on_limit":
        if len(args) != 2:
            context.log.error("on_limit expected <jail> <limits>")
            return 2
        record(context, hook, {"jail": args[0], "limits": args[1]})

    else:
        context.log.warn(f"Ignoring unsupported hook: {hook}")

    return 0


def print_summary(context: JRootContext, requested: int) -> int:
    state = load_state(context)
    events = state["events"][-requested:]
    print(f"JRoot audit events: {len(state['events'])}")
    if not events:
        print("No events recorded yet.")
        return 0
    for item in events:
        payload = ", ".join(f"{key}={value}" for key, value in item["payload"].items())
        print(f"{item['timestamp']}  {item['event']:<12}  {payload}")
    return 0


def print_help() -> int:
    print("Usage: jroot jail-audit [summary [count]|help]")
    print("  summary [count]  Print recent audit entries (default: 10).")
    print("  help             Show this message.")
    return 0


def handle_direct_command(context: JRootContext, args: list[str]) -> int:
    command = args[0] if args else "summary"
    if command == "summary":
        count = 10
        if len(args) > 1:
            try:
                count = max(1, min(int(args[1]), MAX_EVENTS))
            except ValueError:
                print("count must be an integer", file=sys.stderr)
                return 2
        return print_summary(context, count)
    if command in {"help", "--help", "-h"}:
        return print_help()

    print(f"unknown jail-audit command: {command}", file=sys.stderr)
    return print_help() or 2


def main() -> int:
    context = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    if action.startswith("hook:"):
        return handle_hook(context, action.split(":", 1)[1], sys.argv[2:])

    return handle_direct_command(context, sys.argv[1:])


if __name__ == "__main__":
    raise SystemExit(main())
```

### 13.4 Validate it locally

From the JRoot repository root, run:

```bash
python3 jroot-dev.py validate --strict ./jail-audit
python3 jroot-dev.py simulate on_limit --path ./jail-audit
python3 jroot-dev.py test ./jail-audit
```

The final command runs the seven declared hooks with their built-in fixture arguments. Because this bundle does not declare a long-running service hook, the test suite can complete normally.

### 13.5 Install and exercise it on a real host

```bash
jroot plugin install ./jail-audit
jroot plugin verify jail-audit
jroot plugin inspect jail-audit

# Trigger real supported events with an existing jail named dev.
jroot limit dev --mem=256M --cpu=30 --nofile=1024
jroot sync ./project dev:/root/project
jroot snapshot dev before-change

# Read the plugin's output and report.
jroot plugin logs jail-audit
jroot jail-audit summary
jroot jail-audit summary 25
```

### 13.6 What to inspect when adapting the example

| Change you want | Change in `plugin.json` | Change in `main.py` |
|---|---|---|
| Track only limit changes | Leave only `on_limit` in `hooks` | Keep only the `on_limit` branch. |
| Record checkpoint details separately | Keep `on_snapshot` | Split `action` using `checkpoint-create:` and `restore-checkpoint:` prefixes. |
| Add an external notification | Add the required host command only if you actually use one | Use a short timeout, log failures, and do not put API credentials in logs. |
| Add a background monitor | Add `on_monitor` | Add a separate infinite-loop service handler; do not include it in a development-helper `test` run unless it exits. |
| Keep more history | No manifest change | Raise `MAX_EVENTS` or move high-volume data to an external store. |

This is the intended plugin-development shape: understand the event contract, declare only the hooks you need, validate with the local helper, then confirm behaviour against a real existing jail.
