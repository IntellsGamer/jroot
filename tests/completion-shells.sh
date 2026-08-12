#!/usr/bin/env bash
# Parse generated completion scripts with their target shells. Fish also exposes a
# non-interactive completion query, so exercise dynamic helpers there rather than
# trusting syntax alone. The fixture is metadata-only: no jail is started.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export JROOT_HOME="$tmp/home"

mkdir -p "$JROOT_HOME/configs" "$JROOT_HOME/roots/dev/etc" \
         "$JROOT_HOME/snapshots/dev/checkpoints/baseline" \
         "$JROOT_HOME/plugins/ledger"
printf '%s\n' '{"name":"dev","image":"ubuntu:22.04"}' > "$JROOT_HOME/configs/dev.json"
printf '%s\n' '{"name":"ledger","version":"1.0.0"}' > "$JROOT_HOME/plugins/ledger/plugin.json"

bash "$root/jroot" completion zsh > "$tmp/_jroot"
bash "$root/jroot" completion fish > "$tmp/jroot.fish"

if command -v zsh >/dev/null 2>&1; then
    zsh -n "$tmp/_jroot"
    zsh -f -c 'autoload -Uz compinit; compinit -D; source "$1"; whence -w _jroot; whence -w _jroot_checkpoints; whence -w _jroot_plugins' zsh "$tmp/_jroot" >/dev/null
    printf 'zsh completion parses and registers helpers\n'
else
    printf 'zsh not installed; static completion coverage still checked\n'
fi

if command -v fish >/dev/null 2>&1; then
    fish --no-execute "$tmp/jroot.fish"
    cat > "$tmp/fish-smoke.fish" <<'FISH'
source $argv[1]

function require_candidate
    set -l line $argv[1]
    set -l expected $argv[2]
    for item in (complete -C "jroot $line")
        if string match -q -- "$expected*" $item
            return 0
        end
    end
    echo "missing '$expected' for: jroot $line" >&2
    exit 1
end

require_candidate '' sync
require_candidate 'sync ' dev:
require_candidate 'limit dev --' --mem=
require_candidate 'compose ' status
require_candidate 'checkpoint ' dev
require_candidate 'checkpoint ' diff
require_candidate 'checkpoint diff ' dev
require_candidate 'checkpoint diff dev ' baseline
require_candidate 'rm-checkpoint dev ' baseline
require_candidate 'plugin service ' start
require_candidate 'plugin service start ' ledger
FISH
    fish "$tmp/fish-smoke.fish" "$tmp/jroot.fish"
    printf 'fish completion parses and dynamic candidates work\n'
else
    printf 'fish not installed; static completion coverage still checked\n'
fi
