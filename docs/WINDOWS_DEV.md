# Developing JRoot Plugins on Windows

JRoot runs Linux userspace through PRoot, so Windows is not a host for running a jail. Windows is still a good place to **write, validate, and test a plugin** before it is copied to a Linux machine that runs JRoot.

The repository’s `jroot-dev.py` helper is a standard-library Python program. It does not install PRoot or start a Linux environment. Instead, it creates a temporary mock JRoot home, a `sample-jail` configuration, and a private plugin data directory, then runs your handler with the same hook argument contract that JRoot uses on Linux.

> The helper validates the plugin contract and ordinary Python behavior. It cannot emulate Linux-only programs, a real PRoot process tree, installed host dependencies, or the final Linux host’s permissions. Always perform one final install and verification on the Linux system that will run the plugin.

For the complete plugin API, manifest reference, hook table, SDK reference, and service guidance, read the [Plugin Development Guide](PLUGINS.md).

## What you need

Install Python **3.8 or newer**. In PowerShell, confirm that either `python` or the Python launcher `py` works:

```powershell
python --version
# or
py --version
```

Clone the project, or download and extract its source archive. From a clone, open PowerShell in the repository root:

```powershell
git clone https://github.com/IntellsGamer/jroot.git
cd jroot
python .\jroot-dev.py --help
```

The helper and SDK need to remain in the same checkout:

```text
jroot/
├── jroot-dev.py
├── jroot_sdk.py
├── docs/
│   ├── PLUGINS.md
│   └── WINDOWS_DEV.md
└── your-plugin/
```

No `pip install` step or external Python package is required.

## The Windows-to-Linux workflow

A useful workflow has two environments with different responsibilities:

| Environment | What you do there | What you do not expect it to do |
|---|---|---|
| Windows workstation | Write code, validate `plugin.json`, simulate hooks, test every declared event. | Run PRoot, launch a jail, or prove a Linux dependency exists. |
| Linux JRoot host | Install the reviewed plugin, verify real host dependencies, run real JRoot operations, inspect logs. | Replace local source control and normal development tooling. |

The rest of this guide follows that workflow end to end.

## 1. Generate a real plugin project

Run the generator from the repository root:

```powershell
python .\jroot-dev.py init .\jail-audit
cd .\jail-audit
```

The result is a packaged plugin:

```text
jail-audit/
├── plugin.json
└── main.py
```

Open `plugin.json` in your editor and set meaningful metadata. This is a complete minimal manifest:

```json
{
  "api_version": 1,
  "name": "jail-audit",
  "version": "0.1.0",
  "description": "Records jail creation events.",
  "author": "Your name",
  "entrypoint": "main.py",
  "hooks": ["on_init"],
  "permissions": ["jails.read", "state.read", "state.write"],
  "requires": {
    "python": ">=3.8",
    "commands": []
  }
}
```

Use a lowercase `name`; it becomes the Linux command `jroot jail-audit`. Do not use a JRoot built-in command such as `init`, `sync`, `plugin`, or `help` as the name.

## 2. Write and run a first handler

Replace `main.py` with this example. It stores a count in the plugin-private directory and prints an audit line through the JRoot logger.

```python
#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext


def main() -> int:
    context = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    if action == "hook:on_init":
        jail, image = sys.argv[2:4]
        state = context.read_plugin_state("state.json", {"created": 0})
        state["created"] += 1
        context.write_plugin_state(state, "state.json")
        context.log.info(f"created jail={jail} image={image} count={state['created']}")
    else:
        print("Run this plugin through a declared JRoot hook.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

The first argument is always the dispatch selector. For this handler, the simulated invocation is:

```text
hook:on_init sample-jail ubuntu:22.04
```

The `JRootContext` object discovers the mock paths from environment variables, just as it does when JRoot starts the plugin on Linux.

## 3. Validate the package before testing it

Run strict validation from the repository root. Replace `python` with `py` if your Windows Python installation uses the launcher instead.

```powershell
cd ..
python .\jroot-dev.py validate --strict .\jail-audit
```

A strict check catches these common mistakes before the plugin ever reaches Linux:

| Check | Example failure |
|---|---|
| Manifest JSON | Missing comma or an invalid JSON value. |
| API version | Missing `"api_version": 1`. |
| Plugin name | Uppercase letters, spaces, or a reserved command name. |
| Version | `version: "one"` instead of `0.1.0`. |
| Entry point | `entrypoint` names a missing file or escapes the bundle with `..`. |
| Hooks | A non-array value, duplicates, or an invalid `on_*` name. |
| Python syntax | A missing colon, indentation error, or other compile-time error in `main.py`. |

Do not skip `--strict` for a plugin you plan to share. It intentionally rejects legacy manifests that omit contract metadata.

## 4. Simulate one hook while iterating

Use `simulate` for a fast edit-run-debug cycle:

```powershell
python .\jroot-dev.py simulate on_init --path .\jail-audit
```

The helper creates a temporary environment for this one invocation. Your output should resemble:

```text
[*] Simulating on_init with arguments: ['sample-jail', 'ubuntu:22.04']
--- Plugin output ---
2026-... INFO  [development-plugin] created jail=sample-jail image=ubuntu:22.04 count=1
--- Exit code: 0 ---
```

You can test parser behavior with your own event values. First add `on_limit` to the manifest’s `hooks` list and then add a matching branch in `main.py`; after that, run:

```powershell
python .\jroot-dev.py simulate on_limit sample-jail mem=256M,cpu=60,nofile=512 --path .\jail-audit
```

The helper refuses to simulate an undeclared hook. That is deliberate: a packaged plugin should not rely on an event it has not explicitly requested.

## 5. Test every declared hook

Once the handler works for one event, test the entire manifest contract:

```powershell
python .\jroot-dev.py test .\jail-audit
```

For every hook in `plugin.json`, the helper launches a new mock runtime and passes a standard fixture. A non-zero exit, a crash, or a timeout fails the command. The default timeout is ten seconds; use a larger value only for a handler that intentionally needs it:

```powershell
python .\jroot-dev.py test .\jail-audit --timeout 30
```

Do not put an infinite monitoring loop directly in a hook that this command tests. Put long-running work behind a separate custom hook such as `on_monitor`, or add a test mode that exits after one iteration.

## 6. Inspect the mock data model

During a simulation, the helper makes these values available to your plugin:

| Variable or resource | Value in the Windows test environment |
|---|---|
| `JROOT_HOME` | A temporary mock `.jroot` directory. |
| `JROOT_CONFIGS` | Contains `sample-jail.json`. |
| `JROOT_ROOTS` | Contains an empty `sample-jail` root directory. |
| `JROOT_PLUGIN_DATA` | A private temporary directory for the current simulated plugin. |
| `JROOT_PLUGIN_API` | `1`. |
| `JROOT_PLUGIN_NAME` | `development-plugin`. |

The mock `sample-jail` has this representative configuration:

```json
{
  "name": "sample-jail",
  "image": "ubuntu:22.04",
  "user": "root",
  "limit_mem": "256M",
  "limit_cpu": "60",
  "limit_nofile": "512"
}
```

That means you can exercise `context.list_jails()`, `context.get_jail("sample-jail")`, and private JSON state on Windows. The temporary files are deleted after each simulation, so a test never leaves state in your working directory.

## 7. Python and shell plugins on Windows

Python plugins work directly in PowerShell because the helper invokes them with the active Python interpreter.

A shell plugin can be validated structurally on Windows, but simulation requires `bash` to be discoverable. Use one of these options:

| Plugin type | Windows approach |
|---|---|
| Python (`main.py`) | Use PowerShell and `python .\jroot-dev.py ...`. |
| POSIX shell (`main.sh`) | Use WSL or install Git Bash and ensure `bash` is on `PATH`. |
| Linux-specific command behavior | Keep a small Linux test host or VM for the final deployment check. |

Do not try to use `cmd.exe` or PowerShell syntax inside a `.sh` plugin. JRoot runs shell plugins with Bash on Linux.

## 8. Transfer the plugin to Linux

After `validate --strict` and `test` pass, copy the entire plugin directory—not just `main.py`—to the Linux machine that has JRoot installed. For example, from PowerShell with OpenSSH available:

```powershell
scp -r .\jail-audit user@linux-host:~/plugins/
```

On the Linux host:

```bash
cd ~/plugins
jroot plugin install ./jail-audit
jroot plugin verify jail-audit
jroot plugin inspect jail-audit
```

Now run the real operation that should trigger the plugin and inspect its captured output:

```bash
jroot init ubuntu:22.04 --name=demo
jroot plugin logs jail-audit
```

If the plugin needs a host command, declare it in `requires.commands`; `jroot plugin install` and `jroot plugin verify` will reject the package until that **host** command is available. That list does not install a package inside a jail.

## 9. Windows-specific troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `python` is not recognized | Python is not installed or not on `PATH`. | Use `py` if available, reinstall Python with its launcher/PATH option, or call the full Python executable path. |
| `ModuleNotFoundError: jroot_sdk` | You ran the helper outside the repository or copied only `jroot-dev.py`. | Run it from the JRoot checkout containing `jroot_sdk.py`. |
| `Cannot simulate a shell plugin because bash is unavailable` | Windows does not ship Bash. | Use WSL, Git Bash, or develop the plugin in Python. |
| `Hook ... is not declared in plugin.json` | The manifest and handler disagree. | Add the hook to `hooks`, then rerun strict validation. |
| `test` times out | A handler blocks, sleeps too long, or starts a service loop. | Test a one-shot handler; put long-running logic behind a separately started service hook. |
| Linux installation rejects the plugin | The real host differs from Windows. | Run `jroot plugin verify <name>` on Linux and install missing host dependencies. |

## Final pre-deployment checklist

Run these commands before handing a plugin to someone else:

```powershell
python .\jroot-dev.py validate --strict .\jail-audit
python .\jroot-dev.py test .\jail-audit
```

Then on the actual Linux JRoot host:

```bash
jroot plugin install ./jail-audit
jroot plugin verify jail-audit
jroot plugin inspect jail-audit
jroot plugin logs jail-audit
```

That sequence gives you a clean division of responsibility: Windows catches packaging and ordinary code mistakes early; Linux confirms the real runtime, host dependencies, and event behavior.
