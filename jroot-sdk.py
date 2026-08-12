#!/usr/bin/env python3
import os
import json
import glob
import subprocess

class JRootContext:
    def __init__(self):
        self.home = os.environ.get("JROOT_HOME", os.path.expanduser("~/.jroot"))
        self.roots_dir = os.environ.get("JROOT_ROOTS", os.path.join(self.home, "roots"))
        self.configs_dir = os.environ.get("JROOT_CONFIGS", os.path.join(self.home, "configs"))
        self.bin_dir = os.environ.get("JROOT_BIN", os.path.join(self.home, "bin"))
        self.plugin_data = os.environ.get("JROOT_PLUGIN_DATA", os.path.join(self.home, "plugins", "data", "default"))

    def list_jails(self):
        jails = []
        if not os.path.isdir(self.configs_dir):
            return jails
        for cfg_path in glob.glob(os.path.join(self.configs_dir, "*.json")):
            name = os.path.basename(cfg_path)[:-5]
            try:
                with open(cfg_path, "r") as f:
                    cfg = json.load(f)
            except Exception:
                cfg = {}
            jails.append({
                "name": name,
                "image": cfg.get("image", "unknown"),
                "user": cfg.get("user", "root"),
                "limit_mem": cfg.get("limit_mem", "Unlimited"),
                "config_path": cfg_path,
                "rootfs_path": os.path.join(self.roots_dir, name)
            })
        return jails

    def get_jail(self, name):
        cfg_path = os.path.join(self.configs_dir, f"{name}.json")
        if not os.path.exists(cfg_path):
            return None
        with open(cfg_path, "r") as f:
            cfg = json.load(f)
        cfg["name"] = name
        cfg["rootfs_path"] = os.path.join(self.roots_dir, name)
        return cfg

    def run_in_jail(self, jail_name, command):
        """Execute a command inside a jail using jroot exec."""
        res = subprocess.run(["jroot", "exec", jail_name, "/bin/sh", "-c", command], capture_output=True, text=True)
        return res.returncode, res.stdout, res.stderr

    def read_plugin_state(self, filename="state.json", default=None):
        path = os.path.join(self.plugin_data, filename)
        if not os.path.exists(path):
            return default if default is not None else {}
        try:
            with open(path, "r") as f:
                return json.load(f)
        except Exception:
            return default if default is not None else {}

    def write_plugin_state(self, data, filename="state.json"):
        os.makedirs(self.plugin_data, exist_ok=True)
        path = os.path.join(self.plugin_data, filename)
        with open(path, "w") as f:
            json.dump(data, f, indent=2)

if __name__ == "__main__":
    ctx = JRootContext()
    print(json.dumps(ctx.list_jails(), indent=2))
