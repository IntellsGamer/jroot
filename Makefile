# =============================================================================
# jroot Makefile
#
# jroot is a single bash script plus a C shim that lives inside it as a
# heredoc, so there is nothing to compile before installing. What this Makefile
# is actually for is everything around that: installing without root, checking
# the script and the embedded C both parse, and keeping the shim's version
# markers in step.
#
#   make            same as 'make help'
#   make install    copy jroot to ~/.local/bin and add PATH + aliases
#   make uninstall  remove the script, keep every jail
#   make purge      remove the script AND all jails (asks first)
#   make check      lint the shell, compile the embedded C shim, check the
#                   generated completion scripts, run self-tests
#   make test       check + exercise the CLI and the tests/ scripts against a
#                   throwaway JROOT_HOME
#
# Nothing here needs sudo. PREFIX defaults to ~/.local so an ordinary account
# can install jroot the same way jroot itself avoids needing privileges. Set
# PREFIX=/usr/local (with sudo) for a system-wide install if you want one.
# =============================================================================

SHELL := /bin/bash

PREFIX     ?= $(HOME)/.local
BINDIR     ?= $(PREFIX)/bin
JROOT_HOME ?= $(HOME)/.jroot

SCRIPT     := jroot
INSTALLER  := install-jroot.sh
TARGET     := $(BINDIR)/$(SCRIPT)

# Where scratch build output goes. Kept out of the repo root so 'make check'
# never leaves anything behind that git would notice.
BUILDDIR   := .build

# The shim source is embedded in the script between `cat > "$src" <<'CEOF'` and
# a lone CEOF. Extracting it is what lets 'make check' compile the C without
# running jroot at all.
SHIM_C     := $(BUILDDIR)/libjroot.c
SHIM_SO    := $(BUILDDIR)/libjroot.so

# Match the flags jroot uses at runtime. The old symbol set is deliberate: the
# shim is built on the host but loaded inside jails as old as Ubuntu 16.04, so
# one modern symbol would break every command in those jails.
SHIM_CFLAGS := -shared -fPIC -O2 -std=gnu11 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0

CYAN := \033[1;36m
GRN  := \033[1;32m
YEL  := \033[1;33m
RED  := \033[1;31m
DIM  := \033[2m
NC   := \033[0m

.DEFAULT_GOAL := help
.PHONY: help install uninstall purge check lint shim-c shim test clean version \
        shim-version doctor list dev-install

# -----------------------------------------------------------------------------
help:
	@printf '$(CYAN)jroot$(NC) $(DIM)- rootless Linux jails$(NC)\n\n'
	@printf '$(CYAN)INSTALL$(NC)\n'
	@printf '    $(GRN)make install$(NC)      Install to $(BINDIR) (no root needed)\n'
	@printf '    $(GRN)make uninstall$(NC)    Remove the script, keep all jails\n'
	@printf '    $(GRN)make purge$(NC)        Remove the script and every jail (confirms first)\n'
	@printf '    $(GRN)make dev-install$(NC)  Symlink instead of copy, so edits are live\n\n'
	@printf '$(CYAN)VERIFY$(NC)\n'
	@printf '    $(GRN)make check$(NC)        Lint the shell, compile the embedded C, self-test\n'
	@printf '    $(GRN)make lint$(NC)         bash -n (and shellcheck, if installed)\n'
	@printf '    $(GRN)make shim$(NC)         Extract and compile the LD_PRELOAD shim\n'
	@printf '    $(GRN)make completion-check$(NC)  Parse the generated bash/zsh/fish scripts\n'
	@printf '    $(GRN)make test$(NC)         check + drive the CLI in a throwaway JROOT_HOME\n\n'
	@printf '$(CYAN)INFO$(NC)\n'
	@printf '    $(GRN)make version$(NC)      Show the script and shim versions\n'
	@printf '    $(GRN)make doctor$(NC)       Run the installed jroot doctor\n'
	@printf '    $(GRN)make list$(NC)         List jails\n'
	@printf '    $(GRN)make clean$(NC)        Remove build scratch ($(BUILDDIR))\n\n'
	@printf '$(CYAN)VARIABLES$(NC)\n'
	@printf '    PREFIX=$(PREFIX)\n'
	@printf '    BINDIR=$(BINDIR)\n'
	@printf '    JROOT_HOME=$(JROOT_HOME)\n\n'
	@printf '  System-wide instead: $(GRN)sudo make install PREFIX=/usr/local$(NC)\n'

# -----------------------------------------------------------------------------
# Install / uninstall
#
# Delegates to install-jroot.sh for the default prefix, because that script also
# handles the upgrade-vs-clean-reinstall prompt and the ~/.bashrc block. For a
# custom PREFIX it does a plain copy instead, since the shell-rc editing only
# makes sense for a user-local install.
# -----------------------------------------------------------------------------
install: lint
ifeq ($(PREFIX),$(HOME)/.local)
	@bash $(INSTALLER)
else
	@install -d "$(BINDIR)" "$(JROOT_HOME)/sdk"
	@install -m 755 "$(SCRIPT)" "$(TARGET)"
	@install -m 644 "jroot_sdk.py" "$(JROOT_HOME)/sdk/jroot_sdk.py"
	@printf '$(GRN)[+]$(NC) Installed $(TARGET) and plugin SDK\n'
	@command -v jroot >/dev/null 2>&1 || \
		printf '$(YEL)[!]$(NC) %s is not on your PATH yet.\n' "$(BINDIR)"
endif

# A symlink rather than a copy: handy while working on jroot, because the
# installed command always reflects the checkout.
dev-install: lint
	@install -d "$(BINDIR)" "$(JROOT_HOME)/sdk"
	@ln -sf "$(CURDIR)/$(SCRIPT)" "$(TARGET)"
	@install -m 644 "jroot_sdk.py" "$(JROOT_HOME)/sdk/jroot_sdk.py"
	@printf '$(GRN)[+]$(NC) Linked $(TARGET) -> $(CURDIR)/$(SCRIPT) and installed plugin SDK\n'

uninstall:
	@if [ -e "$(TARGET)" ] || [ -L "$(TARGET)" ]; then \
		rm -f "$(TARGET)"; \
		printf '$(GRN)[+]$(NC) Removed $(TARGET)\n'; \
	else \
		printf '$(YEL)[!]$(NC) Not installed at $(TARGET)\n'; \
	fi
	@printf '$(DIM)    Jails in %s were left alone. Use "make purge" to delete them.$(NC)\n' "$(JROOT_HOME)"
	@printf '$(DIM)    The "# >>> jroot >>>" block in ~/.bashrc and ~/.profile is also left in place.$(NC)\n'

# Destructive, so it asks. Every jail rootfs, config, snapshot and history log
# lives under JROOT_HOME and none of it is recoverable afterwards.
purge:
	@printf '$(RED)This deletes %s: every jail rootfs, config, snapshot and history log.$(NC)\n' "$(JROOT_HOME)"
	@if [ -d "$(JROOT_HOME)/roots" ]; then \
		printf '$(DIM)Jails that would be destroyed:$(NC)\n'; \
		ls -1 "$(JROOT_HOME)/roots" 2>/dev/null | sed 's/^/    /' || true; \
	fi
	@read -r -p 'Type "purge" to confirm: ' ans; \
	if [ "$$ans" = "purge" ]; then \
		for p in "$(JROOT_HOME)"/pids/*.sshd; do \
			[ -f "$$p" ] || continue; \
			pid=$$(cat "$$p" 2>/dev/null); \
			[ -n "$$pid" ] && kill -TERM "$$pid" 2>/dev/null || true; \
		done; \
		rm -rf "$(JROOT_HOME)"; \
		rm -f "$(TARGET)"; \
		printf '$(GRN)[+]$(NC) Purged.\n'; \
	else \
		printf 'Cancelled.\n'; \
	fi

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
lint:
	@printf '$(CYAN)==>$(NC) bash -n %s\n' "$(SCRIPT)"
	@bash -n "$(SCRIPT)" && printf '    syntax ok\n'
	@bash -n "$(INSTALLER)" && printf '    %s syntax ok\n' "$(INSTALLER)"
	@for t in tests/*.sh; do \
		bash -n "$$t" || exit 1; \
		printf '    %s syntax ok\n' "$$t"; \
	done
	@if command -v shellcheck >/dev/null 2>&1; then \
		printf '$(CYAN)==>$(NC) shellcheck\n'; \
		shellcheck -S warning -e SC2086,SC2046,SC1090,SC1091 "$(SCRIPT)" "$(INSTALLER)" \
			&& printf '    clean\n' || printf '$(YEL)    shellcheck had findings (not fatal)$(NC)\n'; \
	else \
		printf '$(DIM)    shellcheck not installed, skipping$(NC)\n'; \
	fi

# Pull the C shim out of the heredoc so it can be compiled on its own. If the
# extraction ever comes back empty the markers in jroot have moved, which is a
# real error rather than something to paper over.
$(SHIM_C): $(SCRIPT)
	@mkdir -p "$(BUILDDIR)"
	@awk "/cat > \"\\\$$src\" <<'CEOF'/{f=1;next} /^CEOF\$$/{f=0} f" "$(SCRIPT)" > "$@"
	@if [ ! -s "$@" ]; then \
		printf '$(RED)[!]$(NC) Could not extract the shim from %s - have the CEOF markers moved?\n' "$(SCRIPT)"; \
		rm -f "$@"; exit 1; \
	fi
	@printf '$(GRN)[+]$(NC) Extracted shim: %s lines\n' "$$(wc -l < "$@")"

shim-c: $(SHIM_C)

# Same link fallbacks jroot uses: keep DT_NEEDED libdl (glibc 2.34+), then
# plain -ldl (older glibc), then nothing (musl has dlsym in libc).
$(SHIM_SO): $(SHIM_C)
	@command -v gcc >/dev/null 2>&1 || { \
		printf '$(YEL)[!]$(NC) gcc not installed - cannot compile the shim.\n'; \
		printf '$(DIM)    jroot still works without it, minus per-jail addresses,\n'; \
		printf '    "jroot port", /proc hiding and "jroot ssh".$(NC)\n'; exit 1; }
	@printf '$(CYAN)==>$(NC) compiling the shim\n'
	@gcc $(SHIM_CFLAGS) -o "$@" "$(SHIM_C)" -Wl,--no-as-needed -l:libdl.so.2 2>/dev/null \
		|| gcc $(SHIM_CFLAGS) -o "$@" "$(SHIM_C)" -ldl 2>/dev/null \
		|| gcc $(SHIM_CFLAGS) -o "$@" "$(SHIM_C)" \
		|| { printf '$(RED)[!]$(NC) shim failed to compile\n'; exit 1; }
	@printf '$(GRN)[+]$(NC) Built %s\n' "$@"
	@$(MAKE) --no-print-directory shim-glibc-floor

shim: $(SHIM_SO)

# The shim is built on the host and loaded inside jails, so the highest GLIBC_x.y
# it requires is the oldest jail it can work in. 2.17 covers Ubuntu 16.04;
# anything higher means the host toolchain leaked a newer symbol in.
.PHONY: shim-glibc-floor
shim-glibc-floor:
	@if command -v objdump >/dev/null 2>&1 && [ -f "$(SHIM_SO)" ]; then \
		v=$$(objdump -p "$(SHIM_SO)" 2>/dev/null \
			| sed -n 's/.*GLIBC_\([0-9][0-9.]*\).*/\1/p' \
			| sort -t. -k1,1n -k2,2n -k3,3n | tail -n1); \
		if [ -n "$$v" ]; then \
			case "$$v" in \
				2.[0-9]|2.1[0-7]) printf '    needs glibc >= %s (covers Ubuntu 16.04+)\n' "$$v" ;; \
				*) printf '$(YEL)    needs glibc >= %s - jails older than that will build their own copy$(NC)\n' "$$v" ;; \
			esac; \
		fi; \
	fi

# The version markers exist so an upgraded jroot always replaces an older .so,
# including one compiled inside a jail. Three copies have to agree, and a
# mismatch silently keeps a stale shim alive, so it is worth asserting.
shim-version: $(SHIM_C)
	@printf '$(CYAN)==>$(NC) shim version markers\n'
	@sv=$$(grep -m1 'SHIM_VERSION=' "$(SCRIPT)" | sed 's/.*"\(.*\)".*/\1/'); \
	cc=$$(grep -m1 'jroot_shim_version\[\] =' "$(SHIM_C)" | sed 's/.*"\(.*\)".*/\1/'); \
	cm=$$(grep -m1 -o 'jroot-shim-v[0-9]*' "$(SHIM_C)"); \
	printf '    SHIM_VERSION        %s\n' "$$sv"; \
	printf '    jroot_shim_version  %s\n' "$$cc"; \
	printf '    source comment      %s\n' "$$cm"; \
	if [ "$$sv" = "$$cc" ] && [ "$$sv" = "$$cm" ]; then \
		printf '$(GRN)    all three agree$(NC)\n'; \
	else \
		printf '$(RED)[!]$(NC) markers disagree - bump all three when the shim changes\n'; \
		exit 1; \
	fi

# Exercise the shim's observable behaviour rather than just its exit status: a
# shim that loads but does nothing is the failure mode worth catching.
#
# Everything runs from inside $(BUILDDIR) with LD_PRELOAD=./libjroot.so on
# purpose. LD_PRELOAD is a SPACE-separated list, so it cannot carry a path
# containing spaces at all - and this project's own directory has them. A
# relative path is honoured as long as it contains a slash, so cd'ing sidesteps
# the problem instead of hoping the checkout lives somewhere tidy.
.PHONY: shim-selftest
shim-selftest: $(SHIM_SO)
	@printf '$(CYAN)==>$(NC) shim self-test\n'
	@command -v python3 >/dev/null 2>&1 || { printf '$(DIM)    python3 missing, skipping$(NC)\n'; exit 0; }
	@cd "$(BUILDDIR)" && set -e; \
	P=./libjroot.so; \
	out=$$(JROOT_PORT_MAP="22=22187" JROOT_LOOPBACK="127.2.0.9" JROOT_PORTS="" \
		LD_PRELOAD=$$P python3 -c "import socket;s=socket.socket();s.bind(('0.0.0.0',22));print('%s:%d'%s.getsockname());s.close()" 2>&1); \
	if [ "$$out" = "127.2.0.9:22187" ]; then \
		printf '    bind() port remap + loopback pinning: ok (%s)\n' "$$out"; \
	else \
		printf '$(RED)[!]$(NC) expected 127.2.0.9:22187, got: %s\n' "$$out"; exit 1; \
	fi; \
	out=$$(LD_PRELOAD=$$P JROOT_PROC_ROOT=$$$$ python3 -c "import os;print(os.path.exists('/proc/1'))" 2>&1); \
	if [ "$$out" = "False" ]; then \
		printf '    /proc foreign-pid hiding: ok\n'; \
	else \
		printf '$(RED)[!]$(NC) /proc/1 still visible inside the filter: %s\n' "$$out"; exit 1; \
	fi; \
	out=$$(LD_PRELOAD=$$P JROOT_PROC_ROOT=$$$$ python3 -c "import os;print(os.path.exists('/proc/meminfo'))" 2>&1); \
	if [ "$$out" = "True" ]; then \
		printf '    non-pid /proc entries untouched: ok\n'; \
	else \
		printf '$(RED)[!]$(NC) /proc/meminfo was hidden too: %s\n' "$$out"; exit 1; \
	fi; \
	out=$$(LD_PRELOAD=$$P JROOT_FAKE_PRIVSEP=1 python3 -c "import ctypes;print(ctypes.CDLL(None).chroot(b'/tmp'))" 2>&1); \
	if [ "$$out" = "0" ]; then \
		printf '    privsep fake (chroot) under the flag: ok\n'; \
	else \
		printf '$(RED)[!]$(NC) chroot() was not faked under JROOT_FAKE_PRIVSEP: %s\n' "$$out"; exit 1; \
	fi; \
	out=$$(LD_PRELOAD=$$P python3 -c "import ctypes;print(ctypes.CDLL(None).chroot(b'/tmp'))" 2>&1); \
	if [ "$$out" = "-1" ]; then \
		printf '    chroot() NOT faked without the flag: ok\n'; \
	else \
		printf '$(RED)[!]$(NC) chroot() was faked without JROOT_FAKE_PRIVSEP: %s\n' "$$out"; exit 1; \
	fi

check: lint shim shim-version shim-selftest completion-check
	@printf '$(GRN)==> check passed$(NC)\n'

# The completion scripts are printed by jroot itself, so a syntax error in one
# would only ever show up in somebody's shell. Parse each with its own shell
# where that shell exists, and assert the entry point is still there - a script
# that parses but registers nothing completes nothing.
.PHONY: completion-check
completion-check:
	@printf '$(CYAN)==>$(NC) generated completion scripts\n'
	@mkdir -p "$(BUILDDIR)"
	@bash "$(SCRIPT)" completion bash > "$(BUILDDIR)/jroot-completion.bash"
	@bash -n "$(BUILDDIR)/jroot-completion.bash"
	@grep -q 'complete -F _jroot jroot' "$(BUILDDIR)/jroot-completion.bash" \
		|| { printf '$(RED)[!]$(NC) bash script never calls complete\n'; exit 1; }
	@printf '    bash   parses, registers _jroot\n'
	@bash "$(SCRIPT)" completion zsh > "$(BUILDDIR)/_jroot"
	@head -n1 "$(BUILDDIR)/_jroot" | grep -q '^#compdef jroot' \
		|| { printf '$(RED)[!]$(NC) zsh script is missing its #compdef line\n'; exit 1; }
	@if command -v zsh >/dev/null 2>&1; then \
		zsh -n "$(BUILDDIR)/_jroot" || exit 1; \
		printf '    zsh    parses, has #compdef\n'; \
	else \
		printf '    zsh    has #compdef $(DIM)(zsh not installed, not parsed)$(NC)\n'; \
	fi
	@bash "$(SCRIPT)" completion fish > "$(BUILDDIR)/jroot.fish"
	@grep -q '^complete -c jroot' "$(BUILDDIR)/jroot.fish" \
		|| { printf '$(RED)[!]$(NC) fish script never calls complete\n'; exit 1; }
	@if command -v fish >/dev/null 2>&1; then \
		fish --no-execute "$(BUILDDIR)/jroot.fish" || exit 1; \
		printf '    fish   parses, registers completions\n'; \
	else \
		printf '    fish   registers completions $(DIM)(fish not installed, not parsed)$(NC)\n'; \
	fi

# Drive the CLI itself, against a JROOT_HOME under $(BUILDDIR) so real jails are
# never touched. Deliberately avoids 'jroot init': that downloads a rootfs and
# runs apt, which is not something a Makefile target should do behind your back.
#
# Split into two lists because "exits non-zero" is the CORRECT answer for some of
# these on an empty install - 'jroot net' with no jails is supposed to complain,
# and a test that accepted either outcome would not be testing anything.
test: check
	@printf '$(CYAN)==>$(NC) CLI smoke test (throwaway JROOT_HOME)\n'
	@rm -rf "$(BUILDDIR)/home"
	@set -e; export JROOT_HOME="$(CURDIR)/$(BUILDDIR)/home" NONINTERACTIVE=1; \
	printf '$(DIM)    should succeed with no jails:$(NC)\n'; \
	for args in "help" "help ssh" "help init" "help net" "help mnt" "list" "list --json" \
	            "init --list" "history" "doctor"; do \
		if bash "$(SCRIPT)" $$args >/dev/null 2>&1; then \
			printf '      jroot %-16s ok\n' "$$args"; \
		else \
			printf '$(RED)[!]$(NC) jroot %s should have succeeded\n' "$$args"; exit 1; \
		fi; \
	done; \
	printf '$(DIM)    should fail cleanly with no jails:$(NC)\n'; \
	for args in "net" "size" "info" "ssh nosuchjail status" "enter nosuchjail" \
	            "snapshots nosuchjail" "frobnicate"; do \
		if bash "$(SCRIPT)" $$args >/dev/null 2>&1; then \
			printf '$(RED)[!]$(NC) jroot %s should have failed\n' "$$args"; exit 1; \
		else \
			printf '      jroot %-16s rejected\n' "$$args"; \
		fi; \
	done
	@printf '$(DIM)    generated ssh session wrapper:$(NC)\n'
	@set -e; export JROOT_HOME="$(CURDIR)/$(BUILDDIR)/home"; \
	mkdir -p "$$JROOT_HOME/configs" "$$JROOT_HOME/roots/mktest/usr/local/bin"; \
	printf '%s\n' '{"name":"mktest","image":"ubuntu:22.04","user":"root","mount_host":0,"mount_home":0,"build_essential":1,"loopback":"127.2.0.4","ports":[22001],"mounts":[["ro1","/tmp/ro1","ro"]]}' \
		> "$$JROOT_HOME/configs/mktest.json"; \
	sed '$$ d' "$(SCRIPT)" > "$(BUILDDIR)/jroot-lib.sh"; \
	( source "$(BUILDDIR)/jroot-lib.sh"; write_ssh_session_wrapper mktest ); \
	W="$$JROOT_HOME/roots/mktest/usr/local/bin/jroot-session"; \
	[ -x "$$W" ] || { printf '$(RED)[!]$(NC) wrapper not generated\n'; exit 1; }; \
	sh -n "$$W" || { printf '$(RED)[!]$(NC) wrapper is not valid POSIX sh\n'; exit 1; }; \
	printf '      generated, mode 755, valid sh   ok\n'; \
	grep -q "JROOT_RO_MOUNTS='/mnt/ro1'" "$$W" \
		&& printf '      ro mounts baked in              ok\n' \
		|| { printf '$(RED)[!]$(NC) ro mount list missing from the wrapper\n'; exit 1; }; \
	grep -q "JROOT_LOOPBACK='127.2.0.4'" "$$W" \
		&& printf '      loopback address baked in       ok\n' \
		|| { printf '$(RED)[!]$(NC) loopback missing from the wrapper\n'; exit 1; }
	@rm -rf "$(BUILDDIR)/home" "$(BUILDDIR)/jroot-lib.sh"
	@printf '$(CYAN)==>$(NC) tests/file.sh\n'
	@bash tests/file.sh
	@printf '$(CYAN)==>$(NC) tests/sync.sh\n'
	@bash tests/sync.sh
	@printf '$(CYAN)==>$(NC) tests/completion.sh\n'
	@bash tests/completion.sh
	@printf '$(CYAN)==>$(NC) tests/completion-audit.sh\n'
	@bash tests/completion-audit.sh
	@printf '$(CYAN)==>$(NC) tests/completion-shells.sh\n'
	@bash tests/completion-shells.sh
	@printf '$(CYAN)==>$(NC) tests/reserved-names.sh\n'
	@bash tests/reserved-names.sh
	@printf '$(CYAN)==>$(NC) tests/plugins.sh\n'
	@bash tests/plugins.sh
	@printf '$(CYAN)==>$(NC) tests/init.sh\n'
	@bash tests/init.sh
	@printf '$(CYAN)==>$(NC) tests/unroot-security.sh\n'
	@bash tests/unroot-security.sh
	@printf '$(CYAN)==>$(NC) tests/termux-filesystem.sh\n'
	@bash tests/termux-filesystem.sh
	@printf '$(CYAN)==>$(NC) tests/build.sh\n'
	@bash tests/build.sh
	@printf '$(CYAN)==>$(NC) tests/maintenance.sh\n'
	@bash tests/maintenance.sh
	@printf '$(CYAN)==>$(NC) tests/checkpoint.sh\n'
	@bash tests/checkpoint.sh
	@printf '$(CYAN)==>$(NC) tests/bundle.sh\n'
	@bash tests/bundle.sh
	@printf '$(CYAN)==>$(NC) tests/progress.sh\n'
	@bash tests/progress.sh
	@printf '$(CYAN)==>$(NC) tests/clone.sh\n'
	@bash tests/clone.sh
	@printf '$(CYAN)==>$(NC) tests/logs.sh\n'
	@bash tests/logs.sh
	@printf '$(GRN)==> test passed$(NC)\n'

# -----------------------------------------------------------------------------
# Info
# -----------------------------------------------------------------------------
version:
	@printf '$(CYAN)jroot$(NC)\n'
	@printf '    script:        %s (%s lines)\n' "$(SCRIPT)" "$$(wc -l < $(SCRIPT))"
	@printf '    shim version:  %s\n' "$$(grep -m1 'SHIM_VERSION=' $(SCRIPT) | sed 's/.*"\(.*\)".*/\1/')"
	@printf '    seccomp filter: %s\n' "$$(grep -m1 -o 'jroot-seccomp-v[0-9]*' $(SCRIPT))"
	@printf '    proot:         %s\n' "$$(grep -m1 '^PROOT_VERSION=' $(SCRIPT) | cut -d'"' -f2)"
	@if [ -x "$(TARGET)" ] || [ -L "$(TARGET)" ]; then \
		printf '    installed:     %s\n' "$(TARGET)"; \
		if [ -L "$(TARGET)" ]; then printf '                   (symlink -> %s)\n' "$$(readlink "$(TARGET)")"; \
		elif cmp -s "$(SCRIPT)" "$(TARGET)"; then printf '                   up to date with this checkout\n'; \
		else printf '$(YEL)                   differs from this checkout - run "make install"$(NC)\n'; fi; \
	else \
		printf '    installed:     no\n'; \
	fi

doctor:
	@if [ -x "$(TARGET)" ]; then "$(TARGET)" doctor; else bash "$(SCRIPT)" doctor; fi

list:
	@if [ -x "$(TARGET)" ]; then "$(TARGET)" list; else bash "$(SCRIPT)" list; fi

clean:
	@rm -rf "$(BUILDDIR)"
	@printf '$(GRN)[+]$(NC) Removed $(BUILDDIR)\n'
