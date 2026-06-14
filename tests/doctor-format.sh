#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'doctor-format: FAIL: %s\n' "$*" >&2
    exit 1
}

output="$(bash "$ROOT_DIR/bin/install-runtime.sh" doctor)"

printf '%s\n' "$output" | grep -Eq '^agy doctor v[^[:space:]]+ · Termux native$' \
    || fail "title line missing or changed"
printf '%s\n' "$output" | grep -Fqx 'Installation' \
    || fail "installation section missing"
printf '%s\n' "$output" | grep -Fqx 'Runtime' \
    || fail "runtime section missing"
printf '%s\n' "$output" | grep -Fqx 'Environment' \
    || fail "environment section missing"
printf '%s\n' "$output" | grep -Fqx 'State' \
    || fail "state section missing"
printf '%s\n' "$output" | grep -Fqx 'Registry' \
    || fail "registry section missing"
printf '%s\n' "$output" | grep -Eq '^[0-9]+ ok · [0-9]+ idle · [0-9]+ warn · [0-9]+ fail ok$' \
    || fail "summary line missing or changed"

printf 'doctor-format: ok\n'
