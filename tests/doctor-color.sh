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
printf '%s\n' "$output" | grep -Fq "$esc[38;5;10m✓" \
    || fail 'ok mark does not use Codex bright green'
printf '%s\n' "$output" | grep -Fq "$esc[38;5;214mwarn" \
    || fail 'summary warn label does not use Codex orange'
printf '%s\n' "$output" | grep -Fq "$esc[38;5;196mfail" \
    || fail 'summary fail label does not use Codex bright red'
summary_raw="$(printf '%s\n' "$output" | python3 -c 'import re,sys; ansi=re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]"); lines=sys.stdin.read().splitlines(); print(next((l for l in lines if " ok · " in ansi.sub("", l) and " fail " in ansi.sub("", l)), ""))')"
[ -n "$summary_raw" ] || fail 'raw summary line missing'
summary_line="$(printf '%s\n' "$summary_raw" | python3 -c 'import re,sys; ansi=re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]"); sys.stdout.write(ansi.sub("", sys.stdin.read()))')"
[ -n "$summary_line" ] || fail 'plain summary line missing'
printf '%s\n' "$summary_raw" | grep -Fq "$esc[38;5;10mok$esc[39m" \
    || fail 'summary ok label is not Codex bright green'
! printf '%s\n' "$summary_raw" | grep -Fq "$esc[1m" \
    || fail 'summary line contains bold status styling'
case "$summary_line" in
    *' ok')
        [ "$(printf '%s\n' "$summary_raw" | grep -Fo "$esc[38;5;10mok$esc[39m" | wc -l | tr -d ' ')" = "2" ] \
            || fail 'summary ok label and final ok are not the same color sequence'
        ;;
    *' warn')
        [ "$(printf '%s\n' "$summary_raw" | grep -Fo "$esc[38;5;214mwarn$esc[39m" | wc -l | tr -d ' ')" = "2" ] \
            || fail 'summary warn label and final warn are not the same color sequence'
        ;;
    *' fail')
        [ "$(printf '%s\n' "$summary_raw" | grep -Fo "$esc[38;5;196mfail$esc[39m" | wc -l | tr -d ' ')" = "2" ] \
            || fail 'summary fail label and final fail are not the same color sequence'
        ;;
    *)
        fail "unknown summary status: $summary_line"
        ;;
esac
! printf '%s\n' "$output" | grep -Fq "$esc[32m" \
    || fail 'legacy green ANSI 32 was emitted'
! printf '%s\n' "$output" | grep -Fq "$esc[33m" \
    || fail 'legacy yellow ANSI 33 was emitted'
! printf '%s\n' "$output" | grep -Fq "$esc[31m" \
    || fail 'legacy red ANSI 31 was emitted'
plain="$(printf '%s\n' "$output" | python3 -c 'import re,sys; sys.stdout.write(re.sub("\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read()))')"
printf '%s\n' "$plain" | grep -Fq ' runtime        ' \
    || fail 'primary doctor label column is not Codex wrapper width'

output="$(AGY_SKIP_AUTO_UPDATE=1 AGY_DOCTOR_COLOR=never bash "$ROOT_DIR/bin/install-runtime.sh" doctor || true)"
! printf '%s\n' "$output" | contains_ansi \
    || fail 'AGY_DOCTOR_COLOR=never emitted ANSI escape sequences'

output="$(AGY_SKIP_AUTO_UPDATE=1 NO_COLOR=1 bash "$ROOT_DIR/bin/install-runtime.sh" doctor || true)"
! printf '%s\n' "$output" | contains_ansi \
    || fail 'NO_COLOR=1 emitted ANSI escape sequences'

printf 'doctor-color: ok\n'
