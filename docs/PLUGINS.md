# JRoot Plugin Development Guide

This guide takes you from an empty directory to a tested JRoot plugin. It explains what the runtime actually passes to a plugin, how to persist state safely, how to test on Windows before a Linux deployment, and how to debug a plugin after installation.

A JRoot plugin is **host-side code**. It can react to jail lifecycle events, expose one custom top-level command, keep private state, and optionally run as a managed background process. A standard packaged plugin is a directory containing a `plugin.json` manifest and either a Python or POSIX shell entry point.

> **Trust boundary:** JRoot starts plugins with the permissions of the host user who runs `jroot`. A manifest describes compatibility, dependencies, and expected access, but it does **not** sandbox code. Read a plugin and its dependencies before installation; do not treat `permissions` as a security boundary.

## What you will build

The walkthrough builds `jail-audit`, a small plugin that records when a jail is created or its limits are changed. It demonstrates the important pieces of the API without needing root, PRoot, a network connection, or a long-running service.

```text
jail-audit/
├── plugin.json       # Runtime contract and metadata
└── main.py           # Hook handler and custom-command entry point
```

The final plugin will be able to:

```bash
# Triggered by JRoot after a new jail has been created.
jroot init ubuntu:22.04 --name=demo

# Triggered by JRoot after resource limits are saved.
jroot limit demo --mem=256M --nofile=512

# Runs the plugin directly as a custom JRoot command.
jroot jail-audit
```

## Before you start

On a Linux host that runs JRoot, use the current installer or `make install`; both install the Python SDK at `$JROOT_HOME/sdk/jroot_sdk.py`. For development from a repository checkout, keep these files together:

```text
jroot-dev.py
jroot_sdk.py
jroot
```

The development helper needs Python 3.8 or newer and no third-party packages. On Windows, start with the dedicated [Windows development tutorial](WINDOWS_DEV.md).

## 1. Generate a starter plugin

From a repository checkout, create a new directory with the cross-platform helper:

```bash
python3 jroot-dev.py init jail-audit
cd jail-audit
```

On a Linux machine with JRoot installed, the equivalent starter can be generated with:

```bash
jroot plugin init-sdk
mv jroot-plugin-template jail-audit
cd jail-audit
```

Both routes create a packaged plugin rather than a legacy single-file extension. Packaged plugins are the recommended format because JRoot can validate their API version, entry point, declared hooks, and host dependencies before installation.

## 2. Write the manifest

Replace the generated `plugin.json` with the following manifest:

```json
{
  "api_version": 1,
  "name": "jail-audit",
  "version": "0.1.0",
  "description": "Records jail creation and resource-limit changes.",
  "author": "Your name",
  "entrypoint": "main.py",
  "hooks": ["on_init", "on_limit"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": []
  }
}
```

The runtime validates every required field when you install or verify a packaged plugin.

| Field | Why it exists | Practical rule |
|---|---|---|
| `api_version` | Prevents a plugin written for one runtime contract being loaded by another. | Use the integer `1` today. |
| `name` | Identifies the installed plugin and becomes its custom top-level command. | Use lowercase letters, digits, `.`, `_`, or `-`; `jroot`, `init`, `sync`, and other built-ins are reserved. |
| `version` | Identifies the plugin release. | Use Semantic Versioning such as `0.1.0` or `1.2.0`. |
| `entrypoint` | Tells JRoot which file to execute. | Keep it relative to the plugin directory; it must be a `.py` or `.sh` file. |
| `hooks` | Limits event delivery to events the plugin explicitly supports. | List only handlers implemented by the entry point. |
| `permissions` | Documents expected behavior for a reviewer. | Treat it as honest disclosure, not enforced isolation. |
| `requires.python` | Declares a minimum host Python version. | Use `>=MAJOR.MINOR`, such as `>=3.8`. |
| `requires.commands` | Declares host commands the plugin will execute. | Use host command names, for example `["curl", "jq"]`; installation fails if one is unavailable. |

The `name` is important: a plugin named `jail-audit` can be invoked as `jroot jail-audit`. JRoot rejects names that would shadow its own commands.

## 3. Implement a useful Python plugin

Create `main.py` with this complete example:

```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext


def increment_counter(context: JRootContext, key: str) -> int:
    """Keep one durable counter in this plugin's private state directory."""
    state = context.read_plugin_state("audit.json", {"events": {}})
    events = state.setdefault("events", {})
    events[key] = events.get(key, 0) + 1
    context.write_plugin_state(state, "audit.json")
    return events[key]


def on_init(context: JRootContext, jail: str, image: str) -> None:
    count = increment_counter(context, "created")
    context.log.info(f"recorded jail creation: jail={jail} image={image} count={count}")


def on_limit(context: JRootContext, jail: str, limits: str) -> None:
    count = increment_counter(context, "limits_changed")
    context.log.info(f"recorded limit change: jail={jail} {limits} count={count}")


def print_summary(context: JRootContext) -> None:
    """This path is used when a person runs: jroot jail-audit"""
    state = context.read_plugin_state("audit.json", {"events": {}})
    print("Recorded audit events:")
    for event, count in sorted(state.get("events", {}).items()):
        print(f"  {event}: {count}")


def main() -> int:
    context = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    # Hook invocations always begin with hook:<event-name>.
    if action == "hook:on_init":
        jail, image = sys.argv[2:4]
        on_init(context, jail, image)
    elif action == "hook:on_limit":
        jail, limits = sys.argv[2:4]
        on_limit(context, jail, limits)
    else:
        # Any direct call such as `jroot jail-audit` reaches this branch.
        print_summary(context)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

There are three ideas worth noticing. First, the handler checks the exact hook name instead of assuming every invocation is an event. Second, it stores only JSON data under `JROOT_PLUGIN_DATA`, which JRoot creates separately for every plugin. Finally, it uses `context.log`, so messages land in the plugin log rather than relying on an interactive terminal.

## 4. Understand event payloads

JRoot passes an event selector as argument one and the documented payload after it. The selectors and payloads below are the stable API version 1 contract.

| Hook | When JRoot calls it | Invocation shape | Typical use |
|---|---|---|---|
| `on_init` | A jail is successfully provisioned. | `hook:on_init <jail> <image>` | Record inventory, initialize per-jail metadata. |
| `on_enter` | A shell or command is about to start. | `hook:on_enter <jail> <shell\|command>` | Audit usage or enforce a team convention. |
| `on_stop` | `jroot kill` terminates a tracked jail. | `hook:on_stop <jail> user-request` | Clear external leases or record shutdown. |
| `on_remove` | Removal is confirmed, before the rootfs is deleted. | `hook:on_remove <jail>` | Archive external metadata; do not expect the rootfs to survive. |
| `on_sync` | `jroot sync` completes. | `hook:on_sync <source> <destination>` | Start a build, index a workspace, or record deployment input. |
| `on_snapshot` | A snapshot or checkpoint is created or restored. | `hook:on_snapshot <jail> create:<label>`, `restore:<label>`, `checkpoint-create:<label>`, or `restore-checkpoint:<label>` | Track restore points or inform an external inventory. |
| `on_limit` | Resource settings are saved. | `hook:on_limit <jail> mem=<value>,cpu=<value>,nofile=<value>` | Store governance changes or notify an operator. |
| Custom `on_*` | You start it as a plugin service. | `hook:on_monitor <arguments...>` | Run an explicit long-lived worker. |

For example, this is what the `on_limit` handler sees:

```text
sys.argv == [
  "main.py",
  "hook:on_limit",
  "demo",
  "mem=256M,cpu=unchanged,nofile=512"
]
```

A packaged plugin receives only hooks declared in its `hooks` array. If `on_sync` is not in the manifest, JRoot does not start that plugin for a sync operation.

## 5. Validate and test before installation

Validate the file structure, manifest, and Python syntax:

```bash
python3 jroot-dev.py validate --strict jail-audit
```

Then run one event with a mock JRoot environment:

```bash
python3 jroot-dev.py simulate on_init --path jail-audit
```

The standard `on_init` fixture is equivalent to this payload:

```text
hook:on_init sample-jail ubuntu:22.04
```

You can supply your own payload to test parsing logic:

```bash
python3 jroot-dev.py simulate on_limit demo mem=256M,cpu=60,nofile=512 --path jail-audit
```

Finally, exercise every hook listed in `plugin.json`:

```bash
python3 jroot-dev.py test jail-audit
```

The helper creates a temporary `$JROOT_HOME`, one `sample-jail` configuration, and a temporary `$JROOT_PLUGIN_DATA` directory. It returns non-zero on a Python syntax error, a malformed manifest, a handler crash, a non-zero handler exit, or a timeout. This makes it suitable for local pre-commit checks and Windows development.

## 6. Install and use the plugin on Linux

Copy the validated directory to the Linux machine that runs JRoot, then install it from the directory containing `plugin.json`:

```bash
jroot plugin install ./jail-audit
jroot plugin verify jail-audit
jroot plugin inspect jail-audit
```

A successful inspection shows the version, entry point, declared hooks, permissions, and most recent hook result. Trigger the example in normal JRoot use:

```bash
jroot init ubuntu:22.04 --name=demo
jroot limit demo --mem=256M --nofile=512
jroot jail-audit
```

View the handler output at any time:

```bash
jroot plugin logs jail-audit
jroot plugin logs jail-audit --follow
```

The runtime writes logs to `$JROOT_HOME/plugins/logs/jail-audit.log`, state to `$JROOT_HOME/plugins/data/jail-audit/`, and the latest execution result to `$JROOT_HOME/plugins/status/jail-audit.json`.

## Using the SDK deliberately

`JRootContext` is small on purpose. It offers the parts of JRoot a plugin commonly needs without making plugin code parse JRoot’s internal directory layout.

| SDK member | What it returns or does | Example |
|---|---|---|
| `list_jails()` | Configuration summaries for all jails. | `for jail in context.list_jails(): print(jail["name"])` |
| `get_jail(name)` | One jail configuration or `None`. | `config = context.get_jail("demo")` |
| `read_plugin_state(file, default)` | JSON stored in the plugin-private directory. | `state = context.read_plugin_state("state.json", {})` |
| `write_plugin_state(data, file)` | Atomically saves JSON plugin state. | `context.write_plugin_state(state, "state.json")` |
| `log.info/warn/error/debug` | Writes timestamped output captured by JRoot. | `context.log.warning("threshold exceeded")` |
| `get_resource_usage(jail)` | Observed RSS, CPU seconds, and tracked launcher process count. | `usage = context.get_resource_usage("demo")` |
| `run_in_jail(jail, command)` | Runs `jroot exec` and returns `(exit_code, stdout, stderr)`. | `code, out, err = context.run_in_jail("demo", "id")` |

### Resource observations are not cgroups

`get_resource_usage()` is useful for auditing or a best-effort monitor, but it is not kernel aggregate accounting. In a rootless PRoot deployment it observes the tracked launcher processes exposed by `jroot ps --json`; it cannot provide a cgroup-like enforcement boundary or a guaranteed instantaneous CPU percentage. Use `jroot limit` for JRoot’s configured process limits, and treat SDK observations as telemetry.

### Execute inside a jail only when necessary

`run_in_jail()` is powerful because it starts a host-side `jroot exec` command. Prefer reading configuration or state when that is enough. If you need to execute a command, quote fixed commands carefully and do not pass untrusted text into a shell command string.

```python
# Good: fixed command with a known jail name selected by your plugin.
code, output, error = context.run_in_jail("demo", "id -u")

# Risky: never concatenate untrusted user input into this shell string.
# context.run_in_jail("demo", "apt install " + user_supplied_package)
```

## Writing a shell plugin

Python is recommended for stateful logic, but a small shell plugin can be clearer for simple tasks. Change the manifest entry point to `main.sh`, declare `on_sync`, and use a handler such as:

```bash
#!/usr/bin/env bash
set -eu

case "${1:-}" in
  hook:on_sync)
    source_path="$2"
    destination_path="$3"
    printf 'sync completed: %s -> %s\n' "$source_path" "$destination_path"
    ;;
  *)
    printf 'Usage: jroot sync-note is invoked by jroot sync.\n'
    ;;
esac
```

The plugin output is captured exactly as it is for Python plugins. Keep shell plugins small and avoid `eval`, unquoted expansions, or building commands from untrusted arguments.

## Background services

A service is a plugin process that JRoot starts in the background and tracks with a PID file. It is suitable for a deliberate long-running task, such as sampling telemetry, polling a local queue, or periodically synchronizing an external inventory.

First declare the custom hook in the manifest:

```json
"hooks": ["on_monitor"]
```

Then start and manage it:

```bash
jroot plugin service start jail-audit on_monitor demo
jroot plugin service status jail-audit
jroot plugin service stop jail-audit on_monitor
```

JRoot prevents two active services with the same plugin and hook, captures output in the normal plugin log, and stops managed services before it removes the plugin. A service is **not** automatically restarted after a crash or after host reboot. Write a process that exits clearly on failure, use `jroot plugin logs` to diagnose it, and use a host service manager if you need restart guarantees.

A safe service loop checks its own stop conditions and sleeps between work; it should not busy-loop:

```python
import sys
import time
from jroot_sdk import JRootContext

context = JRootContext()
jail = sys.argv[2]
while True:
    usage = context.get_resource_usage(jail)
    context.log.info(f"usage for {jail}: {usage}")
    time.sleep(60)
```

Do not add this loop to a plugin that you expect `jroot-dev.py test` to finish immediately. Keep service code behind a dedicated `hook:on_monitor` branch and test the normal hooks separately, or use a short test-only mode.

## Operational commands

| Command | When to use it |
|---|---|
| `jroot plugin list` | Check what is installed. Runtime `data`, `logs`, and `status` directories are excluded. |
| `jroot plugin inspect <name>` | Read manifest metadata and the last recorded result. |
| `jroot plugin verify <name\|all>` | Recheck a deployed plugin after host Python or command dependencies change. |
| `jroot plugin logs <name> [--follow]` | Read stdout, stderr, tracebacks, and hook separators. |
| `jroot plugin service start <name> <hook> [args...]` | Start a declared custom service hook. |
| `jroot plugin service status <name>` | Inspect tracked service PIDs. |
| `jroot plugin service stop <name> [hook]` | Stop one service or all services owned by the plugin. |
| `jroot plugin remove <name>` | Stop services, remove the bundle, state, status, and logs. |

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `plugin manifest error: api_version must be 1` | The plugin targets an unsupported contract or omitted the field. | Add `"api_version": 1` and validate with `--strict`. |
| `entrypoint ... does not exist` | `entrypoint` does not match the filename inside the bundle. | Correct the path; it must stay inside the plugin directory. |
| A hook never appears in the log | The event is not declared, or the corresponding JRoot operation did not complete. | Check `hooks`, run `jroot plugin inspect <name>`, then reproduce the operation. |
| A plugin prints nothing in the terminal | Hook output is intentionally captured. | Run `jroot plugin logs <name>` or `--follow`. |
| `ModuleNotFoundError: jroot_sdk` on Linux | The SDK was not installed with the JRoot release. | Re-run the current installer or `make install`; confirm `$JROOT_HOME/sdk/jroot_sdk.py` exists. |
| Service is immediately `stale` | The handler exited or crashed during startup. | Read `jroot plugin logs <name>`; run the handler through `jroot-dev.py simulate` when applicable. |
| Installation rejects a dependency | `requires.commands` names a missing **host** command. | Install that host command, or remove the requirement if the plugin does not need it. |

## Checklist before sharing a plugin

Before another person installs your plugin, make sure that it passes this sequence:

```bash
python3 jroot-dev.py validate --strict ./your-plugin
python3 jroot-dev.py test ./your-plugin
jroot plugin install ./your-plugin
jroot plugin verify your-plugin
jroot plugin inspect your-plugin
```

Include a concise README in the plugin repository explaining its purpose, each declared hook, required host commands, what data it stores, whether it starts a service, and what host access it needs. That description is more valuable to a reviewer than a vague permission label.

For a Windows-first walkthrough, see [Windows Plugin Development](WINDOWS_DEV.md).
