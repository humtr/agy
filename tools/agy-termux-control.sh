#!/usr/bin/env bash
set -euo pipefail

AGY_HOME="${HOME:-/data/data/com.termux/files/home}"
AGY_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
AGY_RUNTIME_LIB="${AGY_RUNTIME_LIB:-$AGY_HOME/.local/lib/agy/native/runtime/lib.sh}"
AGY_NATIVE_ROOT="${AGY_NATIVE_ROOT:-$AGY_HOME/.local/lib/agy/native}"
AGY_RUNTIME_DIR="${AGY_RUNTIME_DIR:-$AGY_NATIVE_ROOT/runtime}"
AGY_STATE_DIR="${AGY_STATE_DIR:-$AGY_HOME/.local/share/agy/native}"
AGY_STATE_FILE="${AGY_STATE_FILE:-$AGY_STATE_DIR/state.json}"
AGY_PATCHED="${AGY_PATCHED:-$AGY_RUNTIME_DIR/agy}"
AGY_RAW="${AGY_RAW:-$AGY_NATIVE_ROOT/raw/agy}"
AGY_LOADER="${AGY_LOADER:-$AGY_PREFIX/glibc/lib/ld-linux-aarch64.so.1}"
AGY_RESOLV_CONF="${AGY_RESOLV_CONF:-$AGY_PREFIX/etc/resolv.conf}"
AGY_SHIM_DIR="${AGY_SHIM_DIR:-$AGY_HOME/.local/glibc-shim}"
AGY_GLIBC_LIB="${AGY_GLIBC_LIB:-$AGY_PREFIX/glibc/lib}"
AGY_USER_LAUNCHER="${AGY_USER_LAUNCHER:-$AGY_HOME/bin/agy}"
AGY_CONTROL_BIN="${AGY_CONTROL_BIN:-$AGY_HOME/bin/agy-termux}"
AGY_SHELL_FALLBACK="${AGY_SHELL_FALLBACK:-$AGY_RUNTIME_DIR/agy-shell-wrapper.sh}"
AGY_PROJECT_ROOT="${AGY_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [ ! -f "$AGY_RUNTIME_LIB" ]; then
    AGY_RUNTIME_LIB="$AGY_PROJECT_ROOT/lib/agy-termux-lib.sh"
fi
# shellcheck disable=SC1090
. "$AGY_RUNTIME_LIB"

usage() {
    cat <<'EOF'
Usage: agy-termux <command> [args]

Commands:
  status                 Print runtime/launcher status
  doctor                 Validate launcher/runtime wiring and warn on drift
  update [--dry-run]     Run Termux raw->patched update pipeline
  repair                 Rebuild patched runtime from raw binary
  rollback [--dry-run]   Restore last runtime backup
  install-launcher       Build/install compiled launcher
  install-shell-wrapper  Install shell fallback wrapper
  test-native            Native fd33 resolver smoke test
  test-proot             Diagnostic-only proot resolver smoke test
  install                Termux-safe install/launcher refresh
  version                Print control plane version
  paths                  Print canonical path layout
  route -- <args...>     Route args through agy runtime command path
  debug bundle           Print latest diagnostic artifacts
  uninstall [--yes]      Remove generated runtime/launcher artifacts (dry-run default)
EOF
}

agy_latest_runtime_backup() {
    ls -1t "$AGY_STATE_DIR"/agy.runtime.*.bak 2>/dev/null | head -n 1
}

agy_latest_raw_backup() {
    ls -1t "$AGY_STATE_DIR"/agy.raw.*.bak 2>/dev/null | head -n 1
}

agy_runtime_counts() {
    local p="$1"
    python3 - "$p" <<'PY'
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
print(b.count(b"/etc/resolv.conf"), b.count(b"/proc/self/fd/33"))
PY
}

agy_doctor() {
    local active resolver_counts etc_count fd33_count lock_file
    active=$(command -v agy 2>/dev/null || true)
    printf 'active agy: %s\n' "$active"
    if [ -n "$active" ] && [ "$active" = "$AGY_PATCHED" ]; then
        printf 'warning: active agy points to patched runtime directly (unsupported)\n'
    fi
    if [ -x "$active" ] && file "$active" 2>/dev/null | grep -qi 'ELF'; then
        printf 'launcher binary: ok\n'
    else
        printf 'launcher binary: fallback-shell-or-missing\n'
    fi
    if [ -x "$AGY_PATCHED" ]; then
        resolver_counts="$(agy_runtime_counts "$AGY_PATCHED")"
        etc_count="$(printf '%s' "$resolver_counts" | awk '{print $1}')"
        fd33_count="$(printf '%s' "$resolver_counts" | awk '{print $2}')"
        printf 'runtime /etc/resolv.conf count: %s\n' "$etc_count"
        printf 'runtime /proc/self/fd/33 count: %s\n' "$fd33_count"
    else
        printf 'runtime: missing\n'
    fi
    printf 'control plane executable: %s\n' "$([ -x "$AGY_CONTROL_BIN" ] && echo ok || echo missing)"
    printf 'loader executable: %s (%s)\n' "$AGY_LOADER" "$([ -x "$AGY_LOADER" ] && echo ok || echo missing)"
    printf 'shim dir: %s (%s)\n' "$AGY_SHIM_DIR" "$([ -d "$AGY_SHIM_DIR" ] && echo present || echo missing)"
    printf 'resolver source readable: %s (%s)\n' "$AGY_RESOLV_CONF" "$([ -r "$AGY_RESOLV_CONF" ] && echo yes || echo no)"
    printf 'state file: %s (%s)\n' "$AGY_STATE_FILE" "$([ -f "$AGY_STATE_FILE" ] && echo present || echo missing)"
    lock_file="${AGY_LOCK_FILE:-$AGY_STATE_DIR/native.lock}"
    printf 'update lock file: %s (%s)\n' "$lock_file" "$([ -f "$lock_file" ] && echo present || echo absent)"
    local ld_preload ld_library_path
    ld_preload="${LD_PRELOAD:-}"
    ld_library_path="${LD_LIBRARY_PATH:-}"

    if [ -z "$ld_preload" ]; then
        printf 'warning: parent LD_PRELOAD is unset; termux-exec may be inactive.\n'
    elif printf '%s' "$ld_preload" | grep -q 'libtermux-exec-ld-preload.so'; then
        if printf '%s' "$ld_preload" | grep -q ':'; then
            printf 'warning: parent LD_PRELOAD includes termux-exec plus extra entries.\n'
        else
            printf 'parent LD_PRELOAD: termux-exec baseline detected\n'
        fi
    else
        printf 'warning: parent LD_PRELOAD is non-termux value.\n'
    fi

    if [ -z "$ld_library_path" ]; then
        printf 'parent LD_LIBRARY_PATH: none\n'
    else
        printf 'warning: parent LD_LIBRARY_PATH is set\n'
        if printf '%s' "$ld_library_path" | grep -q "$AGY_SHIM_DIR\\|$AGY_GLIBC_LIB"; then
            printf 'error: parent LD_LIBRARY_PATH includes glibc/shim path; this is linker pollution risk.\n'
        fi
    fi
}

agy_update_termux() {
    if [ "${1:-}" = "--dry-run" ]; then
        agy_with_lock _agy_update_termux_dryrun
        return $?
    fi
    agy_with_lock _agy_update_termux_apply
}

_agy_update_termux_dryrun() {
    printf 'dry-run: would run Termux raw->patched update pipeline\n'
    printf 'dry-run: source manifest=%s\n' "$AGY_MANIFEST_URL"
}

_agy_update_termux_apply() {
    agy_preflight || return $?
    agy_update_broker explicit explicit
}

agy_rollback_termux() {
    local runtime_bak raw_bak
    runtime_bak=$(agy_latest_runtime_backup || true)
    raw_bak=$(agy_latest_raw_backup || true)
    if [ "${1:-}" = "--dry-run" ]; then
        printf 'dry-run: runtime backup=%s\n' "${runtime_bak:-none}"
        printf 'dry-run: raw backup=%s\n' "${raw_bak:-none}"
        return 0
    fi
    [ -n "$runtime_bak" ] || { printf 'no runtime backup found\n' >&2; return 1; }
    agy_with_lock _agy_rollback_apply "$runtime_bak" "$raw_bak"
}

_agy_rollback_apply() {
    local runtime_bak="$1" raw_bak="$2"
    cp -p "$runtime_bak" "$AGY_PATCHED"
    chmod 755 "$AGY_PATCHED"
    if [ -n "$raw_bak" ] && [ -f "$raw_bak" ]; then
        cp -p "$raw_bak" "$AGY_RAW"
        chmod 755 "$AGY_RAW"
    fi
    PATCHED_FROM_ORIGINAL_SHA256="$(agy_sha256 "$AGY_RAW")"
    PATCHED_SHA256="$(agy_sha256 "$AGY_PATCHED")"
    LAST_RAW_SHA256="$PATCHED_FROM_ORIGINAL_SHA256"
    NEEDS_REPATCH=0
    LAST_REPAIR_AT="$(date -Is)"
    agy_write_state
    printf 'rollback applied: runtime=%s raw=%s\n' "$runtime_bak" "${raw_bak:-none}"
}

agy_test_native() {
    timeout 45 env AGY_SKIP_AUTO_UPDATE=1 "$AGY_USER_LAUNCHER" --print "Reply exactly: AGY_TERMUX_TEST_NATIVE_OK"
}

agy_test_proot() {
    if ! command -v proot >/dev/null 2>&1; then
        printf 'proot is unavailable\n' >&2
        return 1
    fi
    timeout 45 proot -b "$AGY_RESOLV_CONF:/etc/resolv.conf" env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        HOME="$AGY_HOME" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$AGY_HOME/.config}" \
        XDG_CACHE_HOME="${XDG_CACHE_HOME:-$AGY_HOME/.cache}" XDG_DATA_HOME="${XDG_DATA_HOME:-$AGY_HOME/.local/share}" \
        GODEBUG="${GODEBUG:-netdns=go}" SSL_CERT_FILE="${AGY_CERT_FILE:-$AGY_PREFIX/etc/tls/cert.pem}" \
        "$AGY_LOADER" --library-path "$AGY_SHIM_DIR:$AGY_GLIBC_LIB" "$AGY_PATCHED" \
        --print "Reply exactly: AGY_PROOT_FALLBACK_STILL_OK"
}

agy_uninstall() {
    if [ "${1:-}" != "--yes" ]; then
        printf 'dry-run uninstall targets:\n'
        printf '  %s\n' "$AGY_USER_LAUNCHER"
        printf '  %s\n' "$AGY_CONTROL_BIN"
        printf '  %s\n' "$AGY_PATCHED"
        printf '  %s\n' "$AGY_SHELL_FALLBACK"
        return 0
    fi
    rm -f "$AGY_USER_LAUNCHER" "$AGY_CONTROL_BIN" "$AGY_PATCHED" "$AGY_SHELL_FALLBACK"
    printf 'uninstall completed (auth/token/cache untouched)\n'
}

agy_install_safe() {
    if [ -x "$AGY_USER_LAUNCHER" ] && [ -x "$AGY_CONTROL_BIN" ] && [ -x "$AGY_PATCHED" ]; then
        printf 'install: already initialized (idempotent)\n'
        printf 'launcher=%s\n' "$AGY_USER_LAUNCHER"
        printf 'control=%s\n' "$AGY_HOME/.local/bin/agy-t"
        return 0
    fi
    if [ -f "$AGY_PROJECT_ROOT/bin/install-runtime.sh" ]; then
        bash "$AGY_PROJECT_ROOT/bin/install-runtime.sh" --install
        return $?
    fi
    printf 'install: runtime assets missing. Run main install.sh bootstrap from repository.\n' >&2
    return 2
}

agy_paths() {
    printf 'public launcher: %s\n' "$AGY_USER_LAUNCHER"
    printf 'public local shim: %s\n' "$AGY_HOME/.local/bin/agy"
    printf 'management cmd: %s\n' "$AGY_HOME/.local/bin/agy-t"
    printf 'raw private: %s\n' "$AGY_RAW"
    printf 'patched runtime private: %s\n' "$AGY_PATCHED"
    printf 'state file: %s\n' "$AGY_STATE_FILE"
}

agy_route() {
    if [ "${1:-}" = "--" ]; then
        shift
    fi
    agy_run_patched "$@"
}

agy_debug_bundle() {
    local last
    last=$(agy_last_case_path || true)
    printf 'last_case=%s\n' "${last:-none}"
    printf 'warning: raw.log may contain sensitive material. Do not share without review.\n'
    if [ -n "${last:-}" ] && [ -d "$last" ]; then
        ls -1 "$last" 2>/dev/null || true
    fi
}

case "${1:-}" in
    status) agy_status ;;
    doctor) agy_doctor ;;
    update) shift; agy_update_termux "$@" ;;
    repair) agy_repair control-plane ;;
    rollback) shift; agy_rollback_termux "$@" ;;
    install-launcher) agy_install_safe ;;
    install-shell-wrapper) bash "$AGY_PROJECT_ROOT/bin/install-runtime.sh" --install-shell-wrapper ;;
    test-native) agy_test_native ;;
    test-proot) agy_test_proot ;;
    install) agy_install_safe ;;
    paths) agy_paths ;;
    route) shift; agy_route "$@" ;;
    debug) shift; [ "${1:-}" = "bundle" ] && agy_debug_bundle || { usage >&2; exit 2; } ;;
    version) printf 'agy-termux control-plane 1\n' ;;
    uninstall) shift; agy_uninstall "$@" ;;
    -h|--help|"") usage ;;
    *) printf 'unknown command: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
