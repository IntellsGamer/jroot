# JRootfile Reference

A **JRootfile** is a declarative recipe for building a JRoot jail. Its instruction names and ordering follow the Dockerfile model: choose a base image with `FROM`, run setup commands with `RUN`, copy files from a declared build context, set metadata, and produce a named jail.

The result is a normal JRoot jail under `$JROOT_HOME/roots/<tag>`, with its normal JRoot configuration under `$JROOT_HOME/configs/<tag>.json`. It is not an OCI image, does not require Docker, and does not need host root.

```text
JRootfile + build context
          │
          ▼
   jroot build -t my-app .
          │
          ├── jroot init <FROM image>
          ├── executes RUN instructions inside the new jail
          ├── copies files only from the chosen context
          ├── records build metadata under $JROOT_HOME/builds/
          └── leaves a normal named JRoot jail
```

> **Scope:** JRootfile instruction names are intentionally familiar to Dockerfile users, but JRoot is a jail manager rather than an OCI builder. The supported instruction forms and the intentional differences are documented below. Do not rely on unspecified Docker build behaviour such as layer caching, multi-stage `FROM`, a `.dockerignore` parser, arbitrary `USER` accounts, or automatic dependency installation.

---

## Contents

| Section | Purpose |
|---|---|
| [1. Quick start](#1-quick-start) | Build a small jail from a local project directory. |
| [2. Build command](#2-build-command) | Learn command-line options and naming rules. |
| [3. Build context](#3-build-context-and-copy-safety) | Understand what `COPY` and `ADD` can read. |
| [4. Instruction reference](#4-instruction-reference) | See supported syntax, effects, and limitations. |
| [5. Variables and quoting](#5-arg-env-and-quoting) | Use build arguments and persistent environment values safely. |
| [6. Runtime metadata](#6-runtime-metadata-cmd-entrypoint-volume-and-healthcheck) | Understand commands stored for later use. |
| [7. Failure handling](#7-failure-handling-and-cleanup) | Know what is retained after an unsuccessful build. |
| [8. Complete examples](#8-complete-examples) | Build an application jail and an Alpine utility jail. |
| [9. Troubleshooting](#9-troubleshooting) | Diagnose common build failures. |

---

## 1. Quick start

A build context is a directory containing `JRootfile` and every host-side file you intend to copy into the jail.

```text
hello-jail/
├── JRootfile
└── src/
    └── hello.sh
```

Create `hello-jail/JRootfile`:

```dockerfile
FROM ubuntu:22.04

WORKDIR /opt/hello
COPY src/ ./
RUN chmod +x hello.sh

CMD ["/opt/hello/hello.sh"]
```

Create `hello-jail/src/hello.sh`:

```sh
#!/bin/sh
echo "Hello from a JRootfile-built jail"
```

Build it from the directory above `hello-jail`:

```bash
jroot build --tag hello-jail ./hello-jail
```

The build creates the jail `hello-jail`. You can use it with ordinary JRoot commands:

```bash
jroot info hello-jail
jroot enter hello-jail
jroot exec hello-jail /opt/hello/hello.sh
```

The `CMD` instruction is retained as build metadata; JRoot does not automatically replace an interactive `jroot enter` shell with `CMD`. See [runtime metadata](#6-runtime-metadata-cmd-entrypoint-volume-and-healthcheck) for the exact behaviour.

---

## 2. Build command

```text
jroot build [options] <context>
```

`<context>` must be a directory. If no `--file` option is provided, JRoot reads `<context>/JRootfile`.

| Option | Meaning |
|---|---|
| `-f <path>` / `--file <path>` | Read a JRootfile from this path instead of `<context>/JRootfile`. The context remains the directory passed as the final argument. |
| `-t <name>` / `--tag <name>` | Name of the resulting jail. It must be a valid JRoot jail name and must not already exist. |
| `--build-arg NAME=VALUE` | Define or override an `ARG` value. The option can be repeated. |
| `--no-cache` | Accepted for Docker-oriented scripts. JRootfile builds currently do not reuse filesystem layers, so every build is already uncached. |
| `-h` / `--help` | Print command help. |

### Naming the resulting jail

```bash
jroot build -t api-dev ./api
jroot build --tag alpine-tools ./tools
```

If `--tag` is omitted, JRoot derives a lowercase name from the context directory. A build is refused if that jail name already exists; this prevents a recipe from silently overwriting an existing rootfs.

### Choosing a different JRootfile

```bash
jroot build --file ./recipes/JRootfile.dev --tag api-dev ./api
```

In this command, `./api` is still the **only build context**. Therefore, `COPY config/dev.ini /etc/api.ini` reads `./api/config/dev.ini`, not `./recipes/config/dev.ini`.

---

## 3. Build context and copy safety

The build context is a security boundary for `COPY` and local `ADD`. A JRootfile cannot copy `../secrets.txt`, an absolute host path, or a path that resolves outside its context directory.

```text
project/                       ← build context
├── JRootfile
├── app/
│   └── main.py                ← COPY app/ works
└── config/
    └── app.ini                ← COPY config/app.ini works

../private-key.pem             ← COPY ../private-key.pem is rejected
/etc/shadow                    ← COPY /etc/shadow is rejected
```

This prevents a recipe checked into a repository from unexpectedly reading unrelated files owned by the build user.

### `COPY` directory behaviour

`COPY` copies directory **contents** into a directory destination, matching the common Dockerfile expectation.

```dockerfile
WORKDIR /srv/app
COPY src/ ./
```

If `src/` contains `main.py`, the result is `/srv/app/main.py`, not `/srv/app/src/main.py`.

Use a destination ending in `/` when providing multiple sources:

```dockerfile
COPY package.json package-lock.json ./
COPY scripts/ /usr/local/bin/
```

### Local `ADD` and archives

For a local tar archive, `ADD` extracts the archive into the destination directory:

```dockerfile
ADD assets.tar /opt/assets/
```

For an ordinary local file, `ADD` behaves like `COPY`. For an `http://` or `https://` source, JRoot downloads the file with host `curl` and copies it as a file. Remote downloads are **not** auto-extracted, even if they are tar archives.

```dockerfile
ADD https://example.invalid/releases/tool.tar.gz /tmp/tool.tar.gz
RUN tar -xzf /tmp/tool.tar.gz -C /opt/tool
```

Use `COPY` when an archive does not need extraction. Prefer local, reviewed sources when possible: a URL in a build file is executable supply-chain input, not harmless metadata.

---

## 4. Instruction reference

JRootfile instructions are case-insensitive. Empty lines and lines beginning with `#` are ignored. Instructions are evaluated in order, and `FROM` must be the first state-creating instruction.

### 4.1 Supported instruction summary

| Instruction | Supported form | Effect |
|---|---|---|
| `FROM` | `FROM ubuntu:22.04` | Creates the base JRoot jail. Ubuntu and Alpine image names supported by `jroot init` are accepted. |
| `ARG` | `ARG NAME` or `ARG NAME=default` | Defines a build-time substitution variable. |
| `RUN` | `RUN command` | Runs a shell command inside the current jail. |
| `COPY` | `COPY source... destination` | Copies files or directories from the local context. |
| `ADD` | `ADD source destination` | Copies local/remote files; extracts one local tar archive to a directory destination. |
| `WORKDIR` | `WORKDIR /absolute/path` or `WORKDIR relative/path` | Creates and selects the working directory used by later `RUN`, `COPY`, and `ADD` destinations. |
| `USER` | `USER root` or `USER jail` | Selects fake root or JRoot's built-in unprivileged `jail` account for later `RUN` instructions. |
| `ENV` | `ENV KEY=value [KEY=value ...]` | Persists environment exports in `/etc/profile.d/jroot-build-env.sh` and makes values available for later substitutions. |
| `EXPOSE` | `EXPOSE 8080 [8443/tcp ...]` | Adds ports to the JRoot public-port configuration and records build metadata. |
| `VOLUME` | `VOLUME /path [more-paths...]` | Creates the path and records it as metadata. It does not create a Docker-managed host volume. |
| `LABEL` | `LABEL key=value [key=value ...]` | Stores key/value metadata in the build record. |
| `CMD` | `CMD command` or `CMD ["executable", "arg"]` | Stores the raw default-command declaration as build metadata. |
| `ENTRYPOINT` | `ENTRYPOINT command` or JSON form | Stores the raw entrypoint declaration as build metadata. |
| `HEALTHCHECK` | `HEALTHCHECK command` or `HEALTHCHECK NONE` | Stores an update-time health command. It runs after a later `jroot update <name>`. |
| `SHELL` | `SHELL ["/bin/bash", "-c"]` | Changes the two-item shell/flag pair used for subsequent `RUN` instructions. |
| `STOPSIGNAL` | `STOPSIGNAL SIGTERM` | Stores metadata for an external launcher or operator. |
| `MAINTAINER` | `MAINTAINER Name or Team` | Stores the legacy maintainer field as a label. |

### 4.2 Unsupported Dockerfile instructions

JRoot is explicit when it cannot preserve an instruction's intended meaning.

| Instruction or feature | Status | Reason |
|---|---|---|
| Multiple `FROM` stages | Rejected | JRoot builds one named jail per JRootfile and does not yet have a stage image store. |
| `ONBUILD` | Rejected | There are no child-image builds that could inherit triggers. |
| `RUN --mount=...` | Not parsed | JRoot mount policy belongs to `jroot mnt` and jail configuration. |
| `COPY --chown`, `COPY --chmod`, `--link` | Not parsed | Use `RUN chown` or `RUN chmod` after copying. |
| `.dockerignore` | Not parsed | The context is copied only when a `COPY`/`ADD` instruction asks for a path. |
| Arbitrary `USER` names, numeric UID/GID | Rejected | JRoot manages `root` and its optional `jail` user consistently across distributions. |
| Layer cache | Not implemented | A JRoot build creates a normal rootfs directly; `--no-cache` is a compatibility no-op. |
| Automatic `CMD`/`ENTRYPOINT` launch | Not implemented | JRoot's interactive default remains `jroot enter <name>`. Metadata is retained for tooling. |

---

## 5. `ARG`, `ENV`, and quoting

### 5.1 Build arguments

`ARG` defines a value available during parsing of later instructions. JRoot expands both `$NAME` and `${NAME}` forms.

```dockerfile
ARG PYTHON_VERSION=3.12
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python${PYTHON_VERSION}
```

Override a default with the command line:

```bash
jroot build --build-arg PYTHON_VERSION=3.11 -t py311 ./python-app
```

Define an `ARG` before using it. A command-line `--build-arg` supplies the value when the matching `ARG` is encountered; it does not make undeclared variables part of the recipe contract.

### 5.2 Environment values

`ENV` uses `KEY=value` tokens. It creates `/etc/profile.d/jroot-build-env.sh` in the jail and also updates the build variable map for later instructions.

```dockerfile
ENV APP_HOME=/srv/app LOG_LEVEL=info
WORKDIR $APP_HOME
```

The current parser intentionally keeps `ENV` simple. Values containing whitespace, unescaped shell syntax, or multiline content should be written through an explicit `RUN` instruction instead:

```dockerfile
RUN printf '%s\n' 'application title with spaces' > /etc/app-title
```

### 5.3 Shell versus JSON forms

`RUN` is always shell form. The active default is `/bin/sh -c` and can be changed with the two-string `SHELL` JSON array:

```dockerfile
SHELL ["/bin/bash", "-c"]
RUN set -o pipefail && curl -fsSL https://example.invalid/file | tee /tmp/file
```

`CMD` and `ENTRYPOINT` accept shell or JSON-looking text, but JRoot stores the text rather than parsing it into an OCI runtime specification.

---

## 6. Runtime metadata: `CMD`, `ENTRYPOINT`, `VOLUME`, and `HEALTHCHECK`

JRoot stores metadata in:

```text
$JROOT_HOME/builds/<jail-name>.json
```

This file records the source image, JRootfile path, labels, exposed ports, volume paths, default command, entrypoint, stop signal, and health check. It is separate from the jail's core JRoot configuration, which keeps the existing config format stable.

### 6.1 `CMD` and `ENTRYPOINT`

```dockerfile
ENTRYPOINT ["/usr/local/bin/my-service"]
CMD ["--config", "/etc/my-service.toml"]
```

JRoot preserves both declarations in metadata. To execute them today, use `jroot exec` explicitly or write a small host launcher that reads the metadata. This is deliberate: automatically changing `jroot enter` into a service launch would break its established interactive-shell contract.

### 6.2 `EXPOSE`

```dockerfile
EXPOSE 8080 8443/tcp
```

Each port is passed through JRoot's public-port configuration. This is operational behaviour, not merely metadata: a corresponding listener inside the jail may bind publicly according to JRoot's existing port policy.

### 6.3 `VOLUME`

```dockerfile
VOLUME /var/lib/my-service /var/log/my-service
```

JRoot creates these directories in the rootfs and records them. It does not allocate a separate host-managed volume directory or make the paths survive a snapshot/revert in a special way. Use `jroot mnt` when a path must be backed by a particular host directory.

### 6.4 `HEALTHCHECK` and safe updates

```dockerfile
HEALTHCHECK test -f /etc/my-service.conf
```

After `jroot update my-service` finishes its package-manager work, JRoot first performs a basic rootfs launch check. If the JRootfile has a `HEALTHCHECK`, JRoot runs that command inside the jail as fake root as part of the same verification.

`HEALTHCHECK NONE` removes the build-level command. The basic rootfs launch check still runs for every package update.

---

## 7. Failure handling and cleanup

A JRootfile build does not hide a failed build by deleting its jail. If a `RUN`, `COPY`, `ADD`, or another instruction fails after `FROM`, JRoot leaves the partially built jail in place for inspection.

```bash
jroot info my-app
jroot enter my-app --root
jroot history my-app
```

After diagnosing the failure, either fix the JRootfile and use a new tag, or remove the partial jail explicitly:

```bash
jroot rm my-app
jroot build --tag my-app ./my-app
```

This behaviour is especially useful for package-manager failures, missing files, and distribution-specific shell problems. It avoids the common “build failed but all evidence disappeared” situation.

### Update checkpoints

Every `jroot update <name>` now creates an incremental checkpoint named `pre-update-<timestamp>` before changing packages. The checkpoint remains after a successful update so an operator can review or revert later.

If the package manager exits non-zero but the jail still passes basic health checks, JRoot reports the package-manager failure and keeps the checkpoint, but does not ask to revert automatically. A transient mirror failure is not the same thing as a broken rootfs.

If the post-update rootfs health check fails, JRoot offers an interactive rollback prompt. In `NONINTERACTIVE=1` or a non-terminal session, it never performs a destructive rollback automatically; it prints the exact `jroot revert checkpoint` command instead.

---

## 8. Complete examples

### 8.1 Ubuntu application jail

```text
web-demo/
├── JRootfile
├── requirements.txt
└── app/
    └── server.py
```

`web-demo/JRootfile`:

```dockerfile
ARG PYTHON_PACKAGE=python3
FROM ubuntu:22.04

LABEL org.example.component=web-demo org.example.owner=platform
ENV APP_HOME=/srv/web-demo APP_PORT=8080

RUN apt-get update && apt-get install -y $PYTHON_PACKAGE python3-pip ca-certificates
WORKDIR $APP_HOME
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt
COPY app/ ./
RUN useradd -m -s /bin/sh appuser || true

EXPOSE 8080
VOLUME /var/lib/web-demo
HEALTHCHECK test -f /srv/web-demo/server.py
ENTRYPOINT ["python3", "/srv/web-demo/server.py"]
CMD ["--port", "8080"]
```

Build and verify it:

```bash
jroot build -t web-demo ./web-demo
jroot exec web-demo python3 /srv/web-demo/server.py --help
jroot info web-demo
jroot update web-demo
```

The example creates `appuser` inside the rootfs, but JRootfile `USER` only switches between JRoot's managed `root` and `jail` modes. If you need to run this service as `appuser`, invoke it explicitly through a command that switches user according to the distribution's available tools.

### 8.2 Alpine command-line utility jail

```dockerfile
FROM alpine:3.22

LABEL org.example.purpose=network-tools
RUN apk update && apk add --no-cache curl jq bind-tools
WORKDIR /workspace
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*

CMD ["/bin/sh"]
```

```bash
jroot build --tag net-tools ./net-tools
jroot enter net-tools
```

### 8.3 Build argument for a small variation

```dockerfile
ARG TOOL=jq
FROM alpine:3.22
RUN apk add --no-cache $TOOL
```

```bash
jroot build --build-arg TOOL=curl --tag curl-tools ./tools
jroot build --build-arg TOOL=jq --tag jq-tools ./tools
```

Each command produces a separately named jail. JRoot does not reuse prior build layers, so each result is independent and safe to inspect, snapshot, or remove using normal commands.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `JRootfile not found` | No default file exists at `<context>/JRootfile`, or `--file` points to the wrong location. | Create the file or pass `--file path/to/JRootfile`. |
| `Jail '<tag>' already exists` | A build would overwrite a real jail. | Choose another `--tag`, or inspect and deliberately remove the existing jail first. |
| `JRootfile RUN requires FROM first` | A state-changing instruction appeared before `FROM`. | Put exactly one supported `FROM ubuntu:<version>` or `FROM alpine:<version>` first. |
| `Multi-stage FROM is not supported` | The recipe uses Docker build stages. | Split stages into separate JRootfiles/jails and move files with `jroot file cp`. |
| `COPY source must exist inside the build context` | Source path is missing, absolute, or escapes via `..`. | Add the source to the context directory and use a relative path. |
| `COPY directory source requires a directory destination` | A directory source was targeted at a file path. | Use a destination ending in `/`, such as `COPY src/ /srv/app/`. |
| `ADD URL requires curl on the host` | The host lacks `curl`. | Install `curl`, or download the file yourself and use `COPY`. |
| `JRootfile USER supports root and jail` | The recipe names an arbitrary Docker user. | Use `USER root`/`USER jail`, or create the account with `RUN` and invoke it explicitly. |
| Build failed at `RUN` | The inner command returned non-zero. | Enter the retained partial jail as root, correct the command, then rebuild using a clean tag or after `jroot rm`. |
| Update reports a package-manager failure but no rollback question | The rootfs health check passed. | Inspect package logs/mirrors; restore the retained pre-update checkpoint manually only if you decide it is necessary. |
| Update offers rollback | The rootfs or the configured `HEALTHCHECK` failed after package changes. | Accept rollback if you want the prior state, or decline and investigate the failed jail manually. |

For short command syntax, run `jroot help build`, `jroot help update`, or `jroot help doctor`.
