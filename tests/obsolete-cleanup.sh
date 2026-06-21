#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/agy-obsolete-cleanup.XXXXXX")"
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

export HOME="$tmp/home"
export PREFIX="$tmp/prefix"
export AGY_TERMUX_ROOT="$HOME/.local/lib/agy/termux"
export AGY_STATE_DIR="$HOME/.local/share/agy/termux"
mkdir -p "$HOME/.local/bin" "$HOME/bin" "$PREFIX/bin" "$AGY_TERMUX_ROOT/runtime" "$AGY_STATE_DIR"

# shellcheck disable=SC1091
. "$ROOT_DIR/lib/agy-termux-lib.sh"

printf 'legacy shim
' >"$HOME/.local/bin/agy"
printf 'legacy shim
' >"$HOME/bin/agy"
printf 'legacy shim
' >"$HOME/.local/bin/agy-t"
printf 'legacy shim
' >"$HOME/bin/agy-t"
printf 'legacy shim
' >"$HOME/bin/agy-termux"
printf 'legacy shim
' >"$PREFIX/bin/agy-t"
mkdir -p "$PREFIX/bin/agy-termux"

printf 'runtime sentinel
' >"$AGY_TERMUX_ROOT/runtime/keep"
printf 'state sentinel
' >"$AGY_STATE_DIR/keep"

cat >"$HOME/.bashrc" <<'EOF'
export BEFORE=1
# >>> agy termux path >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< agy termux path <<<
export AFTER=1
EOF
printf 'export ZSHRC_UNTOUCHED=1
' >"$HOME/.zshrc"

agy_cleanup_obsolete_runtime_surface >"$tmp/obsolete-cleanup.out"

for path in \
    "$HOME/.local/bin/agy" \
    "$HOME/bin/agy" \
    "$HOME/.local/bin/agy-t" \
    "$HOME/bin/agy-t" \
    "$HOME/bin/agy-termux" \
    "$PREFIX/bin/agy-t"; do
    [ ! -e "$path" ] && [ ! -L "$path" ] || { echo "obsolete shim remained: $path" >&2; exit 1; }
done

[ -d "$PREFIX/bin/agy-termux" ] || { echo 'obsolete shim directory was removed' >&2; exit 1; }
[ -f "$AGY_TERMUX_ROOT/runtime/keep" ] || { echo 'runtime root was modified' >&2; exit 1; }
[ -f "$AGY_STATE_DIR/keep" ] || { echo 'state root was modified' >&2; exit 1; }

grep -Fqx 'export BEFORE=1' "$HOME/.bashrc" || { cat "$HOME/.bashrc" >&2; exit 1; }
grep -Fqx 'export AFTER=1' "$HOME/.bashrc" || { cat "$HOME/.bashrc" >&2; exit 1; }
! grep -Fq 'agy termux path' "$HOME/.bashrc" || { cat "$HOME/.bashrc" >&2; exit 1; }
grep -Fqx 'export ZSHRC_UNTOUCHED=1' "$HOME/.zshrc" || { cat "$HOME/.zshrc" >&2; exit 1; }

printf 'obsolete-cleanup: ok
'
