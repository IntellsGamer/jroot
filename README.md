# JRoot

### **A Free Rooted\* Linux environment that doesn't need root to exist.**

> **Run Ubuntu. Install packages. Get a root-like environment.**
>
> **The host stays unprivileged.**
> 
> *While JRoot provides access to sudo inside a semi-container, the root is not real and some capacities may be limited from kernel directly.

[![Rootless](https://img.shields.io/badge/ROOTLESS-100%25-2ea44f?style=for-the-badge)](#)
[![PRoot](https://img.shields.io/badge/POWERED%20BY-PROOT-6f42c1?style=for-the-badge)](#)
[![Ubuntu](https://img.shields.io/badge/UBUNTU-16.04%20%E2%86%92%2026.04-E95420?style=for-the-badge\&logo=ubuntu\&logoColor=white)](#)
[![Bash](https://img.shields.io/badge/BASH-RUNTIME-121011?style=for-the-badge\&logo=gnu-bash\&logoColor=white)](#)

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

## Installation

1. Download the assets:
```bash
curl -L -O https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/install-jroot.sh
curl -L -O https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/jroot
curl -L -O https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/jroot_sdk.py
```

Or if you prefer using wget:
```bash
wget https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/install-jroot.sh
wget https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/jroot
wget https://raw.githubusercontent.com/IntellsGamer/jroot/refs/heads/main/jroot_sdk.py
```

2. Run the installer:
```bash
bash install-jroot.sh
```

3. Use jroot:
```bash
jroot help
```

### From a clone

If you have the repository, the Makefile wraps the same installer and adds the
verification targets:

```bash
make install      # to ~/.local/bin, no root needed
make check        # lint the script, compile the embedded C shim, self-test it
make test         # check + drive the CLI against a throwaway JROOT_HOME
make version      # script/shim/proot versions, and whether the install is current
make uninstall    # remove the script, keep every jail
make purge        # remove the script AND all jails (asks first)
```

`make dev-install` symlinks instead of copying, so the installed command tracks
your checkout. `sudo make install PREFIX=/usr/local` installs system-wide, if
you would rather have that than a user-local install.

---

## What is JRoot?

JRoot is a rootless Linux jail manager built around **PRoot**.

It creates complete Linux root filesystems and runs them from an ordinary user account, providing a configurable environment with package management, networking, filesystem mapping, root/unroot execution modes, snapshots, diagnostics, and optional security hardening.

Everything lives under the user's JRoot directory. No system daemon is required, and the host does not need to grant JRoot administrative privileges.

```text
HOST
 │
 │  ordinary user
 ▼
┌────────────────────────────────────┐
│              JRoot                 │
│                                    │
│  filesystem mapping                │
│  identity mapping                  │
│  package management                │
│  snapshots, checkpoints & revert   │
│  JRootfile reproducible builds     │
│  security layer (seccomp+landlock) │
│  per-jail loopback address         │
│  /proc process filtering           │
│  read-only mounts (LD_PRELOAD)     │
│  port binding control              │
│  ssh access (persistent daemon)    │
│  file transfer (host ↔ jail ↔ jail)│
│  tab completion (bash/zsh/fish)    │
└────────────┬───────────────────────┘
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

---

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
├── builds/
│   └── my-service.json
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
| 🔑 | SSH into a jail             | **Yes** |
| 📁 | File transfer (any direction) | **Yes** |
|  📸 | Full rootfs snapshots       | **Yes** |
|  ⚡ | Incremental checkpoints     | **Yes** |
|  🧬 | Clone from saved state      | **Yes** |
|  ↩️ | Snapshot/checkpoint restore | **Yes** |
|  🧱 | Dockerfile-like JRoot builds | **Yes** |
|  🔄 | Checkpointed package updates | **Yes** |
| 🏷️ | Jail rename                 | **Yes** |
|  🩺 | Installation diagnostics    | **Yes** |
| 🛡️ | Seccomp protection          | **Yes** |
| 🖥️ | Interactive command shell   | **Yes** |
| ⌨️ | Tab completion (bash/zsh/fish) | **Yes** |
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
allow 0.0.0.0      force the jail's own address
```

This prevents accidental exposure of services running inside jails.

---

# 🏷️ Per-jail loopback addresses

Every jail owns one address inside `127/8` — `127.2.0.1`, `127.2.0.2`, and so on — assigned on first use and stored in its config. Non-public listeners are pinned to that address instead of `127.0.0.1`.

The practical result: **three jails can each run a dev server on port 8080 at the same time**, and the host reaches each one separately. Port collisions stop being something you have to think about.

```bash
jroot net
JAIL             ADDRESS          PUBLIC PORTS   DISTRO
api              127.2.0.1        none           ubuntu
web              127.2.0.2        8080           ubuntu
tiny             127.2.0.3        none           alpine
```

```bash
# inside jail 'api'
python3 -m http.server 8080        # asks for 0.0.0.0:8080
# actually bound to 127.2.0.1:8080

# from the host
curl http://127.2.0.1:8080/        # 200
curl http://127.0.0.1:8080/        # connection refused
```

`localhost` still works *inside* the jail: `connect()` is redirected the same way, so a client in the jail that dials `127.0.0.1:8080` reaches its own server. The trade-off is that a jail can no longer reach services on the **host's** `127.0.0.1`. DNS is exempt — port 53 is never redirected, so a resolver on host loopback keeps working.

```bash
jroot net set web 127.2.9.9   # pick an address by hand
jroot net set web auto        # back to the next free one
jroot net set web off         # share 127.0.0.1 with the host, like before
```

Public ports are unaffected: `jroot port web add 8080` binds `0.0.0.0` and ignores the jail address.

> **The deliberate trade-off: a jail can no longer reach host services on 127.0.0.1. `jroot net set <name> off` restores the old shared behaviour.**

---

# 👀 Process isolation in `/proc`

PRoot binds the host `/proc`, so without help a jailed `ps aux` lists every process on the machine, command lines included, and `pkill` inside a jail can match host processes by accident.

The shim filters `/proc` at **two levels**:

1. **Directory listing** — `readdir()` on `/proc` skips numeric entries (PIDs) that don't belong to this jail
2. **Direct path access** — `open()`, `stat()`, `access()`, `readlink()`, and every other syscall on `/proc/<pid>/...` returns `ENOENT` for foreign PIDs

```bash
$ ps -e | wc -l      # on the host
29

$ jroot exec dev ps -e
    PID TTY          TIME CMD
  28938 ?        00:00:00 bash
  28980 ?        00:00:00 proot
  28981 ?        00:00:00 sh
  28982 ?        00:00:00 ps

# Even direct access to a host PID is blocked:
$ jroot exec dev cat /proc/1/cmdline
cat: /proc/1/cmdline: No such file or directory
```

Membership is decided two ways: a process is part of the jail if the same PRoot instance traces it — which covers daemons that double-forked and were reparented to host PID 1 — or if its parent chain leads back to the jail's root process. When `JROOT_PROC_ROOT` is missing, the shim falls back to "whoever is tracing me", which inside a jail is always PRoot.

This covers the glibc `readdir()` path (`ls`, `ps`, `htop`, Python's `os.listdir`) **and** direct path access (`open`, `stat`, `readlink`). A statically-linked binary issuing raw `getdents64()` still sees everything, as does anything that bypasses the dynamic linker. Set `JROOT_SHOW_ALL_PROCS=1` to turn it off.

It applies to SSH sessions too, not just `jroot enter` — see [the session environment](#the-session-environment) for why that needed explicit work.

---

# 🔑 SSH access

JRoot can expose a jail over SSH so you can connect from another machine — or from the same machine in a different terminal — without needing an interactive `jroot enter` session open.

```bash
# Start SSH (auto-assigns a port in 22001-22099, prompts for a password)
jroot ssh dev start

# Start on a specific port
jroot ssh dev start 20022
jroot ssh dev start --port=20022

# Check status (also verifies the handshake, not just the socket)
jroot ssh dev status

# Rotate the password
jroot ssh dev passwd

# Read sshd's own log
jroot ssh dev log

# Stop
jroot ssh dev stop
```

### Ports

`sshd` binds the port directly on `0.0.0.0`. The port is added to the jail's public list, so the `bind()` shim leaves it there instead of pinning it to the jail's loopback address — no redirector process, nothing to keep in sync.

```text
Remote client
     │  ssh -p 22001 jail@host
     ▼
┌────────────────────────────────────────────┐
│ JAIL   sshd -D   0.0.0.0:22001             │
│        (persistent proot, own pgroup)      │
└────────────────────────────────────────────┘
```

The port must be **above 1024**. Fake root is not `CAP_NET_BIND_SERVICE`: `getuid()` returns 0, but the kernel still sees your unprivileged host UID, so `bind()` below 1024 fails with `EACCES`. JRoot refuses such a port with a suggestion rather than starting a daemon that cannot listen.

> The shim *can* remap a port a service insists on (`JROOT_PORT_MAP="80=8080"`, useful for daemons with a hardcoded privileged port), but remapping does not make the low port reachable, so `jroot ssh` does not use it.

### Privilege separation and auditing

Two things in OpenSSH assume real root and treat failure as fatal. Both had to be handled, and both are worth knowing about because the symptoms are misleading.

**1. The pre-auth chroot.** OpenSSH's privilege-separated child hardens itself by chrooting into an empty directory:

```text
chroot("/run/sshd"): Operation not permitted [preauth]
```

`chroot(2)` requires `CAP_SYS_CHROOT`, which fake root does not provide, and OpenSSH **removed `UsePrivilegeSeparation` in 7.5** — so it cannot be configured off. The symptom is brutal: the daemon starts, accepts the TCP connection, then closes it before sending its version banner, and the client only says `Connection closed by <host> port <port>`.

**2. The audit record.** This one is worse, because it happens *after* a successful password check:

```text
Accepted password for root from 127.0.0.1 port 52744 ssh2
Starting session: shell on pts/2 for root
linux_audit_write_entry failed: Unknown error -1
```

The client sees `Connection to <host> closed` right after typing the correct password, which looks exactly like an auth failure. Writing audit records needs `CAP_AUDIT_WRITE`, and OpenSSH refuses to allow an unaudited login.

JRoot starts `sshd` with `JROOT_FAKE_PRIVSEP=1`, and the shim reports success for exactly those steps:

| Call | Faked | Why |
| --- | --- | --- |
| `chroot()` | → `0` | proot already confines the filesystem |
| `prctl(PR_SET_SECCOMP)` | → `0` | JRoot installed its own filter before proot |
| `setgroups()` / `initgroups()` | → `0` | no supplementary groups to drop |
| `audit_open()` | → `EPROTONOSUPPORT` | OpenSSH already has a "kernel has no audit support" path; this jail genuinely has none |
| `prctl(PR_SET_NO_NEW_PRIVS)` | **not faked** | it works, and it costs nothing |

The `audit_open()` case is not a lie so much as an accurate answer: OpenSSH explicitly accepts `EINVAL`, `EPROTONOSUPPORT` and `EAFNOSUPPORT` as "no audit subsystem here, carry on", and a rootless jail has no usable one.

This is a scoped trade, and it is worth being precise about what it costs: it removes a layer of **sshd's own** defence in depth, not a layer of the jail. The rootfs boundary still comes from proot, the syscall filter from JRoot's seccomp launcher, and the path allowlist from Landlock. The variable is opt-in — `jroot ssh` sets it for the `sshd` it starts, and nothing else does.

Because the shim is what makes this work, a jail without a working shim cannot run `sshd`. JRoot says so explicitly and points at `jroot install <name> gcc`.

### The session environment

`sshd` builds a **clean environment for every login** and deliberately drops `LD_PRELOAD`. That meant an SSH session originally ran with no shim at all, while `jroot enter` on the same jail behaved correctly — a difference you could see immediately:

```bash
# over SSH, before the fix: every host process visible
root@dev1:/$ ps aux | wc -l
32

# jroot enter, same jail, same moment
root@dev1:~$ ps aux | wc -l
4
```

Losing the shim did not just make `ps` noisy. It also meant `~/.jroot` became visible inside host mounts, read-only mounts stopped returning `EROFS`, and jailed servers no longer bound to the jail's own loopback address.

JRoot fixes this with a generated `ForceCommand` wrapper at `/usr/local/bin/jroot-session` inside the jail, which restores the environment and then becomes the requested shell:

```text
ssh login
   │
   ▼
sshd  (clean env, no LD_PRELOAD)
   │  ForceCommand
   ▼
jroot-session
   ├── JROOT_PROC_ROOT  ← read from TracerPid (this jail's proot)
   ├── JROOT_PORTS / JROOT_LOOPBACK / JROOT_RO_MOUNTS  ← from the jail config
   ├── LD_PRELOAD=/usr/local/lib/libjroot.so
   ▼
exec $SHELL -l      (or $SHELL -c "<command>", or sftp-server)
```

`JROOT_PROC_ROOT` is read at session time from `/proc/self/status` rather than baked in, because the process tracing the session *is* this jail's proot, and that pid changes every time the daemon restarts.

The wrapper is regenerated on every `jroot ssh <name> start`, so config changes take effect on the next login, and it handles all three session types — interactive shells, `ssh host <command>` and `scp`, and the `sftp` subsystem. As a second line of defence, the shim now also falls back to "whoever is tracing me" when `JROOT_PROC_ROOT` is absent, so a process that somehow bypasses the wrapper still gets `/proc` filtering.

### Passwords

**There is no default password and nothing is hardcoded.** With no flags, `jroot ssh <name> start` prompts with echo off; pressing Enter instead generates a 24-character random password and prints it exactly once.

```bash
jroot ssh dev start                          # prompt (echo off)
jroot ssh dev start --random-password        # generate, print once
pass show jail/dev | jroot ssh dev start --password-stdin
jroot ssh dev start --password=hunter2       # warns: lands in shell history
jroot ssh dev passwd                         # rotate later
```

The rules the implementation follows:

- The plaintext never touches the host filesystem, never appears in `argv` (which is world-readable through `/proc` on the host), and never reaches the history log — only `password set for 'jail' (source: prompt)` is recorded.
- It reaches `chpasswd` through a pipe on stdin. If `chpasswd` is missing, JRoot falls back to `passwd`, then to hashing on the host and rewriting the shadow entry.
- A generated password is shown once and cannot be recovered, only replaced.
- Short passwords are questioned rather than quietly accepted.

### Key-based login

```bash
jroot ssh dev start --key=~/.ssh/id_ed25519.pub                # password or key
jroot ssh dev start --key=~/.ssh/id_ed25519.pub --no-password   # key only
```

JRoot refuses a private key by mistake and checks the file actually looks like an OpenSSH public key.

### Hardening applied to the generated `sshd_config`

- `PermitRootLogin no` unless the login account *is* root, or you pass `--permit-root`
- `AllowUsers <the one account>` — nothing else can log in
- `PermitEmptyPasswords no`, `MaxAuthTries 4`, `LoginGraceTime 60`
- `PasswordAuthentication no` when `--no-password` is used
- `StrictModes no` and `UseDNS no` — both for proot-specific reasons: `StrictModes` rejects logins over home-directory ownership that a fake-root rootfs reports oddly, and `UseDNS` stalls every connection when the jail has no working resolver
- `LogLevel VERBOSE`, so the log is worth reading when something breaks

JRoot targets OpenSSH 7.2 (Ubuntu 16.04) through 9.x, and an unrecognised keyword is *fatal* rather than a warning. Instead of guessing per release, JRoot runs `sshd -t`, comments out whatever line it objects to, and repeats — so a deprecated keyword degrades into a comment instead of a daemon that will not start.

The login account defaults to `jail` for unroot jails and `root` for root jails; `--user=<name>` overrides it and the account is created if it does not exist. Only that account is unlocked — in an unroot jail, root stays locked. The unprivileged `sshd` privsep account is created too if the package's postinst failed to (which happens routinely under proot).

### Lifecycle

- The jail runs as a **persistent background daemon** (proot + `sshd -D`) in its own process group, so it survives closing your terminal, and stopping it cannot take your shell down with it.
- Startup waits for the socket to accept connections, **then reads the SSH banner**. A listening socket is not a working daemon — reading the banner is what catches a privsep failure at start time instead of leaving you with `Connection closed`.
- `jroot ssh <name> status` re-runs that handshake check, so it reports `FAILING` rather than `running` when the daemon is broken.
- An SSH session gets the same shim environment as `jroot enter`, via the generated `ForceCommand` wrapper described above.
- `jroot ps` lists SSH daemons alongside interactive shells; `jroot rm` stops the daemon first.

```bash
$ jroot ssh dev start --random-password
[+] Ensuring openssh-server is installed in 'dev'...

  Generated SSH password for jail:  7Kq2mXvB9pLdR4tYwZ3nHcFs
  Write it down now. It is not stored anywhere and cannot be shown again.
  Replace it any time with: jroot ssh dev passwd

[+] Starting SSH daemon for 'dev' on port 22001...
[+] SSH for 'dev' is running.
[+]   Port:          22001  (sshd listening on 0.0.0.0:22001)
[+]   Connect:       ssh -p 22001 jail@<host-ip>
[+]   Auth:          password
[+]   Only 'jail' may log in; root login is no.
[+]   Handshake:     verified (SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.16)
[+]   sshd log:      /home/user/.jroot/pids/dev.sshlog
[+]   The jail stays alive in the background for SSH access.

$ jroot ps
JAIL             PID      TYPE   COMMAND
dev              54321    sshd   port 22001
```

**Requirements:** `openssh-server` is installed inside the jail automatically on first start. On the host, `gcc` is needed once so the shim can be built — without it `sshd`'s `chroot()` cannot be faked and the daemon will not complete a handshake. `jroot doctor` reports whether the shim is active per jail.

---

# 🧩 One shim, many libcs

`libjroot.so` is compiled on the **host** but loaded by the **jail's** dynamic loader, so their libcs have to agree. A newer host is the common trap:

```text
/bin/bash: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found
           (required by /usr/local/lib/libjroot.so)
```

That breaks every command in the jail, not just the shim. JRoot avoids it by building the shim against a deliberately old symbol set — `-std=gnu11` (so glibc 2.38+ doesn't rewrite `strtol` into `__isoc23_strtol`), no `_FORTIFY_SOURCE` (no `__*_chk` symbols), and `dlsym` pinned to the platform's base version — which keeps one build usable from Ubuntu 16.04 to 26.04, and in practice inside musl jails too.

Compatibility is then **verified, not assumed**. On first use in each jail, JRoot preloads the shim and checks an observable side effect; the verdict is cached in `~/.jroot/.shim.<jail>`:

1. a shim built inside the jail wins, since it is ABI-correct by construction
2. otherwise the host build is used, if the probe shows it loads and works
3. otherwise JRoot compiles one inside the jail with its own `gcc`
4. otherwise the jail runs without the shim, with a warning explaining what is lost

`jroot doctor` reports which of those applies to each jail. `JROOT_SHIM_OFF=1` skips the shim entirely.

---

# 📁 File transfer

Moving files between host and jail is a common pain point. JRoot solves it with `jroot file`.

```bash
# Host to jail
jroot file cp ~/app.tar.gz dev:/root/app.tar.gz

# Jail to host
jroot file cp dev:/root/log.txt ./log.txt

# Jail to jail - either direction, any two jails
jroot file cp dev:/etc/nginx/nginx.conf web:/etc/nginx/nginx.conf

# Move instead of copy
jroot file mv dev:/tmp/build.log web:/tmp/build.log
```

A path written `<jail>:/path` is inside that jail. Anything else is a host path. At least one side has to be a jail path — for host-to-host, `cp` already exists.

```text
dev:/root/app.tar.gz   →  ~/.jroot/roots/dev/root/app.tar.gz
./app.tar.gz           →  the host path, as written
```

The jail side is resolved on the host, so no jail is started and nothing inside one is executed. Missing parent directories on the destination side are created.

**Paths are checked before anything is written.** `..` is refused outright, and a jail path is rejected when it resolves outside that jail's rootfs — the case that matters is an absolute symlink, which Ubuntu really does ship (`/lib -> /usr/lib`): resolved out here rather than under PRoot, "into the jail" would have meant the host's `/usr/lib`.

```bash
$ jroot file cp ./x dev:/root/../../../etc/passwd
[!] A jail path may not contain '..': 'dev:/root/../../../etc/passwd'
```

The older form still works, where the jail is named up front and a bare `:` means "in that jail":

```bash
jroot file cp dev ~/app.tar.gz :/root/app.tar.gz
```

Copies into a jail are recorded in `jroot history`, since they change it.


### Workspace synchronization

`jroot sync` mirrors a directory between the host and a jail, or in the reverse direction. It uses `rsync`, so repeated transfers are incremental; `--delete` removes destination files absent from the source, `--dry-run` previews changes, and `--watch` repeats a transfer after local filesystem changes.

```bash
# Host to jail
jroot sync ./my-app dev:/root/my-app

# Jail to host
jroot sync dev:/root/my-app ./my-app-backup

# Preview or continuously synchronize a workspace
jroot sync --dry-run ./my-app dev:/root/my-app
jroot sync --watch ./my-app dev:/root/my-app
```

---

# 📸 Snapshots & Checkpoints

JRoot provides two ways to save and restore jail states: **Snapshots** for long-term backups and **Checkpoints** for rapid experimentation.

### 📦 Snapshots
Snapshots are compressed `.tar.gz` archives of the entire rootfs and configuration. They are safe for long-term storage and can be moved between machines.

```bash
jroot snapshot dev before-major-upgrade
jroot snapshots dev
jroot revert snapshot dev before-major-upgrade
```

### ⚡ Checkpoints
Checkpoints preserve a quickly restorable filesystem state without creating a compressed archive. The first checkpoint is a private copy (using reflinks when available); later checkpoints reuse unchanged files from the prior immutable checkpoint with `rsync --link-dest`. This keeps later save points space-efficient without sharing writable inodes with the active jail.

```bash
jroot checkpoint dev pre-patch
jroot checkpoints dev
jroot revert checkpoint dev pre-patch
```

> **Note:** The first checkpoint is a private filesystem copy (using a reflink when the filesystem supports it). Later checkpoints use `rsync --link-dest` to share only unchanged files with an earlier immutable checkpoint; they never share writable inodes with the active jail. They are lightweight save points, not compressed archival snapshots.

### Compare two checkpoints

Use `jroot checkpoint diff` to inspect filesystem changes between two saved states without restoring either one.

```bash
jroot checkpoint diff dev before-upgrade after-upgrade
```

The output is concise: `A` means added, `D` removed, `M` file content, permission, or symlink-target change, `T` a file-type change, and `C` a changed saved jail-configuration field. Paths are shown from the rootfs root. The command is read-only and never starts the jail.

```text
M   /etc/app.conf
D   /var/cache/old-index
A   /usr/local/bin/new-tool
C   @config.limit_mem

Summary: 1 added, 1 removed, 1 modified, 0 type changed, 1 config changed
```

### Clone a saved state
Use `jroot clone` when you need a writable, independent copy of a known checkpoint or snapshot without changing the source jail. This is useful for reproducing a bug, rehearsing an upgrade, or trying a risky change against a preserved state.

```bash
# Start a disposable investigation jail from a fast checkpoint
jroot clone checkpoint dev pre-patch dev-investigation

# Recreate a separate jail from a compressed snapshot
jroot clone snapshot dev before-major-upgrade dev-archive-test
```

The clone receives the saved rootfs and configuration, but JRoot deliberately gives it a fresh host-facing identity. It clears public ports, host and custom mounts, and any assigned loopback address; it also removes inherited SSH host keys so `jroot ssh <clone> start` generates a distinct server identity. The source jail, checkpoint, and snapshot are not modified.

### Useful commands

| Command | Description |
|---|---|
| `jroot snapshot <name> [label]` | Create a compressed full backup |
| `jroot checkpoint <name> [label]` | Create a fast, incremental save point |
| `jroot clone checkpoint|snapshot <source> <label> <new-name>` | Create an isolated writable jail from a saved state |
| `jroot checkpoint diff <name> <a> <b>` | Compare filesystem and configuration changes between checkpoints |
| `jroot revert snapshot <name> <label>` | Restore from a compressed snapshot |
| `jroot revert checkpoint <name> <label>` | Restore from a fast checkpoint |
| `jroot snapshots <name>` | List all snapshots |
| `jroot checkpoints <name>` | List all checkpoints |
| `jroot rm-snapshot <name> <label>` | Delete a snapshot |
| `jroot rm-checkpoint <name> <label>` | Delete a checkpoint |


### Portability with `bundle` and `deploy`

Use `jroot bundle` to package a jail rootfs and its configuration into a compressed archive. `jroot deploy` restores that bundle on another JRoot host and may assign a new jail name during deployment.

```bash
jroot bundle dev my-dev-jail.tar.gz
jroot deploy my-dev-jail.tar.gz production-jail
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

# 🛑 Managing running jails

### `jroot ps` – list running jails

Shows every jail that currently has an active interactive shell or SSH daemon:

```bash
jroot ps
JAIL             PID      TYPE   COMMAND
dev              12345    shell  /bin/bash --login
staging          12346    shell  /bin/bash --login
dev              54321    sshd   port 22001
```

Stale PID files are automatically cleaned up when a jail exits or is killed.

### `jroot kill` – terminate a running jail

Kills the jail's shell process and all its children. This is equivalent to sending SIGTERM to the entire process group.

```bash
jroot kill dev
[+] Killing jail 'dev' (PID: 12345)...
[+] Jail 'dev' killed.
```

For immediate termination (SIGKILL):

```bash
jroot kill dev --force
```

The jail's rootfs and configuration are left intact — you can restart it with `jroot enter dev` later.

Note that `jroot kill` targets the interactive shell. To stop an SSH daemon, use `jroot ssh <name> stop`.


### Monitoring active jails

`jroot monitor` presents a live terminal dashboard for active jails, including process state, rootfs size, observed memory use, and active commands.

```bash
jroot monitor
```

### Multi-jail stacks with `compose`

`jroot compose` creates, inspects, and stops a group of jails declared in `jroot-compose.yml`. The command uses Python with PyYAML to parse the file.

```yaml
jails:
  web:
    image: ubuntu:22.04
  db:
    image: ubuntu:22.04
```

```bash
jroot compose up
jroot compose status
jroot compose down
```

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

# ⌨️ Shell completion

Thirty-odd commands with a subcommand grammar is more than anyone should have to remember, so JRoot generates its own completion script.

```bash
jroot completion bash > ~/.local/share/bash-completion/completions/jroot
jroot completion zsh > "${fpath[1]}/_jroot"        # then: compinit
jroot completion fish > ~/.config/fish/completions/jroot.fish
```

`install-jroot.sh` does the bash one (and fish, if fish is installed) for you. For a single shell, `eval "$(jroot completion bash)"`.

It completes rather more than command names:

```bash
jroot en<TAB>                    →  enter  exec
jroot enter <TAB>                →  dev  web  build
jroot revert snapshot dev <TAB>  →  before-upgrade  clean        (this jail's snapshots)
jroot revert checkpoint dev <TAB>  →  pre-patch       debug        (this jail's checkpoints)
jroot port dev rm <TAB>          →  3000  8080                   (this jail's public ports)
jroot mnt dev set <TAB>          →  work  secrets                (this jail's mounts)
jroot ssh dev start --<TAB>      →  --port=  --key=  --random-password  ...
jroot build --<TAB>              →  --file=  --tag=  --build-arg=  --no-cache
jroot doctor --<TAB>             →  --fix  --mute=7d  --mute=forever  ...
```

And, most useful with `jroot file`, **paths inside a jail**:

```bash
jroot file cp dev:/etc/ng<TAB>   →  dev:/etc/nginx/
jroot file cp report.pdf web:/v<TAB>  →  web:/var/
```

Everything it needs is read straight off the host — jail names are files in `configs/`, snapshot labels are files in `snapshots/<jail>/`, ports and mounts come out of the jail config — so pressing TAB never starts a jail, and never forks a python interpreter either.

The scripts are printed rather than installed so you can put them where your shell wants them, and regenerate after an upgrade adds a command. `make check` parses all three with their own shells, because a completion script with a syntax error only ever breaks in somebody else's terminal.

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
[PASS] kernel seccomp filter mode
       openat2 / io_uring escape vectors are blocked
[PASS] kernel Landlock ABI v3
       ~/.jroot is denied and ro mounts are enforced by the kernel
[PASS] gcc: /usr/bin/gcc
[PASS] jail 'dev' config
[PASS] jail 'dev' rootfs    /home/user/.jroot/roots/dev (245M)

Summary: 8 ok, 0 warn, 0 fail
```

The diagnostic system is implemented directly in JRoot rather than relying on a collection of external commands.

### Safe repair mode

`jroot doctor --fix` refreshes JRoot's generated runtime helpers and removes **stale PID records** for stopped jail, SSH, and plugin-service processes. It never deletes a jail, removes a rootfs, or rewrites an invalid configuration file.

```bash
jroot doctor
# ... reports an actual [FAIL], for example a stale PID record
# Repairable faults may be fixed with: jroot doctor --fix

jroot doctor --fix
```

The normal diagnostic recommends `--fix` only when it finds a real fault. Capability notices such as a missing compiler, unavailable Landlock support, or an intentionally muted warning do not trigger that recommendation.

---

# 🔄 Safe package updates

`jroot update <name>` now creates a checkpoint before it touches packages. It updates the distribution, confirms that the rootfs still launches a basic shell, and runs a JRootfile `HEALTHCHECK` when the jail was built with one.

```bash
jroot update dev
# Creates: pre-update-YYYYMMDD-HHMMSS
# Runs apt/apk update and upgrade
# Validates the rootfs after the package manager exits
```

A failed package-manager command does not automatically discard the jail if the rootfs remains healthy; the retained checkpoint gives you a deliberate rollback option. JRoot asks whether to restore the checkpoint only after a failed post-update rootfs health check. In non-interactive use it prints the restore command rather than performing a destructive rollback.

```bash
jroot checkpoints dev
jroot revert checkpoint dev pre-update-20260812-120000
```

---

# 🧱 Reproducible JRootfile builds

A `JRootfile` is a Dockerfile-like recipe that turns a source directory into a normal JRoot jail. It supports familiar instructions including `FROM`, `RUN`, `COPY`, `ADD`, `WORKDIR`, `ARG`, `ENV`, `EXPOSE`, `VOLUME`, `LABEL`, `CMD`, `ENTRYPOINT`, and `HEALTHCHECK`.

```text
my-service/
├── JRootfile
└── app/
    └── server.py
```

```dockerfile
FROM ubuntu:22.04
WORKDIR /srv/my-service
COPY app/ ./
RUN apt-get update && apt-get install -y python3
EXPOSE 8080
HEALTHCHECK test -f /srv/my-service/server.py
CMD ["python3", "/srv/my-service/server.py"]
```

```bash
jroot build --tag my-service ./my-service
jroot exec my-service python3 /srv/my-service/server.py
```

Builds create ordinary jails: use `jroot enter`, `jroot snapshot`, `jroot checkpoint`, `jroot update`, and `jroot rm` exactly as you would for a jail created by `jroot init`. `COPY` and local `ADD` may read only files inside the supplied build context, which prevents a recipe from silently reading unrelated host paths.

Read the full [JRootfile Reference](./docs/JROOTFILE.md) for every supported instruction, context rules, build arguments, metadata, health checks, Dockerfile differences, and full examples.

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

# 🔎 Inspecting jails

### `jroot history` – what was done to a jail, and when

Every command that changes a jail appends a line to `~/.jroot/history/<name>.log`: creation, bootstrap, installs, updates, snapshots, reverts, config changes, mounts, ports, cleans and renames.

```bash
jroot history dev
WHEN             EVENT          DETAIL
2026-08-09 21:04 created        ubuntu:22.04 user=root build_essential=1
2026-08-09 21:09 bootstrap      core packages installed
2026-08-10 09:12 install        git curl
2026-08-10 09:40 snapshot       before-upgrade (86M)
2026-08-10 10:03 mnt            added /mnt/work -> /home/user/projects (ro)
```

```bash
jroot history                  # every jail, oldest first, with a JAIL column
jroot history dev --limit=20   # only the last 20 events
jroot history dev --json       # machine-readable
jroot history dev --clear      # forget this jail's history
jroot logs dev                 # exact alias for: jroot history dev
```

`jroot logs` is provided for the operational wording many users expect; it reads the same event records as `jroot history` and accepts the same `--limit`, `--json`, and `--clear` flags.

A rename carries the log over, and deleting a jail deletes its log with it.

### `jroot compare` – diff two jails

Answers "why does it work in `dev` but not in `web`". It compares the config first, then the package lists.

```bash
jroot compare dev web
Comparing 'dev' vs 'web'   (* = differs)

CONFIG
    FIELD              dev                      web
    image              ubuntu:22.04             ubuntu:22.04
  * user               root                     unroot
    mount_host         0                        0
    ports              none                     8080
  * mounts             work                     none
    distro             ubuntu                   ubuntu
    rootfs size        245M                     180M

PACKAGES (explicitly installed; --all for every package)
    dev: 42 packages, web: 39 packages, 37 shared

  only in dev:
    + git
    + htop

  only in web:
    + nginx
```

By default only explicitly-installed packages are compared — `apt-mark showmanual` on Ubuntu, `/etc/apk/world` on Alpine — which keeps the output about decisions you made rather than dependency noise. Use `--all` to compare every installed package.

### `jroot which` – find a program across jails

```bash
jroot which node
dev              /usr/local/bin/node
build            /usr/bin/node

jroot which dev node          # one jail only
jroot which node --all        # every match, not just the first on PATH
jroot which /etc/nginx/nginx.conf   # absolute paths are checked as-is
```

This reads the rootfs directly from the host, so no jail is started and nothing is executed. Exit status is 1 when nothing matches, so it composes in scripts.

---

# 🛡️ Security

PRoot is powerful because it can provide filesystem and process translation without requiring privileged mounts.

That power also means its attack surface deserves attention. PRoot translates paths by intercepting syscalls with `ptrace`, so anything it does not intercept sees real host paths.

JRoot starts every jail through a launcher that installs two kernel-level protections before PRoot runs:

* a **seccomp filter** that refuses the syscalls PRoot 5.3.0 does not trace — `openat2`, `faccessat2`, `fchmodat2`, the fs-tree family (`open_tree`, `move_mount`, `fsopen`, `fsconfig`, `fsmount`, `fspick`, `mount_setattr`), `pidfd_getfd`, and **io_uring** (a ring bypasses `ptrace` entirely, so once a ring exists every read/write/open on it is invisible to PRoot). The blocked calls return `ENOSYS`, so callers fall back to the classic syscalls PRoot does trace.
* a **Landlock ruleset** — a kernel-enforced, inode-based path allowlist. The jail gets its own rootfs, `/dev`, `/proc`, `/sys`, and whatever you mounted; everything else on the host is refused with `EACCES` no matter which syscall is used. `~/.jroot` is explicitly denied so a jailed process cannot reach another jail's rootfs or rewrite its own config.

```text
JRoot
  │
  ▼
seccomp launcher
  │
  ├── NO_NEW_PRIVS
  ├── syscall filtering (openat2, io_uring, fs-tree family, ...)
  └── Landlock path allowlist (rootfs + mounts only, ~/.jroot denied)
  │
  ▼
 PRoot
  │
  ▼
Ubuntu userspace
```

Both are best effort: a kernel without `CONFIG_SECCOMP_FILTER` or without Landlock (WSL1, older kernels) gets a warning and runs with the remaining layers. `jroot doctor` reports exactly which of the two your kernel supports. `JROOT_LANDLOCK_OFF=1` disables the allowlist for debugging.

### Additional security features

1. **Loopback-only by default** – Jailed servers only listen on the jail's own `127.x.y.z` address unless explicitly whitelisted with `jroot port`
2. **Read-only mount enforcement** – `jroot mnt ... ro` is enforced twice: by Landlock in the kernel, and by the LD_PRELOAD shim returning `EROFS`
3. **Host mount warnings** – JRoot warns when host `/` or `$HOME` are deliberately mounted, and shadows `~/.jroot` inside those mounts
4. **Unroot mode** – Root account can be locked, daily use is a non-root user
5. **Clean environment** – `LD_PRELOAD`, `LD_LIBRARY_PATH`, and proxy env vars are unset on enter
6. **Host processes hidden** – a jailed `ps` sees only the jail's own process tree, and `/proc/<foreign-pid>` returns `ENOENT` even when opened by exact path
7. **No default SSH credentials** – `jroot ssh` never sets a known password; it prompts, or generates one and shows it once. Only the chosen account may log in, and root login is opt-in

**Shim caveat:** the LD_PRELOAD layer needs a libc the jail can load. JRoot verifies this per jail and falls back to compiling the shim inside the jail, but a jail with neither a compatible host build nor `gcc` loses the shim-based features (per-jail address, `jroot port`, `/proc` filtering, and `jroot ssh`). Landlock and seccomp are libc-independent and always apply.

**SSH caveat:** `jroot ssh` runs `sshd` with `JROOT_FAKE_PRIVSEP=1`, which makes the daemon's own `chroot()`, seccomp and audit hardening report success instead of killing the login. That weakens sshd's internal defence in depth — not the jail's boundaries — and it applies only to the `sshd` JRoot starts. See the SSH section for the full reasoning.

### Important

JRoot is **not a virtual machine**, and it does not use namespaces or cgroups.

Landlock and seccomp are real kernel enforcement, but they only cover filesystem paths and syscall numbers. There is no PID, network, or user namespace, no resource limit, and PRoot's `ptrace` translation is not designed to withstand a process that is actively attacking it.

Treat JRoot as strong containment for code you mostly trust, not as a boundary for hostile workloads.

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
  jroot build [options] <context>  Build a jail from a JRootfile
  jroot enter <name>               Enter a jail (interactive shell)
  jroot enter <name> <command>     Run a command inside a jail
  jroot enter <name> --root ...    Run a command as root
  jroot exec <name> [--root] <cmd> Run one command (no shell wrapping)
  jroot shell                      Interactive jroot command shell
  jroot install <name> <packages>  Install apt packages
  jroot config <name>              Configure a jail


FILE & PORT MANAGEMENT

  jroot file cp <src> <dst>        Copy files (host ↔ jail, jail ↔ jail)
  jroot file mv <src> <dst>        Move files (a jail side is dev:/path)
  jroot port <name> list           Show public ports
  jroot port <name> add <port>     Make a port public (0.0.0.0)
  jroot port <name> rm <port>      Keep a port on the jail's own address
  jroot net                        Show every jail's loopback address
  jroot net set <name> auto|off    Reassign or disable the jail address
  jroot mnt <name> list            Show custom mounts
  jroot mnt <name> <label> <dir>   Mount host directory at /mnt/<label> (rw)
  jroot mnt <name> <label> <dir> ro Mount read-only
  jroot mnt <name> set <label> rw|ro Change mount mode
  jroot mnt <name> rm <label>      Unmount /mnt/<label>


INSPECTION

  jroot list [--json]              List all jails
  jroot info [name]                Show jail details
  jroot size [name]                Show disk usage per jail
  jroot history [name]             What was done to a jail, and when
  jroot logs [name]                Alias for a jail's event history
  jroot compare <jailA> <jailB>    Diff two jails (config + packages)
  jroot which [jail] <program>     Find a program across jails
  jroot doctor [--fix]             Diagnose JRoot and repair safe faults


SNAPSHOTS

  jroot snapshot <name> [label]    Save a full snapshot (compressed)
  jroot snapshots <name>           List snapshots
  jroot clone checkpoint|snapshot <source> <label> <new-name>  Clone a saved state
  jroot checkpoint <name> [label]  Save an incremental checkpoint
  jroot checkpoint diff <name> <a> <b>  Compare two checkpoint filesystems
  jroot checkpoints <name>         List checkpoints
  jroot revert snapshot <name> [label]   Restore a snapshot
  jroot revert checkpoint <name> [label] Restore a checkpoint
  jroot rm-snapshot <name> <label>   Delete a snapshot
  jroot rm-checkpoint <name> <label> Delete a checkpoint


MAINTENANCE

  jroot update [name]              Checkpoint, update, and health-check packages
  jroot clean <name>...            Free disk space inside a jail
  jroot rename <name> <newname>    Rename a jail
  jroot kill <name>                Terminate a running jail
  jroot ps                         List running jails
  jroot ssh <name> start [port]    Start SSH daemon (persistent, auto port)
  jroot ssh <name> stop            Stop SSH daemon
  jroot ssh <name> status          Check SSH daemon status (verifies handshake)
  jroot ssh <name> passwd [user]   Set a new SSH password
  jroot ssh <name> log             Show sshd's own log
  jroot rm <name>                  Delete a jail
  jroot completion bash|zsh|fish   Print a shell completion script
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
  "loopback": "127.2.0.1",
  "ports": [3000, 8080, 22001],
  "ssh_user": "jail",
  "ssh_auth": "password",
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
loopback        this jail's address in 127/8, or "off" to share 127.0.0.1
ports           list of public ports (bind to 0.0.0.0)
ssh_user        account SSH logins use (set by 'jroot ssh')
ssh_auth        password | password+key | key-only
mounts          list of [label, hostpath, mode] (mode: rw or ro)
```

No SSH password or hash is ever stored here — only which account logs in and how.

Environment overrides, mostly for debugging:

```text
JROOT_HOME=path        storage root (default ~/.jroot)
JROOT_KERNEL=x.y.z     kernel version reported inside jails (default 6.8.0)
JROOT_SHIM_OFF=1       do not load the LD_PRELOAD shim
JROOT_SHOW_ALL_PROCS=1 let jails see every host process in /proc
JROOT_LANDLOCK_OFF=1   skip the Landlock allowlist
JROOT_PORT_MAP=80=8080 remap a port a jailed listener asks for, so a service with
                       a hardcoded privileged port can run in a rootless jail
JROOT_FAKE_PRIVSEP=1   report success for chroot()/PR_SET_SECCOMP/setgroups()/
                       audit_open() - what lets sshd run (set by 'jroot ssh')
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
                │  security (seccomp + landlock)    │
                │  port shim (bind() LD_PRELOAD)    │
                │  mount shim (write syscalls)      │
                │  /proc shim (process hiding)      │
                │  ssh daemon (persistent, keyed)   │
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
├── builds/
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
* remote access (SSH)
* interactive shell
* completion coverage as commands are added

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


## Documentation

| Guide | What it covers |
|---|---|
| [JRootfile Reference](./docs/JROOTFILE.md) | `jroot build`, supported Dockerfile-like syntax, context safety, metadata, and health checks. |
| [Plugin Development Guide](./docs/PLUGINS.md) | Plugin manifests, hooks, SDK, services, testing, and troubleshooting. |
| [Windows Plugin Development](./docs/WINDOWS_DEV.md) | Cross-platform plugin authoring and validation before deployment to Linux. |

## Plugin development

JRoot supports packaged, event-driven host-side plugins with manifest validation, private state, captured logs, service lifecycle controls, and an importable Python SDK. Packaged plugins declare the API version, entry point, lifecycle hooks, optional host dependencies, and human-readable access expectations before installation.

> Plugins run with the permissions of the host user running `jroot`; they are not sandboxed. Install only reviewed code.

Read the [Plugin Development Guide](./docs/PLUGINS.md) for the stable manifest contract, hook payloads, SDK, services, and validation workflow.

### Windows plugin development

Windows cannot run JRoot’s PRoot runtime, but contributors can create, strictly validate, simulate, and fixture-test plugins before transferring them to a Linux host:

```powershell
python .\jroot-dev.py init my-plugin
python .\jroot-dev.py validate --strict .\my-plugin
python .\jroot-dev.py test .\my-plugin
```

See [Windows Plugin Development](docs/WINDOWS_DEV.md) for the complete cross-platform workflow.
