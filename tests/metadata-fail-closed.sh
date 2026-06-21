#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/agy-metadata-test.XXXXXX")"
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

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

ok_repo="$tmp/ok-repo"
copy_repo "$ok_repo"
run_support "$ok_repo" "$tmp/ok-home" "$tmp/ok-prefix" "$tmp/ok.log" \
    || { cat "$tmp/ok.log" >&2; exit 1; }

ok_metadata="$tmp/ok-home/.local/lib/agy/termux/runtime/wrapper-version.env"
[ -f "$ok_metadata" ] || { cat "$tmp/ok.log" >&2; echo 'metadata was not installed' >&2; exit 1; }
! grep -Fq 'AGY_WRAPPER_VERSION=unknown' "$ok_metadata" \
    || { cat "$ok_metadata" >&2; echo 'metadata fallback leaked into normal install' >&2; exit 1; }

missing_repo="$tmp/missing-repo"
copy_repo "$missing_repo"
rm -f "$missing_repo/config/wrapper-version.env"

set +e
run_support "$missing_repo" "$tmp/missing-home" "$tmp/missing-prefix" "$tmp/missing.log"
status=$?
set -e

[ "$status" -ne 0 ] || { cat "$tmp/missing.log" >&2; echo 'support succeeded without wrapper metadata' >&2; exit 1; }
grep -Fq 'wrapper metadata missing' "$tmp/missing.log" \
    || { cat "$tmp/missing.log" >&2; echo 'missing metadata error not reported' >&2; exit 1; }

missing_metadata="$tmp/missing-home/.local/lib/agy/termux/runtime/wrapper-version.env"
[ ! -f "$missing_metadata" ] \
    || { cat "$missing_metadata" >&2; echo 'metadata file was created despite missing source metadata' >&2; exit 1; }

printf 'metadata-fail-closed: ok\n'
