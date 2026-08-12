# JRoot Plugin Development on Windows

`jroot` itself runs on Linux through PRoot and therefore is not a Windows runtime. Plugin development does not require a Linux jail, however: the repository includes `jroot-dev.py`, a standard-library Python helper that validates and exercises packaged plugins on Windows, macOS, and Linux.

The helper creates a temporary mock JRoot home, a sample jail configuration, and an isolated plugin data directory. It does not install or execute PRoot.

## Prerequisites

Install Python **3.8 or newer** and clone or download the repository so that these files are in the same directory:

```text
jroot-dev.py
jroot_sdk.py
docs/
```

No external Python packages are required.

## Create a plugin

Use the helper to generate a manifest and a Python handler:

```powershell
python .\jroot-dev.py init my-plugin
```

The created `plugin.json` targets plugin API version 1 and declares an `on_init` hook. Edit its `name`, `description`, dependencies, requested permissions, and hook list before using it.

## Validate before transfer

Run strict validation before copying the plugin to a Linux host:

```powershell
python .\jroot-dev.py validate --strict .\my-plugin
```

Strict validation checks the manifest version, safe plugin identifier, Semantic Versioning version, entry-point path, declared hooks, optional command dependency format, and Python syntax. A packaged plugin must pass this command before the Linux runtime will install it.

## Simulate a hook

Run a single declared hook with the standard fixture arguments:

```powershell
python .\jroot-dev.py simulate on_init --path .\my-plugin
```

You may override the fixture payload when testing parsing behavior:

```powershell
python .\jroot-dev.py simulate on_limit sample-jail mem=256M,cpu=60,nofile=512 --path .\my-plugin
```

During simulation, `JROOT_PLUGIN_DATA` points to a temporary private directory. The helper also sets `JROOT_HOME`, `JROOT_CONFIGS`, and `JROOT_ROOTS` to a mock JRoot layout containing a `sample-jail` configuration.

## Test every declared hook

Run the complete contract fixture set before deployment:

```powershell
python .\jroot-dev.py test .\my-plugin
```

This runs every event listed in `plugin.json` and returns non-zero if a handler crashes, exits non-zero, or exceeds the configured timeout. Change the timeout when deliberately testing a slower handler:

```powershell
python .\jroot-dev.py test .\my-plugin --timeout 30
```

## Linux deployment

Copy the validated directory to the Linux machine that runs JRoot, then install and verify it there:

```bash
jroot plugin install ./my-plugin
jroot plugin verify my-plugin
jroot plugin inspect my-plugin
```

The local simulation verifies the plugin contract and ordinary Python behavior. It cannot reproduce Linux-only commands, a live jail process tree, host dependencies, or the privileges of the final host. Keep final deployment verification on the intended Linux system.
