#!/usr/bin/env python3
import os
import json
import glob
import subprocess
from datetime import datetime
from pathlib import Path

class Logger:
    def __init__(self, plugin_name):
        self.plugin_name = plugin_name
        
    def _log(self, level, message):
        timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
        print(f"{timestamp} {level:<5} [{self.plugin_name}] {message}", flush=True)

    def info(self, message): self._log("INFO", message)
    def warn(self, message): self._log("WARN", message)
    def error(self, message): self._log("ERROR", message)
    def debug(self, message): self._log("DEBUG", message)

class JRootContext:
    def __init__(self):
        self.home = os.environ.get("JROOT_HOME", os.path.expanduser("~/.jroot"))
        self.roots_dir = os.environ.get("JROOT_ROOTS", os.path.join(self.home, "roots"))
        self.configs_dir = os.environ.get("JROOT_CONFIGS", os.path.join(self.home, "configs"))
        self.bin_dir = os.environ.get("JROOT_BIN", os.path.join(self.home, "bin"))
        self.plugin_data = os.environ.get("JROOT_PLUGIN_DATA", os.path.join(self.home, "plugins", "data", "default"))
        self.plugin_name = os.environ.get("JROOT_PLUGIN_NAME", os.path.basename(self.plugin_data))
        self.log = Logger(self.plugin_name)

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
                "limit_cpu": cfg.get("limit_cpu", "Unlimited"),
                "limit_nofile": cfg.get("limit_nofile", "Unlimited"),
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
        """Execute a shell command in a jail and return (exit_code, stdout, stderr)."""
        jroot_command = os.environ.get("JROOT_COMMAND", "jroot")
        res = subprocess.run(
            [jroot_command, "exec", jail_name, "/bin/sh", "-c", command],
            capture_output=True, text=True, check=False,
        )
        return res.returncode, res.stdout, res.stderr

    def get_resource_usage(self, jail_name):
        """Return RSS and cumulative CPU time for tracked JRoot launcher processes.

        This is observational process accounting, not cgroup accounting. Rootless
        PRoot does not expose a kernel-enforced aggregate to this SDK.
        """
        try:
            jroot_command = os.environ.get("JROOT_COMMAND", "jroot")
            res = subprocess.run([jroot_command, "ps", "--json"], capture_output=True, text=True, check=False)
            if res.returncode != 0:
                raise RuntimeError(res.stderr.strip() or "jroot ps --json failed")
            processes = json.loads(res.stdout)
            jail_pids = [int(p["pid"]) for p in processes if p.get("jail") == jail_name]
            if not jail_pids:
                return {"mem_bytes": 0, "mem_mb": 0.0, "cpu_seconds": 0.0, "pids": 0}

            total_rss = 0
            total_ticks = 0
            page_size = os.sysconf("SC_PAGE_SIZE")
            clock_ticks = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
            living = 0
            for pid in jail_pids:
                try:
                    statm = Path(f"/proc/{pid}/statm").read_text().split()
                    stat = Path(f"/proc/{pid}/stat").read_text().split()
                    total_rss += int(statm[1]) * page_size
                    total_ticks += int(stat[13]) + int(stat[14])
                    living += 1
                except (OSError, IndexError, ValueError):
                    continue
            return {
                "mem_bytes": total_rss,
                "mem_mb": round(total_rss / (1024 * 1024), 2),
                "cpu_seconds": round(total_ticks / clock_ticks, 3),
                "pids": living,
            }
        except (OSError, RuntimeError, json.JSONDecodeError) as e:
            self.log.error(f"Unable to collect resource usage for '{jail_name}': {e}")
            return None

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
        path = Path(self.plugin_data) / filename
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)

if __name__ == "__main__":
    ctx = JRootContext()
    print(json.dumps(ctx.list_jails(), indent=2))
