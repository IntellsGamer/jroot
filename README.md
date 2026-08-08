# JRoot

### **A Linux environment that doesn't need root to exist.**

> **Run Ubuntu. Install packages. Get a root-like environment.**
>
> **The host stays unprivileged.**

[![Rootless](https://img.shields.io/badge/ROOTLESS-100%25-2ea44f?style=for-the-badge)](#)
[![PRoot](https://img.shields.io/badge/POWERED%20BY-PROOT-6f42c1?style=for-the-badge)](#)
[![Ubuntu](https://img.shields.io/badge/UBUNTU-16.04%20%E2%86%92%2026.04-E95420?style=for-the-badge\&logo=ubuntu\&logoColor=white)](#)
[![Bash](https://img.shields.io/badge/BASH-RUNTIME-121011?style=for-the-badge\&logo=gnu-bash\&logoColor=white)](#)

```text
HOST
 │
 │  ordinary user
 ▼
┌──────────────────────────────────┐
│              JRoot               │
│                                  │
│  filesystem mapping              │
│  identity mapping                │
│  package management              │
│  snapshots & revert              │
│  security layer (seccomp)        │
│  read-only mounts (LD_PRELOAD)   │
│  port binding control            │
│  file transfer (host ↔ jail)     │
└────────────┬─────────────────────┘
             │
             ▼
        ┌─────────┐
        │  PRoot  │
        └────┬────┘
             │
             ▼
       ┌─────────────┐
       │   Ubuntu    │
       │  userspace  │
       └─────────────┘
```

```bash
$ jroot init ubuntu:22.04

$ jroot enter ubuntu

root@ubuntu:~# whoami
root

root@ubuntu:~# apt install git python3 gcc
```

```bash
$ id
uid=1000(...)
```

**No host root. No VM. No privileged `chroot`.**

Just userspace.

---

## What is JRoot?

JRoot is a rootless Linux jail manager built around **PRoot**.

It creates complete Linux root filesystems and runs them from an ordinary user account, providing a configurable environment with package management, networking, filesystem mapping, root/unroot execution modes, snapshots, diagnostics, and optional security hardening.

Everything lives under the user's JRoot directory. No system daemon is required, and the host does not need to grant JRoot administrative privileges.

## Installation

1. Download the assets:
```bash
curl -L -O https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/install-jroot.sh
curl -L -O https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/jroot
```

Or if you prefer using wget:
```bash
wget https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/install-jroot.sh
wget https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/jroot
```

3. Run the installer:
```bash
bash install-jroot.sh
```

4. Use jroot:
```bash
jroot help
```

### The interesting part?

A JRoot environment is fundamentally a directory.

```text
~/.jroot/
│
├── roots/
│   └── ubuntu/
│       ├── bin/
│       ├── etc/
│       ├── home/
│       ├── usr/
│       └── var/
│
├── configs/
│   └── ubuntu.json
│
├── snapshots/
│   └── ubuntu/
│
├── cache/
│   └── ubuntu-base-*.tar.gz
│
└── bin/
    ├── proot
    ├── seccomp-launcher
    └── libjroot.so
```

Inside the jail, that same directory becomes:

```text
/
├── bin
├── etc
├── home
├── usr
└── var
```

The files didn't move.

The computer didn't become a VM.

The kernel didn't get replaced.

**The process simply receives a different view of its environment.**

> ### **JRoot doesn't change the computer.**
>
> ### **It changes how the process thinks it exists.**

That's the core idea.

---

# ⚡ What can it actually do?

|     | Capability                  |  JRoot  |
| :-: | --------------------------- | :-----: |
|  👤 | Host root required          |  **No** |
|  🐧 | Full Ubuntu userspace       | **Yes** |
|  👑 | Root-like inner environment | **Yes** |
|  👤 | Unrooted inner environment  | **Yes** |
|  📦 | APT / DPKG                  | **Yes** |
|  🌐 | Networking                  | **Yes** |
| 🗺️ | Filesystem mapping          | **Yes** |
| 🔒 | Read-only mount enforcement | **Yes** |
| 🚪 | Port binding control        | **Yes** |
| 📁 | File transfer (host ↔ jail) | **Yes** |
|  📸 | Full rootfs snapshots       | **Yes** |
|  ↩️ | Snapshot restoration        | **Yes** |
| 🏷️ | Jail rename                 | **Yes** |
|  🩺 | Installation diagnostics    | **Yes** |
| 🛡️ | Seccomp protection          | **Yes** |
| 🖥️ | Interactive command shell   | **Yes** |
|  ⚙️ | System-wide daemon          |  **No** |

The project is deliberately aimed at the gap between **"I have a Linux account"** and **"I have administrative control of this machine."**

---

# 👑 Root mode

JRoot can create an environment whose normal entry point runs with PRoot's fake-root mapping.

```bash
jroot enter ubuntu
```

Inside:

```bash
root@ubuntu:~# whoami
root

root@ubuntu:~# id
uid=0(root) gid=0(root)
```

That identity applies **inside the JRoot environment**.

It does not turn the host account into UID 0.

JRoot can also explicitly execute commands as root:

```bash
jroot enter ubuntu --root <command>
```

The implementation exposes both the normal jail user and an explicit root execution path.

---

# 👤 Unrooted mode

Root isn't always what you want.

JRoot supports an unrooted jail mode where the environment is prepared with root privileges during installation, but normal entry uses a non-root user.

```text
                 JRoot
                   │
          ┌────────┴────────┐
          │                 │
          ▼                 ▼
       👤 unroot          👑 root
       normal use       administration
```

The root password can be locked while the normal environment runs as the inner unprivileged user.

That makes it possible to use JRoot as a development environment without making fake root the default.

---

# 📦 Real Linux software

This isn't a toy shell pretending to be Ubuntu.

JRoot bootstraps an actual Ubuntu root filesystem and configures it for package management. The current implementation downloads Ubuntu Base images, extracts them into the jail rootfs, and configures APT for the selected Ubuntu release.

Inside the environment:

```bash
apt update

apt install git
apt install python3
apt install gcc
apt install build-essential
```

You can then use the normal tools you'd expect:

```text
Python
Git
GCC
SSH
curl
wget
vim
nano
tmux
htop
rsync
node (x86_64)
and the rest of Ubuntu's package ecosystem
```

JRoot's job is not to invent another Linux package manager.

Its job is to make the existing one work in a rootless userspace.

---

# 🌐 Networking

The environment doesn't need a privileged network namespace just to communicate with the outside world.

PRoot runs the userspace environment while the underlying host network remains available.

That means software inside JRoot can do things like:

```bash
curl https://example.com
git clone ...
apt update
ssh ...
```

without requiring host root.

---

# 🗺️ Filesystem mapping

This is where the "it's just a folder" idea becomes useful.

JRoot maps the jail rootfs to `/` from the process's point of view.

Optional mappings can also expose parts of the host when explicitly enabled.

### Host filesystem

```text
/home/user
/
```

### JRoot view

```text
/
├── home/
├── etc/
├── usr/
└── mnt/
    ├── host/          (optional: host /)
    ├── home/          (optional: host $HOME)
    └── <label>/       (custom: host directory)
```

Host `/`, host `$HOME`, and custom directories are configurable.

### Custom mounts with `jroot mnt`

```bash
# Mount a host directory read-write
jroot mnt dev project ~/myproject

# Mount read-only (all writes return EROFS)
jroot mnt dev secrets ~/secrets ro

# List mounts
jroot mnt dev list

# Change mount mode
jroot mnt dev set project ro

# Remove a mount
jroot mnt dev rm project
```

**Read-only mounts are enforced at the syscall level** via an LD_PRELOAD shim that intercepts `open()`, `creat()`, `mkdir()`, `unlink()`, `rename()`, `chmod()`, `chown()`, and every other write syscall, returning `EROFS`.

A jail shouldn't accidentally become:

> "Ubuntu, except surprise, here's your entire host."

---

# 🚪 Port binding control

Jailed servers are **loopback-only by default**. This is a deliberate security choice.

```bash
# Inside the jail, a web server on port 3000
# is ONLY reachable from inside the jail by default

# Make port 3000 public (binds to 0.0.0.0)
jroot port dev add 3000

# List public ports
jroot port dev list

# Make port 3000 loopback-only again
jroot port dev rm 3000
```

The implementation uses an LD_PRELOAD shim that intercepts `bind()` and forces loopback addresses unless the port is whitelisted.

```text
Jailed server tries to bind 0.0.0.0:3000
              │
              ▼
         LD_PRELOAD shim
              │
    ┌─────────┴─────────┐
    │                   │
    ▼                   ▼
port in whitelist    port not whitelisted
    │                   │
    ▼                   ▼
allow 0.0.0.0      force 127.0.0.1
```

This prevents accidental exposure of services running inside jails.

---

# 📁 File transfer

Moving files between host and jail is a common pain point. JRoot solves it with `jroot file`.

```bash
# Copy from host to jail
jroot file cp dev ~/app.tar.gz :/root/app.tar.gz

# Copy from jail to host
jroot file cp dev :/root/log.txt ./log.txt

# Move a file
jroot file mv dev :/tmp/old.log :/tmp/new.log
```

Paths prefixed with `:` are inside the jail. Everything else is on the host.

```text
host path         →  /home/user/app.tar.gz
jail path (:)     →  /root/app.tar.gz
```

The file operation copies or moves directly between the two filesystem views.

---

# 📸 Snapshots

JRoot can save the complete rootfs and its configuration as a snapshot.

```bash
jroot snapshot ubuntu before-test
```

Then:

```text
ubuntu/
   │
   ├── experiment
   ├── experiment
   ├── experiment
   └── 💥
```

Something breaks?

```bash
jroot revert ubuntu before-test
```

The snapshot system stores the root filesystem as a compressed archive alongside the jail configuration and restores both together.

### Useful commands

```bash
jroot snapshots ubuntu
jroot snapshot ubuntu clean
jroot revert ubuntu clean
jroot rm-snapshot ubuntu clean
```

---

# 🏷️ Rename a jail

Jails can be renamed without losing their state.

```bash
jroot rename ubuntu-dev ubuntu-staging
```

The rename operation updates:

```text
~/.jroot/
├── roots/ubuntu-dev     →  roots/ubuntu-staging
├── configs/ubuntu-dev.json → configs/ubuntu-staging.json
└── snapshots/ubuntu-dev/ → snapshots/ubuntu-staging/
```

The jail's hostname, `/etc/hosts`, and shell prompt are also updated to reflect the new name.

---

# 🖥️ Interactive command shell

For repetitive tasks, JRoot offers an interactive shell where you don't need to type `jroot` every time.

```bash
jroot shell

jroot> list
NAME             IMAGE           USER     MNT/  MNT~  BUILD ROOTFS
dev              ubuntu:22.04    root     0     0     1     /home/user/.jroot/roots/dev

jroot> enter dev
root@dev:~# exit
exit

jroot> help init
jroot init - create a jail from an Ubuntu image
...

jroot> exit
Bye!
```

Type `help` for commands, `exit` to leave. All jroot commands work without the prefix.

---

# 🩺 `jroot doctor`

Because eventually something will break.

That's Linux.

```bash
jroot doctor
```

JRoot checks:

* JRoot storage
* required directories
* PRoot
* Python
* seccomp launcher
* port shim (`libjroot.so`)
* jail configuration
* rootfs integrity
* rootfs size

and produces a simple summary:

```text
[PASS] jroot home writable: /home/user/.jroot
[PASS] proot binary: /home/user/.jroot/bin/proot  (v5.3.0)
[PASS] python3 (seccomp launcher): /usr/bin/python3
[PASS] seccomp launcher: /home/user/.jroot/bin/seccomp-launcher
[PASS] jail 'dev' config
[PASS] jail 'dev' rootfs    /home/user/.jroot/roots/dev (245M)

Summary: 6 ok, 0 warn, 0 fail
```

The diagnostic system is implemented directly in JRoot rather than relying on a collection of external commands.

---

# 🧹 Cleaning and disk usage

### `jroot clean` – free disk space

```bash
jroot clean dev
# Removes apt caches, package lists, debconf, temp files
# Also trims /usr/share/doc and /var/log for build-essential jails
```

### `jroot size` – see disk usage

```bash
jroot size
JAIL                 ROOTFS   SNAPSHOTS
dev                   245M        12M
ubuntu-test           180M       0B
```

---

# 🛡️ Security

PRoot is powerful because it can provide filesystem and process translation without requiring privileged mounts.

That power also means its attack surface deserves attention.

JRoot includes a seccomp-based launcher designed to block the `openat2` syscall (437) before PRoot starts.

```text
JRoot
  │
  ▼
seccomp launcher
  │
  ├── NO_NEW_PRIVS
  └── syscall filtering (blocks openat2)
  │
  ▼
 PRoot
  │
  ▼
Ubuntu userspace
```

The runtime checks for the launcher and reports whether the protection is available through `jroot doctor`.

### Additional security features

1. **Loopback-only by default** – Jailed servers only listen on `127.0.0.1` unless explicitly whitelisted with `jroot port`
2. **Read-only mount enforcement** – `jroot mnt ... ro` blocks ALL write syscalls via LD_PRELOAD
3. **Host mount warnings** – JRoot warns when host `/` or `$HOME` are deliberately mounted
4. **Unroot mode** – Root account can be locked, daily use is a non-root user
5. **Clean environment** – `LD_PRELOAD`, `LD_LIBRARY_PATH`, and proxy env vars are unset on enter

### Important

JRoot is **not a virtual machine**.

It is **not kernel-level container isolation**.

It should not be treated as a security boundary for hostile workloads.

The goal is rootless Linux environments, not pretending a userspace process can defeat the kernel.

---

# 🐳 JRoot vs. containers

JRoot and Docker solve different problems.

|                        | **JRoot** | **Docker** | **`chroot`** |   **VM**  |
| ---------------------- | :-------: | :--------: | :----------: | :-------: |
| Host root required     |     ❌     |   Usually  |       ✅      |  Usually  |
| Separate kernel        |     ❌     |      ❌     |       ❌      |     ✅     |
| Full Linux userspace   |     ✅     |      ✅     |       ✅      |     ✅     |
| Userspace root mapping |     ✅     |      —     |       ❌      |     —     |
| Namespaces             |     ❌     |      ✅     |       ❌      |    N/A    |
| cgroups                |     ❌     |      ✅     |       ❌      |    N/A    |
| VM isolation           |     ❌     |      ❌     |       ❌      |     ✅     |
| Runs as ordinary user  |   **✅**   |  Usually ❌ |       ❌      | Usually ❌ |
| System daemon          |   **❌**   |      ✅     |       ❌      |  Depends  |
| Port isolation         |   **✅**   |      ✅     |       ❌      |     ✅     |
| Read-only mounts       |   **✅**   |      ✅     |       ❌      |     ✅     |
| Built-in snapshots     |   **✅**   |      —     |       ❌      |     —     |

JRoot isn't trying to replace kernel-level containers where those are available.

It's useful when they **aren't**.

---

# 🧰 One command instead of the ritual

The original problem wasn't:

> "Can PRoot execute Ubuntu?"

It can.

The problem was everything around it.

APT configuration.

Rootfs downloads.

Architecture detection.

Certificates.

DNS.

DPKG behavior.

Identity mapping.

Package bootstrapping.

Environment cleanup.

Snapshots.

Security.

Configuration.

File transfer.

Port management.

Mount management.

And eventually:

```text
"Why the hell does this package think that file exists?"
```

JRoot turns that collection of problems into one interface.

```bash
jroot init ubuntu:22.04
```

The current CLI handles runtime installation, rootfs acquisition, configuration, bootstrapping, and jail creation as one workflow.

---

# 🎛️ JRoot CLI

```text
CREATE & USE

  jroot init <image> [flags]       Create a jail
  jroot enter <name>               Enter a jail (interactive shell)
  jroot enter <name> <command>     Run a command inside a jail
  jroot enter <name> --root ...    Run a command as root
  jroot exec <name> [--root] <cmd> Run one command (no shell wrapping)
  jroot shell                      Interactive jroot command shell
  jroot install <name> <packages>  Install apt packages
  jroot config <name>              Configure a jail


FILE & PORT MANAGEMENT

  jroot file cp <name> <src> <dst> Copy files (host ↔ jail)
  jroot file mv <name> <src> <dst> Move files (host ↔ jail)
  jroot port <name> list           Show public ports
  jroot port <name> add <port>     Make a port public (0.0.0.0)
  jroot port <name> rm <port>      Make a port loopback-only (127.0.0.1)
  jroot mnt <name> list            Show custom mounts
  jroot mnt <name> <label> <dir>   Mount host directory at /mnt/<label> (rw)
  jroot mnt <name> <label> <dir> ro Mount read-only
  jroot mnt <name> set <label> rw|ro Change mount mode
  jroot mnt <name> rm <label>      Unmount /mnt/<label>


INSPECTION

  jroot list [--json]              List all jails
  jroot info [name]                Show jail details
  jroot size [name]                Show disk usage per jail
  jroot doctor                     Diagnose JRoot


SNAPSHOTS

  jroot snapshot <name> [label]    Save a snapshot
  jroot snapshots <name>           List snapshots
  jroot revert <name> [label]      Restore a snapshot
  jroot rm-snapshot <name> <label> Delete a snapshot


MAINTENANCE

  jroot update [name]              Update runtime/packages
  jroot clean <name>...            Free disk space inside a jail
  jroot rename <name> <newname>    Rename a jail
  jroot rm <name>                  Delete a jail
  jroot help [command]             Show help
```

These aren't hypothetical commands. They're the actual command structure implemented by the current JRoot script.

---

# ⚙️ Configuration

Each jail has its own configuration.

```json
{
  "name": "dev",
  "image": "ubuntu:22.04",
  "user": "root",
  "mount_host": 0,
  "mount_home": 0,
  "build_essential": 1,
  "ports": [3000, 8080],
  "mounts": [
    ["project", "/home/user/project", "rw"],
    ["secrets", "/home/user/secrets", "ro"]
  ]
}
```

Among the available settings are:

```text
user            root or unroot
build_essential 0 or 1
mount_host      0 or 1 (host / at /mnt/host)
mount_home      0 or 1 (host $HOME at /mnt/home)
ports           list of public ports (bind to 0.0.0.0)
mounts          list of [label, hostpath, mode] (mode: rw or ro)
```

That means you don't have to rebuild an environment just because you want to change how it behaves.

```bash
jroot config dev
```

Configuration is stored separately from the rootfs, which also allows snapshots to preserve the environment's configuration alongside its filesystem.

---

# 🧠 How it works

At the bottom of the stack, the host still owns:

```text
CPU
Memory
Kernel
Devices
Network
```

JRoot doesn't emulate those.

Instead:

```text
                ┌───────────────────────────────────┐
                │              JRoot                │
                │                                   │
                │  CLI                              │
                │  jail configuration               │
                │  rootfs management                │
                │  snapshots                        │
                │  security (seccomp)               │
                │  port shim (bind() LD_PRELOAD)    │
                │  mount shim (write syscalls)      │
                └───────────┬───────────────────────┘
                            │
                            ▼
                     ┌────────────┐
                     │   PRoot    │
                     └─────┬──────┘
                           │
                    filesystem /
                    process view
                           │
                           ▼
                 ┌──────────────────┐
                 │ Ubuntu rootfs    │
                 └────────┬─────────┘
                          │
                          ▼
                    Linux kernel
                          │
                          ▼
                       Hardware
```

The result is not hardware emulation.

It is **userspace translation**.

That is why something as mundane as:

```text
~/.jroot/roots/ubuntu
```

can become:

```text
/
```

to a process running inside it.

---

# 📁 Everything is a jail

JRoot can manage multiple independent environments:

```text
~/.jroot/
│
├── roots/
│   ├── ubuntu-dev/
│   ├── ubuntu-test/
│   └── ubuntu-build/
│
├── configs/
│   ├── ubuntu-dev.json
│   ├── ubuntu-test.json
│   └── ubuntu-build.json
│
└── snapshots/
    ├── ubuntu-dev/
    └── ubuntu-test/
```

List them:

```bash
jroot list
```

Inspect one:

```bash
jroot info ubuntu-dev
```

Remove one:

```bash
jroot rm ubuntu-test
```

The jail is a filesystem, configuration, and runtime mapping managed as one unit.

---

# 🔬 From experiment to runtime

JRoot started from a much smaller idea:

```text
PRoot
   +
Ubuntu Base
   +
APT
   +
networking
```

Making that actually behave like a usable Linux environment required dealing with the ugly details.

The current runtime includes compatibility handling for APT/DPKG, HTTPS repositories, architecture-specific rootfs downloads, environment setup, package bootstrapping, PRoot execution, seccomp filtering, port binding control, mount management, file transfer, interactive shell, and snapshot management.

The result is something considerably more useful than:

```bash
proot -0 -r ./ubuntu
```

It is a **manager around the entire environment**.

---

# 🚧 Roadmap

JRoot is still evolving.

The project is focused on improving:

* filesystem mapping
* identity mapping
* security
* compatibility
* networking
* environment configuration
* root/unroot behavior
* architecture support
* performance
* diagnostics
* snapshot management
* port management
* mount management
* file transfer
* interactive shell
* tab completion

The underlying idea stays the same:

> **More capability in userspace. Less dependence on host privileges.**

---

# ⚠️ Limitations

JRoot deliberately does **not** try to hide what it is.

It uses PRoot.

That means:

* there is runtime overhead compared with native execution
* some applications expecting kernel-level isolation won't behave the same way
* system services requiring real kernel features may not work normally
* it is not a VM
* it is not a replacement for kernel namespaces
* fake root does not grant host capabilities

JRoot is best viewed as a **rootless Linux userspace environment**, not a magical privilege escalation mechanism.

---

# 🤝 Contributing

There is a lot of interesting work hiding underneath a project like this.

Especially:

* PRoot compatibility
* filesystem translation
* identity mapping
* seccomp
* package-manager behavior
* architecture support
* networking
* performance
* isolation
* rootless tooling
* port binding
* read-only mount enforcement
* snapshot management
* file transfer
* interactive shell

If something behaves strangely under JRoot, that's probably interesting.

Because somewhere underneath:

```text
process
   ↓
PRoot
   ↓
syscall
   ↓
filesystem mapping
   ↓
host kernel
```

something is making a decision.

And that's usually where the fun starts.

---

<div align="center">

# JRoot

### **Rootless Linux, built from userspace.**

**No host root.**
**No VM.**
**No privileged `chroot`.**

Just a Linux userspace running somewhere it technically shouldn't be this easy to run.

</div>
