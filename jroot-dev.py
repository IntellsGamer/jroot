#!/usr/bin/env python3
import os
import sys
import json
import argparse
import subprocess
import tempfile
import shutil
from pathlib import Path

def cmd_init(args):
    target_dir = Path(args.name or "jroot-plugin-template")
    target_dir.mkdir(parents=True, exist_ok=True)
    
    manifest = {
        "name": target_dir.name,
        "version": "1.0.0",
        "author": "Developer",
        "description": "A JRoot enterprise plugin",
        "hooks": ["on_init", "on_enter", "on_stop", "on_remove", "on_sync", "on_snapshot", "on_limit"]
    }
    
    manifest_path = target_dir / "plugin.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        
    script_content = '''#!/usr/bin/env python3
import sys
import os

def main():
    print(f"[Plugin] Arguments received: {sys.argv[1:]}")
    
    # Example of reading environment variables provided by JRoot runtime
    plugin_data = os.environ.get("JROOT_PLUGIN_DATA", "./plugin-data")
    os.makedirs(plugin_data, exist_ok=True)
    
    print(f"[Plugin] Isolated plugin storage at: {plugin_data}")

if __name__ == "__main__":
    main()
'''
    script_path = target_dir / "main.py"
    with open(script_path, "w") as f:
        f.write(script_content)
        
    # Make executable on Unix, advisory on Windows
    try:
        script_path.chmod(0o755)
    except Exception:
        pass
        
    print(f"[+] Successfully initialized plugin template in '{target_dir}'")
    print(f"    - {manifest_path}")
    print(f"    - {script_path}")

def cmd_validate(args):
    plugin_dir = Path(args.path or ".")
    print(f"[*] Validating plugin structure in '{plugin_dir}'...")
    
    errors = []
    warnings = []
    
    manifest_path = plugin_dir / "plugin.json"
    if not manifest_path.exists():
        errors.append("Missing 'plugin.json' manifest file.")
    else:
        try:
            with open(manifest_path, "r") as f:
                manifest = json.load(f)
            
            for key in ["name", "version", "hooks"]:
                if key not in manifest:
                    errors.append(f"Manifest 'plugin.json' missing required field: '{key}'")
                    
            if "hooks" in manifest and not isinstance(manifest["hooks"], list):
                errors.append("Manifest field 'hooks' must be a JSON array.")
        except json.JSONDecodeError as e:
            errors.append(f"Invalid JSON in 'plugin.json': {e}")
            
    main_py = plugin_dir / "main.py"
    if not main_py.exists():
        errors.append("Missing entry point script 'main.py'.")
    else:
        # Check python syntax
        try:
            code = main_py.read_text()
            compile(code, str(main_py), 'exec')
        except SyntaxError as e:
            errors.append(f"Syntax error in 'main.py': {e}")
            
    if errors:
        print("[-] Validation FAILED with errors:")
        for err in errors:
            print(f"    - {err}")
        sys.exit(1)
    else:
        print("[+] Validation PASSED successfully! No structural or syntax errors found.")

def cmd_simulate(args):
    plugin_dir = Path(args.path or ".")
    manifest_path = plugin_dir / "plugin.json"
    main_py = plugin_dir / "main.py"
    
    if not manifest_path.exists() or not main_py.exists():
        print("[-] Error: Invalid plugin directory. Run 'validate' first.")
        sys.exit(1)
        
    hook_name = args.hook
    hook_args = args.hook_args or []
    
    print(f"[*] Simulating hook '{hook_name}' with args {hook_args}...")
    
    # Create temp data store for simulation
    with tempfile.TemporaryDirectory() as tmpdir:
        env = os.environ.copy()
        env["JROOT_PLUGIN_DATA"] = tmpdir
        env["JROOT_HOME"] = str(Path(tmpdir) / ".jroot")
        
        cmd = [sys.executable, str(main_py), f"hook:{hook_name}"] + hook_args
        
        try:
            res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
            print("--- Simulation Output ---")
            print(res.stdout)
            if res.stderr:
                print("--- Simulation Stderr ---")
                print(res.stderr, file=sys.stderr)
            print(f"--- Exit Code: {res.returncode} ---")
            if res.returncode != 0:
                sys.exit(res.returncode)
        except Exception as e:
            print(f"[-] Simulation failed to execute: {e}")
            sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="JRoot Cross-Platform Plugin Development & Validation Helper")
    subparsers = parser.add_subparsers(dest="command", required=True)
    
    # init
    p_init = subparsers.add_parser("init", help="Initialize a new plugin template")
    p_init.add_argument("name", nargs="?", default="jroot-plugin-template", help="Plugin directory name")
    
    # validate
    p_val = subparsers.add_parser("validate", help="Validate plugin manifest and entry point")
    p_val.add_argument("path", nargs="?", default=".", help="Path to plugin directory")
    
    # simulate
    p_sim = subparsers.add_parser("simulate", help="Simulate hook execution locally")
    p_sim.add_argument("hook", help="Hook name to simulate (e.g. on_init, on_enter)")
    p_sim.add_argument("hook_args", nargs="*", help="Arguments passed to the hook")
    p_sim.add_argument("--path", default=".", help="Path to plugin directory")
    
    args = parser.parse_args()
    
    if args.command == "init":
        cmd_init(args)
    elif args.command == "validate":
        cmd_validate(args)
    elif args.command == "simulate":
        cmd_simulate(args)

if __name__ == "__main__":
    main()
