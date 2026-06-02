#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/agy-termux-lib.sh"

AGY_BACKUP_KEEP="${AGY_BACKUP_KEEP:-2}"
AGY_PUBLIC_LAUNCHER="${PREFIX:-/data/data/com.termux/files/usr}/bin/agy"
AGY_MANAGED_SHELL="${AGY_RUNTIME_DIR}/managed.sh"
AGY_MANAGED_LAUNCHER_MARKER="${AGY_MANAGED_LAUNCHER_MARKER:-agy native managed launcher}"

usage() {
    cat <<'EOF'
Usage: bash bin/install-runtime.sh [setup|support|remove|doctor]

Default action: setup

Actions:
  setup        Install managed launcher and runtime support, then ensure raw/runtime are ready.
  support      Refresh managed launcher/support files without touching raw/runtime.
  remove       Remove managed launcher, runtime files, state, and obsolete shims.
  doctor       Run the local installer/launcher diagnosis checks.

This script never patches the official raw agy binary in place and never runs
agy auth login.
EOF
}

agy_launcher_available() {
    command -v clang >/dev/null 2>&1
}

agy_build_launcher() {
    local out="$1"
    clang -O2 -Wall -Wextra -o "$out" "$ROOT_DIR/tools/agy-launcher.c"
}

agy_source_commit() {
    if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$ROOT_DIR" rev-parse --short=6 HEAD 2>/dev/null || printf 'unknown\n'
    else
        printf 'unknown\n'
    fi
}

agy_prune_file_backups() {
    local pattern="$1"
    local keep="${2:-$AGY_BACKUP_KEEP}"
    python3 - "$pattern" "$keep" <<'PY'
import glob
import os
import sys

pattern = sys.argv[1]
try:
    keep = max(0, int(sys.argv[2]))
except Exception:
    keep = 2
files = [p for p in glob.glob(pattern) if os.path.isfile(p) and not os.path.islink(p)]
files.sort(key=lambda p: (os.path.getmtime(p), p), reverse=True)
for path in files[keep:]:
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
PY
}

agy_prune_backups() {
    agy_prune_file_backups "$AGY_STATE_DIR/agy.launcher.*.bak"
    agy_prune_file_backups "$AGY_STATE_DIR/agy.runtime.*.bak"
    agy_prune_file_backups "$AGY_STATE_DIR/agy.raw.*.bak"
}

agy_write_managed_shell() {
    mkdir -p "$AGY_RUNTIME_DIR"
    cat >"$AGY_RUNTIME_DIR/managed.sh.$$" <<EOF
#!/$PREFIX/bin/bash
# agy native managed shell
set -euo pipefail
unset LD_PRELOAD LD_LIBRARY_PATH
# shellcheck disable=SC1091
. "$AGY_RUNTIME_DIR/lib.sh"
agy_main "\$@"
EOF
    chmod 755 "$AGY_RUNTIME_DIR/managed.sh.$$"
    mv "$AGY_RUNTIME_DIR/managed.sh.$$" "$AGY_MANAGED_SHELL"
    chmod 755 "$AGY_MANAGED_SHELL"
}

agy_prepare_public_launcher_slot() {
    local backup public_dir
    public_dir="${AGY_PUBLIC_LAUNCHER%/*}"
    mkdir -p "$public_dir" "$AGY_STATE_DIR"

    if [ -d "$AGY_PUBLIC_LAUNCHER" ] && [ ! -L "$AGY_PUBLIC_LAUNCHER" ]; then
        printf 'refusing to replace launcher directory %s\n' "$AGY_PUBLIC_LAUNCHER" >&2
        return 1
    fi

    if [ -e "$AGY_PUBLIC_LAUNCHER" ] || [ -L "$AGY_PUBLIC_LAUNCHER" ]; then
        if agy_file_has_marker "$AGY_PUBLIC_LAUNCHER"; then
            rm -f "$AGY_PUBLIC_LAUNCHER"
            return 0
        fi
        if [ -f "$AGY_PUBLIC_LAUNCHER" ] || [ -L "$AGY_PUBLIC_LAUNCHER" ]; then
            backup="$AGY_STATE_DIR/agy.launcher.$(date +%Y%m%d-%H%M%S).bak"
            cp -Pp "$AGY_PUBLIC_LAUNCHER" "$backup"
            rm -f "$AGY_PUBLIC_LAUNCHER"
            return 0
        fi
        printf 'refusing to replace non-file launcher path %s\n' "$AGY_PUBLIC_LAUNCHER" >&2
        return 1
    fi
}

agy_write_shell_launcher() {
    agy_prepare_public_launcher_slot
    mkdir -p "$AGY_STATE_DIR"
    cat >"$AGY_STATE_DIR/agy.launcher.$$" <<EOF
#!/bin/sh
# $AGY_MANAGED_LAUNCHER_MARKER
exec "$AGY_MANAGED_SHELL" "\$@"
EOF
    chmod 755 "$AGY_STATE_DIR/agy.launcher.$$"
    mv "$AGY_STATE_DIR/agy.launcher.$$" "$AGY_PUBLIC_LAUNCHER"
    chmod 755 "$AGY_PUBLIC_LAUNCHER"
}

agy_write_compiled_launcher() {
    local tmp
    mkdir -p "$AGY_STATE_DIR"
    tmp="$AGY_STATE_DIR/agy.launcher.$$"
    agy_build_launcher "$tmp"
    chmod 755 "$tmp"
    if ! agy_file_has_marker "$tmp"; then
        rm -f "$tmp"
        printf 'compiled launcher missing marker: %s\n' "$AGY_MANAGED_LAUNCHER_MARKER" >&2
        return 1
    fi
    agy_prepare_public_launcher_slot || {
        rm -f "$tmp"
        return 1
    }
    mv "$tmp" "$AGY_PUBLIC_LAUNCHER"
    chmod 755 "$AGY_PUBLIC_LAUNCHER"
}

agy_install_support_files() {
    local wrapper_commit
    mkdir -p "$AGY_RUNTIME_DIR" "$AGY_STATE_DIR"
    cp "$ROOT_DIR/lib/agy-termux-lib.sh" "$AGY_RUNTIME_DIR/lib.sh"
    chmod 755 "$AGY_RUNTIME_DIR/lib.sh"
    cp "$ROOT_DIR/tools/build-runtime.py" "$AGY_RUNTIME_DIR/build-runtime.py"
    chmod 755 "$AGY_RUNTIME_DIR/build-runtime.py"
    if [ -f "$ROOT_DIR/config/wrapper-version.env" ]; then
        cp "$ROOT_DIR/config/wrapper-version.env" "$AGY_RUNTIME_DIR/wrapper-version.env"
    else
        cat >"$AGY_RUNTIME_DIR/wrapper-version.env" <<'EOF'
AGY_WRAPPER_VERSION=unknown
AGY_WRAPPER_CHANNEL=unknown
AGY_WRAPPER_REPO=humtr/agy
EOF
    fi
    wrapper_commit="$(agy_source_commit)"
    {
        printf 'AGY_WRAPPER_COMMIT=%s\n' "$wrapper_commit"
        printf 'AGY_WRAPPER_INSTALLED_AT=%s\n' "$(date -Is)"
    } >>"$AGY_RUNTIME_DIR/wrapper-version.env"
    chmod 644 "$AGY_RUNTIME_DIR/wrapper-version.env"
    agy_write_managed_shell
}

agy_install_launcher() {
    if agy_launcher_available; then
        agy_write_compiled_launcher
    else
        agy_write_shell_launcher
    fi
}

agy_ensure_runtime() {
    if [ ! -x "$AGY_RAW" ]; then
        agy_update_broker explicit
        return $?
    fi
    if ! agy_validate_patched || agy_needs_repatch; then
        agy_rebuild_runtime setup
        return $?
    fi
    return 0
}

agy_setup_cleanup() {
    agy_cleanup_obsolete_runtime_surface
}

agy_setup_finalize() {
    agy_prune_backups
    agy_registry_bootstrap_from_current
    agy_print_version_summary "$(agy_current_version 2>/dev/null || true)"
}

agy_setup() {
    agy_install_support_files
    agy_install_launcher
    agy_setup_cleanup
    agy_ensure_runtime
    agy_setup_finalize
}

agy_support() {
    agy_install_support_files
    agy_install_launcher
    agy_setup_cleanup
    agy_setup_finalize
}

agy_do_remove() {
    agy_remove_run
}

case "${1:-setup}" in
    setup)
        agy_setup
        ;;
    support)
        agy_support
        ;;
    remove)
        agy_do_remove
        ;;
    doctor)
        agy_doctor
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
