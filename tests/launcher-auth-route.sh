#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/agy-launcher-auth-route.XXXXXX")"
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'launcher-auth-route: FAIL: %s\n' "$*" >&2
    exit 1
}

compiler=""
for candidate in cc clang; do
    if command -v "$candidate" >/dev/null 2>&1; then
        compiler="$candidate"
        break
    fi
done

if [ -z "$compiler" ]; then
    printf 'launcher-auth-route: skip (no C compiler available)\n'
    exit 0
fi

"$compiler" -O2 -Wall -Wextra -o "$tmp/agy-launcher" "$ROOT_DIR/tools/agy-launcher.c"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/bash" <<'SH'
#!/bin/sh
set -eu

capture="${AGY_LAUNCHER_CAPTURE:-}"
[ -n "$capture" ] || exit 99
{
    printf 'argv0=%s\n' "$0"
    printf 'argv1=%s\n' "${1:-}"
    printf 'argv2=%s\n' "${2:-}"
    printf 'profile=%s\n' "${AGY_PROFILE_HOME:-}"
} >"$capture"
exit 0
SH
chmod 755 "$tmp/bin/bash"

capture="$tmp/capture.txt"
AGY_LAUNCHER_CAPTURE="$capture" \
AGY_PROFILE_HOME="$tmp/profile-home" \
AGY_BASH="$tmp/bin/bash" \
AGY_MANAGED_SHELL="$tmp/managed.sh" \
AGY_LOADER="$tmp/missing-loader" \
AGY_GLIBC_LIB="$tmp/missing-glibc" \
    "$tmp/agy-launcher" auth login >/dev/null 2>&1 || fail 'launcher did not route auth to managed shell'

[ -f "$capture" ] || fail 'managed shell was not invoked for auth'
grep -Fqx "argv0=$tmp/bin/bash" "$capture" || { cat "$capture" >&2; fail 'managed bash was not invoked'; }
grep -Fqx "argv1=$tmp/managed.sh" "$capture" || { cat "$capture" >&2; fail 'managed shell path mismatch'; }
grep -Fqx "argv2=auth" "$capture" || { cat "$capture" >&2; fail 'auth command was not preserved'; }
grep -Fqx "profile=$tmp/profile-home" "$capture" || { cat "$capture" >&2; fail 'profile home was not preserved'; }

printf 'launcher-auth-route: ok\n'
