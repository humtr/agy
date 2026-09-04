#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/agy-raw-changed-rebuild.XXXXXX")"
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'raw-changed-rebuild: FAIL: %s\n' "$*" >&2
    exit 1
}

export HOME="$tmp/home"
export PREFIX="$tmp/prefix"
export AGY_TERMUX_ROOT="$HOME/.local/lib/agy/termux"
export AGY_STATE_DIR="$HOME/.local/share/agy/termux"
export AGY_RUNTIME_DIR="$AGY_TERMUX_ROOT/runtime"
export AGY_STORE_DIR="$AGY_STATE_DIR/store"
export AGY_RAW="$AGY_TERMUX_ROOT/raw/agy"
export AGY_PATCHED="$AGY_RUNTIME_DIR/agy"
export AGY_LOADER="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
export AGY_GLIBC_LIB="$PREFIX/glibc/lib"
export AGY_CERT_FILE="$PREFIX/etc/tls/cert.pem"
export AGY_RESOLV_CONF="$PREFIX/etc/resolv.conf"
export AGY_MANAGED_SHELL="$AGY_RUNTIME_DIR/managed.sh"
export AGY_PUBLIC_LAUNCHER="$PREFIX/bin/agy"
export AGY_SKIP_AUTO_UPDATE=1
export AGY_AUTO_UPDATE_DISABLED=1

mkdir -p "$HOME" "$PREFIX/bin" "$tmp/bin" "$PREFIX/etc/tls" "$PREFIX/glibc/lib" "$AGY_TERMUX_ROOT/raw" "$AGY_RUNTIME_DIR" "$AGY_STATE_DIR"
touch "$AGY_CERT_FILE"
echo "nameserver 1.1.1.1" > "$AGY_RESOLV_CONF"

export PATH="$PREFIX/bin:$tmp/bin:$PATH"

# Install support files
bash "$ROOT_DIR/bin/install-runtime.sh" support >"$tmp/support.log" 2>&1 \
    || { cat "$tmp/support.log" >&2; fail 'support installation failed'; }

# Source installed runtime lib
# shellcheck disable=SC1091
. "$AGY_RUNTIME_DIR/lib.sh"

# Mock loader
cat >"$AGY_LOADER" <<'SH'
#!/bin/sh
set -eu
shift 2
exe="$1"
shift
case "${1:-}" in
    --release_base_url=*) shift ;;
esac
exec "$exe" "$@"
SH
chmod 755 "$AGY_LOADER"

# Mock patchelf
cat >"$tmp/bin/patchelf" <<SH
#!/bin/sh
if [ "\${1:-}" = "--print-interpreter" ]; then
    printf '%s\\n' "$AGY_LOADER"
    exit 0
fi
exit 0
SH
chmod 755 "$tmp/bin/patchelf"

# Mock strings to satisfy doctor rewrite verification
cat >"$tmp/bin/strings" <<'SH'
#!/bin/sh
printf '/proc/self/fd/33\n/proc/self/fd/33\n'
SH
chmod 755 "$tmp/bin/strings"

# Mock raw binary that will mutate itself when MUTATE_RAW_ON_RUN is set
cat >"$AGY_RAW" <<'SH'
#!/bin/sh
# /proc/self/fd/33
if [ "${1:-}" = "--version" ]; then
    echo "1.1.25"
    exit 0
fi
if [ -n "${MUTATE_RAW_ON_RUN:-}" ]; then
    cat >"$AGY_RAW" <<'NEWRAW'
#!/bin/sh
# /proc/self/fd/33
if [ "${1:-}" = "--version" ]; then
    echo "1.1.26"
    exit 0
fi
exit 0
NEWRAW
    chmod 755 "$AGY_RAW"
fi
exit 0
SH
chmod 755 "$AGY_RAW"

cp "$AGY_RAW" "$AGY_PATCHED"

# Mock runtime builder
cat >"$AGY_RUNTIME_DIR/build-runtime.py" <<'PY'
#!/usr/bin/env python3
import sys, shutil, json, pathlib
args = sys.argv[1:]
raw_in = args[0]
out_idx = args.index("--output")
out_path = args[out_idx + 1]
shutil.copyfile(raw_in, out_path)
if "--report-json" in args:
    rep_idx = args.index("--report-json")
    pathlib.Path(args[rep_idx + 1]).write_text(json.dumps({
        "total": 2,
        "bitfield_counts": {},
        "pair_counts": {},
        "word_counts": {},
        "syscall_count": 0,
        "resolver_path_count": 2,
        "allocator_profile": "mock",
        "allocator_required": False,
        "allocator_status": "ok",
        "missing_required": []
    }))
PY
chmod 755 "$AGY_RUNTIME_DIR/build-runtime.py"

# Bootstrap registry and state
agy_bootstrap_setup >/dev/null 2>&1 || true
agy_registry_bootstrap_from_current

initial_raw_hash="$(agy_sha256 "$AGY_RAW")"
initial_patched_hash="$(agy_sha256 "$AGY_PATCHED")"

output_log="$tmp/run.log"
MUTATE_RAW_ON_RUN=1 agy_run_bare_runtime >"$output_log" 2>&1 || true

new_raw_hash="$(agy_sha256 "$AGY_RAW")"
new_patched_hash="$(agy_sha256 "$AGY_PATCHED")"

[ "$initial_raw_hash" != "$new_raw_hash" ] || fail 'raw binary was not updated'
[ "$initial_patched_hash" != "$new_patched_hash" ] || fail 'patched runtime was not updated'
[ "$new_raw_hash" = "$new_patched_hash" ] || fail 'new patched runtime does not match new raw'

grep -Fq 'raw changed during execution; rebuilding runtime copy.' "$output_log" \
    || { cat "$output_log" >&2; fail 'postflight rebuild notice was not emitted'; }

grep -Fq 'runtime ready (postflight-update)' "$output_log" \
    || { cat "$output_log" >&2; fail 'runtime ready notice was not emitted'; }

! agy_needs_repatch || fail 'runtime repatch needed after successful postflight rebuild'

doctor_log="$tmp/doctor.log"
agy_doctor >"$doctor_log" 2>&1 || true

! grep -Eq '[1-9][0-9]* fail' "$doctor_log" \
    || { cat "$doctor_log" >&2; fail 'agy doctor reported failure after postflight rebuild'; }

! grep -Eq '[1-9][0-9]* warn' "$doctor_log" \
    || { cat "$doctor_log" >&2; fail 'agy doctor reported warning after postflight rebuild'; }

printf 'raw-changed-rebuild: ok\n'
