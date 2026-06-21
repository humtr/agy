#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/agy-installed-runtime-isolation.XXXXXX")"
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'installed-runtime-isolation: FAIL: %s\n' "$*" >&2
    exit 1
}

copy_repo() {
    local dst="$1"
    mkdir -p "$dst"
    (cd "$ROOT_DIR" && tar --exclude=.git -cf - .) | (cd "$dst" && tar -xf -)
}

run_support() {
    local repo="$1" home_dir="$2" prefix_dir="$3" log_file="$4"
    mkdir -p "$home_dir" "$prefix_dir/bin"
    PREFIX="$prefix_dir" \
    HOME="$home_dir" \
    AGY_TERMUX_ROOT="$home_dir/.local/lib/agy/termux" \
    AGY_STATE_DIR="$home_dir/.local/share/agy/termux" \
    AGY_SKIP_AUTO_UPDATE=1 \
        bash "$repo/bin/install-runtime.sh" support >"$log_file" 2>&1
}

repo="$tmp/repo"
home_dir="$tmp/home"
prefix_dir="$tmp/prefix"
log_file="$tmp/support.log"
copy_repo "$repo"

run_support "$repo" "$home_dir" "$prefix_dir" "$log_file" \
    || { cat "$log_file" >&2; fail 'support failed'; }

runtime_dir="$home_dir/.local/lib/agy/termux/runtime"
managed="$runtime_dir/managed.sh"
runtime_lib="$runtime_dir/lib.sh"
builder="$runtime_dir/build-runtime.py"
metadata="$runtime_dir/wrapper-version.env"
launcher="$prefix_dir/bin/agy"

[ -f "$managed" ] || { cat "$log_file" >&2; fail 'managed shell was not installed'; }
[ -f "$runtime_lib" ] || { cat "$log_file" >&2; fail 'runtime lib was not installed'; }
[ -f "$builder" ] || { cat "$log_file" >&2; fail 'runtime builder was not installed'; }
[ -f "$metadata" ] || { cat "$log_file" >&2; fail 'wrapper metadata was not installed'; }
[ -x "$launcher" ] || { cat "$log_file" >&2; fail 'public launcher was not installed'; }

! grep -Fq 'AGY_MANAGED_REPO_LIB' "$managed" \
    || { cat "$managed" >&2; fail 'managed shell sources development checkout lib'; }
! grep -Fq 'AGY_INSTALLED_REPO_ROOT' "$managed" \
    || { cat "$managed" >&2; fail 'managed shell records development checkout root'; }

grep -Fq '. "'$runtime_dir'/lib.sh"' "$managed" \
    || { cat "$managed" >&2; fail 'managed shell does not source installed runtime lib'; }

repo_marker="installed-runtime-isolation-test-marker"
printf '%s\n' "$repo_marker" >>"$repo/lib/agy-termux-lib.sh"
! grep -Fq "$repo_marker" "$runtime_lib" \
    || fail 'runtime lib changed when checkout changed without support refresh'

grep -Fq 'AGY_WRAPPER_COMMIT=' "$metadata" \
    || { cat "$metadata" >&2; fail 'installed metadata missing wrapper commit'; }

printf 'installed-runtime-isolation: ok\n'
