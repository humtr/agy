#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
esc="$(printf '\033')"

fail() {
    printf 'doctor-color: FAIL: %s\n' "$*" >&2
    exit 1
}

contains_ansi() {
    grep -Fq "$esc["
}

output="$(AGY_SKIP_AUTO_UPDATE=1 AGY_DOCTOR_COLOR=always bash "$ROOT_DIR/bin/install-runtime.sh" doctor || true)"
printf '%s\n' "$output" | contains_ansi \
    || fail 'AGY_DOCTOR_COLOR=always did not emit ANSI escape sequences'

output="$(AGY_SKIP_AUTO_UPDATE=1 AGY_DOCTOR_COLOR=never bash "$ROOT_DIR/bin/install-runtime.sh" doctor || true)"
! printf '%s\n' "$output" | contains_ansi \
    || fail 'AGY_DOCTOR_COLOR=never emitted ANSI escape sequences'

output="$(AGY_SKIP_AUTO_UPDATE=1 NO_COLOR=1 bash "$ROOT_DIR/bin/install-runtime.sh" doctor || true)"
! printf '%s\n' "$output" | contains_ansi \
    || fail 'NO_COLOR=1 emitted ANSI escape sequences'

printf 'doctor-color: ok\n'
