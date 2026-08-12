# JRoot Plugin Development on Windows (`jroot-dev.py`)

Because `jroot` runs on Linux userspace via PRoot, Windows developers cannot execute `jroot` directly on Windows hosts. However, you can develop, validate, and simulate `jroot` plugins locally on Windows using the cross-platform development helper (`jroot-dev.py`).

---

## Prerequisites

- Python 3.8 or higher installed on Windows.

---

## Quickstart: Bootstrapping a Plugin

To initialize a new plugin project structure in your current Windows workspace:

```bash
python jroot-dev.py init my-new-plugin
```

This generates a local directory containing:
1. **`plugin.json`**: The plugin manifest defining metadata and hooks.
2. **`main.py`**: The entry-point script handling hook dispatches and storage.

---

## Manifest Validation

Before deploying your plugin to a Linux environment running `jroot`, validate your plugin configuration and syntax locally:

```bash
python jroot-dev.py validate my-new-plugin
```

The validator checks for:
- Presence and formatting of `plugin.json`.
- Required manifest fields (`name`, `version`, `hooks`).
- Python syntax correctness in `main.py`.

---

## Local Hook Simulation

You can simulate how `jroot` dispatches lifecycle hooks to your plugin, verifying argument parsing and state persistence before pushing to production:

```bash
# Simulate the 'on_init' hook with mock jail arguments
python jroot-dev.py simulate on_init test-jail ubuntu:22.04 --path my-new-plugin

# Simulate the 'on_enter' hook
python jroot-dev.py simulate on_enter test-jail --path my-new-plugin
```

The simulation securely mocks isolated plugin data directories (`$JROOT_PLUGIN_DATA`), allowing you to test state read/write operations locally on Windows.
