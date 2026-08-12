#!/usr/bin/env python3
"""Cross-platform development and validation utility for JRoot plugins.

This program deliberately does not run JRoot itself. It creates an isolated mock
runtime so plugin authors can validate and exercise Python plugin handlers on
Windows, macOS, or Linux before installing a plugin on a JRoot host.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable

PLUGIN_API_VERSION = 1
PLUGIN_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[-+][0-9A-Za-z.-]+)?$")
HOOK_NAME_RE = re.compile(r"^on_[a-z][a-z0-9_]*$")
KNOWN_HOOKS = {
    "on_init",
    "on_enter",
    "on_stop",
    "on_remove",
    "on_sync",
    "on_snapshot",
    "on_limit",
}
RESERVED_COMMANDS = {
    "init", "enter", "exec", "shell", "install", "file", "sync", "limit",
    "bundle", "deploy", "monitor", "compose", "port", "net", "mnt", "mount",
    "config", "list", "ls", "info", "history", "compare", "diff", "which",
    "size", "update", "clean", "snapshot", "snapshots", "revert", "rm-snapshot",
    "doctor", "rm", "delete", "rename", "kill", "stop", "ps", "ssh",
    "completion", "completions", "plugin", "help",
}
HOOK_FIXTURES = {
    "on_init": ["sample-jail", "ubuntu:22.04"],
    "on_enter": ["sample-jail", "command"],
    "on_stop": ["sample-jail", "user-request"],
    "on_remove": ["sample-jail"],
    "on_sync": ["host:/project", "sample-jail:/root/project"],
    "on_snapshot": ["sample-jail", "create:sample"],
    "on_limit": ["sample-jail", "mem=256M,cpu=60,nofile=512"],
}


def load_manifest(plugin_dir: Path) -> tuple[dict[str, Any] | None, list[str]]:
    manifest_path = plugin_dir / "plugin.json"
    if not manifest_path.is_file():
        return None, ["Missing plugin.json manifest file."]
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return None, [f"Invalid JSON in plugin.json: {exc}"]
    if not isinstance(data, dict):
        return None, ["plugin.json must contain a JSON object."]
    return data, []


def validate_manifest(plugin_dir: Path) -> tuple[dict[str, Any] | None, list[str], list[str]]:
    manifest, errors = load_manifest(plugin_dir)
    warnings: list[str] = []
    if manifest is None:
        return None, errors, warnings

    name = manifest.get("name")
    if not isinstance(name, str) or not PLUGIN_NAME_RE.fullmatch(name):
        errors.append("Manifest field 'name' must be a lowercase identifier (1-64 characters: a-z, 0-9, '.', '_' or '-').")
    elif name in RESERVED_COMMANDS or name in {"data", "logs", "registry"}:
        errors.append(f"Plugin name '{name}' is reserved by the JRoot runtime.")

    version = manifest.get("version")
    if not isinstance(version, str) or not SEMVER_RE.fullmatch(version):
        errors.append("Manifest field 'version' must use Semantic Versioning (for example: 1.0.0).")

    api_version = manifest.get("api_version")
    if api_version is None:
        warnings.append("Legacy manifest: add 'api_version': 1 before publishing this plugin.")
    elif api_version != PLUGIN_API_VERSION:
        errors.append(f"Manifest api_version must be {PLUGIN_API_VERSION}; found {api_version!r}.")

    description = manifest.get("description")
    if description is not None and (not isinstance(description, str) or not description.strip()):
        errors.append("Manifest field 'description', when present, must be a non-empty string.")

    entrypoint = manifest.get("entrypoint", "main.py")
    if not isinstance(entrypoint, str) or entrypoint.startswith(("/", "\\")) or ".." in Path(entrypoint).parts:
        errors.append("Manifest field 'entrypoint' must be a relative path inside the plugin bundle.")
    elif Path(entrypoint).suffix not in {".py", ".sh"}:
        errors.append("Manifest entrypoint must be a Python (.py) or POSIX shell (.sh) file.")
    elif not (plugin_dir / entrypoint).is_file():
        errors.append(f"Manifest entrypoint '{entrypoint}' does not exist in the plugin bundle.")

    hooks = manifest.get("hooks")
    if hooks is None:
        warnings.append("Legacy manifest: declare the lifecycle hooks the plugin subscribes to.")
    elif not isinstance(hooks, list) or not all(isinstance(hook, str) and HOOK_NAME_RE.fullmatch(hook) for hook in hooks):
        errors.append("Manifest field 'hooks' must be an array of names beginning with 'on_'.")
    elif len(set(hooks)) != len(hooks):
        errors.append("Manifest field 'hooks' must not contain duplicate event names.")

    permissions = manifest.get("permissions", [])
    if not isinstance(permissions, list) or not all(isinstance(permission, str) for permission in permissions):
        errors.append("Manifest field 'permissions' must be an array of descriptive strings.")

    requires = manifest.get("requires", {})
    if not isinstance(requires, dict):
        errors.append("Manifest field 'requires' must be an object when present.")
    else:
        commands = requires.get("commands", [])
        if not isinstance(commands, list) or not all(isinstance(command, str) and re.fullmatch(r"[A-Za-z0-9._+-]+", command) for command in commands):
            errors.append("Manifest requires.commands must be an array of command names.")
        python_requirement = requires.get("python")
        if python_requirement is not None:
            if not isinstance(python_requirement, str) or not re.fullmatch(r">=[0-9]+\.[0-9]+", python_requirement):
                errors.append("Manifest requires.python must use the supported format '>=MAJOR.MINOR'.")

    return manifest, errors, warnings


def print_messages(errors: Iterable[str], warnings: Iterable[str]) -> None:
    for warning in warnings:
        print(f"[!] Warning: {warning}")
    for error in errors:
        print(f"[-] {error}")


def entrypoint_for(plugin_dir: Path, manifest: dict[str, Any]) -> Path:
    return plugin_dir / manifest.get("entrypoint", "main.py")


def mock_runtime(root: Path) -> tuple[Path, Path]:
    home = root / ".jroot"
    (home / "roots" / "sample-jail").mkdir(parents=True)
    (home / "configs").mkdir(parents=True)
    (home / "plugin-data").mkdir(parents=True)
    config = {
        "name": "sample-jail",
        "image": "ubuntu:22.04",
        "user": "root",
        "limit_mem": "256M",
        "limit_cpu": "60",
        "limit_nofile": "512",
    }
    (home / "configs" / "sample-jail.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    return home, home / "plugin-data" / "development-plugin"


def execution_environment(home: Path, plugin_data: Path) -> dict[str, str]:
    env = os.environ.copy()
    sdk_dir = str(Path(__file__).resolve().parent)
    env.update({
        "JROOT_HOME": str(home),
        "JROOT_ROOTS": str(home / "roots"),
        "JROOT_CONFIGS": str(home / "configs"),
        "JROOT_BIN": str(home / "bin"),
        "JROOT_PLUGIN_DATA": str(plugin_data),
        "JROOT_PLUGIN_API": str(PLUGIN_API_VERSION),
        "JROOT_PLUGIN_NAME": "development-plugin",
        "PYTHONPATH": sdk_dir + os.pathsep + env.get("PYTHONPATH", ""),
    })
    return env


def run_handler(plugin_dir: Path, manifest: dict[str, Any], hook: str, hook_args: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    entrypoint = entrypoint_for(plugin_dir, manifest)
    with tempfile.TemporaryDirectory(prefix="jroot-plugin-dev-") as temporary_dir:
        home, plugin_data = mock_runtime(Path(temporary_dir))
        if entrypoint.suffix == ".py":
            command = [sys.executable, str(entrypoint), f"hook:{hook}", *hook_args]
        else:
            shell = shutil.which("bash")
            if shell is None:
                raise RuntimeError("Cannot simulate a shell plugin because bash is unavailable. Use WSL, Git Bash, or a Linux host.")
            command = [shell, str(entrypoint), f"hook:{hook}", *hook_args]
        return subprocess.run(command, env=execution_environment(home, plugin_data), capture_output=True, text=True, timeout=timeout)


def cmd_init(args: argparse.Namespace) -> int:
    target_dir = Path(args.name or "jroot-plugin-template")
    if target_dir.exists() and any(target_dir.iterdir()):
        print(f"[-] Refusing to overwrite non-empty directory: {target_dir}", file=sys.stderr)
        return 1
    target_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "api_version": PLUGIN_API_VERSION,
        "name": target_dir.name.lower().replace("_", "-").replace(" ", "-"),
        "version": "0.1.0",
        "description": "A JRoot plugin.",
        "author": "Developer",
        "entrypoint": "main.py",
        "hooks": ["on_init"],
        "permissions": ["jails.read", "state.read", "state.write"],
        "requires": {"python": ">=3.8", "commands": []},
    }
    (target_dir / "plugin.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    script = '''#!/usr/bin/env python3
import sys
from jroot_sdk import JRootContext


def main() -> int:
    ctx = JRootContext()
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "hook:on_init":
        jail_name, image = sys.argv[2:4]
        ctx.log.info(f"Provisioned {jail_name} from {image}")
        state = ctx.read_plugin_state("state.json", {"initializations": 0})
        state["initializations"] += 1
        ctx.write_plugin_state(state, "state.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''
    script_path = target_dir / "main.py"
    script_path.write_text(script, encoding="utf-8")
    try:
        script_path.chmod(0o755)
    except OSError:
        pass
    print(f"[+] Created plugin template: {target_dir}")
    print("    Next: validate it with 'python jroot-dev.py validate <path>'.")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    plugin_dir = Path(args.path).resolve()
    manifest, errors, warnings = validate_manifest(plugin_dir)
    print(f"[*] Validating plugin bundle: {plugin_dir}")
    print_messages(errors, warnings)
    if errors:
        print("[-] Validation failed.")
        return 1
    if args.strict and warnings:
        print("[-] Strict validation failed because the plugin uses legacy manifest fields.")
        return 1
    assert manifest is not None
    print(f"[+] Validation passed (API {manifest.get('api_version', 'legacy')}; entrypoint {manifest.get('entrypoint', 'main.py')}).")
    return 0


def cmd_simulate(args: argparse.Namespace) -> int:
    plugin_dir = Path(args.path).resolve()
    manifest, errors, warnings = validate_manifest(plugin_dir)
    print_messages(errors, warnings)
    if errors or manifest is None:
        return 1
    if manifest.get("hooks") and args.hook not in manifest["hooks"]:
        print(f"[-] Hook '{args.hook}' is not declared in plugin.json.", file=sys.stderr)
        return 1
    hook_args = args.hook_args if args.hook_args else HOOK_FIXTURES.get(args.hook, ["sample-jail"])
    print(f"[*] Simulating {args.hook} with arguments: {hook_args}")
    try:
        result = run_handler(plugin_dir, manifest, args.hook, hook_args, args.timeout)
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
        print(f"[-] Simulation could not start: {exc}", file=sys.stderr)
        return 1
    print("--- Plugin output ---")
    print(result.stdout, end="")
    if result.stderr:
        print("--- Plugin errors ---", file=sys.stderr)
        print(result.stderr, end="", file=sys.stderr)
    print(f"--- Exit code: {result.returncode} ---")
    return result.returncode


def cmd_test(args: argparse.Namespace) -> int:
    plugin_dir = Path(args.path).resolve()
    manifest, errors, warnings = validate_manifest(plugin_dir)
    print_messages(errors, warnings)
    if errors or manifest is None:
        return 1
    hooks = manifest.get("hooks") or []
    if not hooks:
        print("[-] No hooks declared; there is no contract test to run.")
        return 1
    failures = 0
    for hook in hooks:
        fixture = HOOK_FIXTURES.get(hook, ["sample-jail"])
        print(f"[*] Testing {hook} with fixture {fixture}...")
        try:
            result = run_handler(plugin_dir, manifest, hook, fixture, args.timeout)
        except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
            print(f"[-] {hook}: could not start: {exc}")
            failures += 1
            continue
        if result.returncode == 0:
            print(f"[+] {hook}: passed")
        else:
            print(f"[-] {hook}: failed with exit code {result.returncode}")
            if result.stdout:
                print(result.stdout, end="")
            if result.stderr:
                print(result.stderr, end="", file=sys.stderr)
            failures += 1
    if failures:
        print(f"[-] {failures} hook test(s) failed.")
        return 1
    print("[+] All declared hook fixtures passed.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Cross-platform JRoot plugin development helper")
    subparsers = parser.add_subparsers(dest="command", required=True)
    init = subparsers.add_parser("init", help="create a standards-compliant plugin template")
    init.add_argument("name", nargs="?", default="jroot-plugin-template", help="target directory")
    init.set_defaults(func=cmd_init)

    validate = subparsers.add_parser("validate", help="validate a plugin manifest, entry point, and dependencies")
    validate.add_argument("path", nargs="?", default=".", help="plugin directory")
    validate.add_argument("--strict", action="store_true", help="reject legacy manifests that omit API metadata")
    validate.set_defaults(func=cmd_validate)

    simulate = subparsers.add_parser("simulate", help="run one hook against an isolated mock JRoot runtime")
    simulate.add_argument("hook", help="declared hook name")
    simulate.add_argument("hook_args", nargs="*", help="optional hook arguments; defaults to a fixture")
    simulate.add_argument("--path", default=".", help="plugin directory")
    simulate.add_argument("--timeout", type=int, default=10, help="execution timeout in seconds")
    simulate.set_defaults(func=cmd_simulate)

    test = subparsers.add_parser("test", help="exercise every declared hook against contract fixtures")
    test.add_argument("path", nargs="?", default=".", help="plugin directory")
    test.add_argument("--timeout", type=int, default=10, help="per-hook execution timeout in seconds")
    test.set_defaults(func=cmd_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
