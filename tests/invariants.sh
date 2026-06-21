#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    printf 'invariants: FAIL: %s\n' "$1" >&2
    exit 1
}

pass() {
    printf 'invariants: ok\n'
}

require_file() {
    [ -f "$1" ] || fail "required file missing: $1"
}

require_executable() {
    [ -x "$1" ] || fail "required executable missing or not executable: $1"
}

reject_grep() {
    local pattern="$1" output
    shift
    output="$(mktemp "${TMPDIR:-/tmp}/agy-invariant-grep.XXXXXX")" || fail "could not create grep output file"
    if grep -RIn --binary-files=without-match --exclude='invariants.sh' --exclude-dir=.git "$pattern" "$@" >"$output" 2>/dev/null; then
        cat "$output" >&2
        rm -f "$output"
        fail "forbidden pattern found: $pattern"
    fi
    rm -f "$output"
}

require_grep() {
    local pattern="$1" path="$2" label="$3"
    grep -Eq "$pattern" "$path" || fail "$label missing in $path"
}

require_file README.md
require_file .gitignore
require_file config/wrapper-version.env
require_file docs/AGY_TERMUX_GUIDE.md
require_file docs/AGY_TERMUX_LAUNCHER.md
require_file bin/install-runtime.sh
require_file lib/agy-termux-lib.sh
require_file tools/build-runtime.py
require_file tools/agy-launcher.c
require_file tests/doctor-format.sh
require_file tests/doctor-color.sh
require_file tests/metadata-fail-closed.sh
require_file tests/obsolete-cleanup.sh
require_file tests/installed-runtime-isolation.sh
require_file tests/run-all.sh

require_executable install.sh
require_executable bin/install-runtime.sh
require_executable tools/build-runtime.py
require_executable tests/doctor-format.sh
require_executable tests/doctor-color.sh
require_executable tests/metadata-fail-closed.sh
require_executable tests/obsolete-cleanup.sh
require_executable tests/installed-runtime-isolation.sh
require_executable tests/invariants.sh
require_executable tests/run-all.sh

[ ! -e docs/AGY_TERMUX_NATIVE_GUIDE.md ] || fail 'obsolete native guide filename exists'
[ ! -e docs/AGY_TERMUX_COMPILED_LAUNCHER.md ] || fail 'obsolete launcher doc filename exists'

reject_grep 'AGY_NATIVE_ROOT' README.md docs bin lib config install.sh tools tests
reject_grep 'native\.lock' README.md docs bin lib config install.sh tools tests
reject_grep '/agy/native' README.md docs bin lib config install.sh tools tests
reject_grep 'AGY_TERMUX_NATIVE_GUIDE' README.md docs bin lib config install.sh tools tests
reject_grep 'AGY_TERMUX_COMPILED_LAUNCHER' README.md docs bin lib config install.sh tools tests

require_grep '^AGY_WRAPPER_VERSION=' config/wrapper-version.env 'wrapper version'
require_grep '^AGY_WRAPPER_CHANNEL=' config/wrapper-version.env 'wrapper channel'
require_grep '^AGY_WRAPPER_REPO=humtr/agy$' config/wrapper-version.env 'wrapper repo'
! grep -Eq '=unknown$' config/wrapper-version.env || fail 'wrapper metadata contains unknown value'

require_grep 'wrapper metadata missing' bin/install-runtime.sh 'metadata fail-closed message'
! grep -Fq 'AGY_WRAPPER_VERSION=unknown' bin/install-runtime.sh || fail 'install-runtime fallback metadata remains'
require_grep 'metadata-fail-closed: ok' tests/metadata-fail-closed.sh 'metadata fail-closed focused test'

require_grep 'AGY_TERMUX_ROOT=.*\.local/lib/agy/termux' lib/agy-termux-lib.sh 'termux runtime root default'
require_grep 'AGY_STATE_DIR=.*\.local/share/agy/termux' lib/agy-termux-lib.sh 'termux state root default'
require_grep 'termux\.lock' lib/agy-termux-lib.sh 'termux lock name'

require_grep 'Obsolete cleanup policy' docs/AGY_TERMUX_GUIDE.md 'obsolete cleanup policy docs'
require_grep 'Obsolete cleanup policy' lib/agy-termux-lib.sh 'obsolete cleanup policy code comment'
require_grep 'obsolete-cleanup: ok' tests/obsolete-cleanup.sh 'obsolete cleanup focused test'
require_grep 'does not remove the current' README.md 'README cleanup boundary'
require_grep 'does not remove the current runtime' docs/AGY_TERMUX_GUIDE.md 'guide cleanup boundary'

require_grep 'tests/doctor-format\.sh' tests/run-all.sh 'doctor-format in run-all'
require_grep 'tests/doctor-color\.sh' tests/run-all.sh 'doctor-color in run-all'
require_grep 'tests/metadata-fail-closed\.sh' tests/run-all.sh 'metadata test in run-all'
require_grep 'tests/obsolete-cleanup\.sh' tests/run-all.sh 'obsolete cleanup test in run-all'
require_grep 'tests/installed-runtime-isolation\.sh' tests/run-all.sh 'installed runtime isolation test in run-all'
require_grep 'tests/invariants\.sh' tests/run-all.sh 'invariants in run-all'
reject_grep 'AGY_MANAGED_REPO_LIB' bin/install-runtime.sh docs 'managed shell must not source development checkout lib'
reject_grep 'AGY_INSTALLED_REPO_ROOT' bin/install-runtime.sh docs 'managed shell must not record development checkout root'
require_grep 'sources only the installed runtime support copy' docs/AGY_TERMUX_LAUNCHER.md 'installed runtime support isolation docs'
require_grep 'installed-runtime-isolation: ok' tests/installed-runtime-isolation.sh 'installed runtime isolation focused test'

pass
