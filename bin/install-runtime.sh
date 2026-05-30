#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/agy-termux-lib.sh"

usage() {
    cat <<'EOF'
Usage: bash bin/install-runtime.sh [--install|--status|--repair|--install-wrappers|--install-launcher|--install-shell-wrapper|--init-state]

Default action: --status

Actions:
  --install          Install wrappers, download/update raw agy, and build the runtime copy.
  --status           Print current wrapper/runtime status.
  --repair           Reinstall wrappers and rebuild the patched runtime copy from raw agy.
  --install-wrappers Install the agy launcher, runtime support files, and shell fallback.
  --install-launcher Build/install compiled launcher at ~/bin/agy.
  --install-shell-wrapper Install shell fallback wrapper.
  --init-state       Initialize state.json after validating the current runtime copy.

This script never modifies the raw official agy binary in place and never runs
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

remove_legacy_control_shims() {
    local p
    for p in \
        "$AGY_HOME/.local/bin/agy-t" \
        "$AGY_HOME/bin/agy-t" \
        "$AGY_HOME/bin/agy-termux" \
        "$AGY_PREFIX/bin/agy-t" \
        "$AGY_PREFIX/bin/agy-termux"; do
        if [ -e "$p" ]; then
            rm -f "$p"
            echo "Removed legacy control shim:"
            echo "  $p"
        fi
    done
}

install_shell_fallback() {
    mkdir -p "$AGY_RUNTIME_DIR"
cat >"$AGY_RUNTIME_DIR/agy-shell-wrapper.sh" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
unset LD_PRELOAD LD_LIBRARY_PATH
LIB="$AGY_RUNTIME_DIR/lib.sh"
# shellcheck disable=SC1091
. "\$LIB"
agy_main "\$@"
EOF
    chmod 755 "$AGY_RUNTIME_DIR/agy-shell-wrapper.sh"
}

install_compiled_launcher() {
    local tmp launcher_bin backup
    launcher_bin="$AGY_USER_WRAPPER"
    mkdir -p "$(dirname "$launcher_bin")"
    tmp="$AGY_STATE_DIR/agy-launcher.$$"
    mkdir -p "$AGY_STATE_DIR"
    agy_build_launcher "$tmp"
    chmod 755 "$tmp"
    if [ -e "$launcher_bin" ]; then
        backup="$AGY_STATE_DIR/agy.launcher.$(date +%Y%m%d-%H%M%S).bak"
        cp -p "$launcher_bin" "$backup"
        echo "Backed up launcher:"
        echo "  $backup"
    fi
    mv "$tmp" "$launcher_bin"
    chmod 755 "$launcher_bin"
}

install_local_launcher_shim() {
    local local_launcher="$AGY_HOME/.local/bin/agy"
    mkdir -p "$(dirname "$local_launcher")"
    cat >"$local_launcher" <<EOF
#!/bin/sh
set -eu
exec "$AGY_USER_WRAPPER" "\$@"
EOF
    chmod 755 "$local_launcher"
}

migrate_legacy_raw() {
    local legacy_raw="$AGY_HOME/.local/bin/agy"
    local legacy_runtime_raw="$AGY_HOME/.local/bin/agy.raw-legacy"
    mkdir -p "$(dirname "$AGY_RAW")"
    if [ -x "$AGY_RAW" ]; then
        return 0
    fi
    if [ -x "$legacy_raw" ] && file "$legacy_raw" 2>/dev/null | grep -q 'ELF'; then
        cp -p "$legacy_raw" "$AGY_RAW"
        chmod 755 "$AGY_RAW"
        mv "$legacy_raw" "$legacy_runtime_raw"
        return 0
    fi
    if [ -x "$legacy_runtime_raw" ]; then
        cp -p "$legacy_runtime_raw" "$AGY_RAW"
        chmod 755 "$AGY_RAW"
    fi
}

install_wrappers() {
    mkdir -p "$(dirname "$AGY_USER_WRAPPER")" "$AGY_RUNTIME_DIR" "$AGY_STATE_DIR"

    cp "$ROOT_DIR/lib/agy-termux-lib.sh" "$AGY_RUNTIME_DIR/lib.sh"
    chmod 755 "$AGY_RUNTIME_DIR/lib.sh"
    cp "$ROOT_DIR/tools/build-runtime.py" "$AGY_RUNTIME_DIR/build-runtime.py"
    chmod 755 "$AGY_RUNTIME_DIR/build-runtime.py"
    cp "$ROOT_DIR/config/verified-agy-version.env" "$AGY_RUNTIME_DIR/verified-agy-version.env"
    chmod 644 "$AGY_RUNTIME_DIR/verified-agy-version.env"

cat >"$AGY_EXEC_WRAPPER" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
unset LD_PRELOAD LD_LIBRARY_PATH
LIB="$AGY_RUNTIME_DIR/lib.sh"
# shellcheck disable=SC1091
. "\$LIB"
agy_run_patched "\$@"
EOF

    chmod 755 "$AGY_EXEC_WRAPPER"
    if agy_launcher_available; then
        install_compiled_launcher
        echo "Installed launcher:"
        echo "  $AGY_USER_WRAPPER"
    else
        install_shell_fallback
        cp "$AGY_RUNTIME_DIR/agy-shell-wrapper.sh" "$AGY_USER_WRAPPER"
        chmod 755 "$AGY_USER_WRAPPER"
        echo "clang unavailable, installed shell fallback launcher:"
        echo "  $AGY_USER_WRAPPER"
    fi
    install_shell_fallback
    install_local_launcher_shim
    install_prefix_wrapper
    remove_legacy_control_shims
    ensure_user_path

    mkdir -p "$AGY_SHIM_DIR"
    if [ -f "$AGY_GLIBC_LIB/libc.so.6" ]; then
        ln -sfn "$AGY_GLIBC_LIB/libc.so.6" "$AGY_SHIM_DIR/libc.so.6"
        ln -sfn "$AGY_GLIBC_LIB/libc.so.6" "$AGY_SHIM_DIR/libc.so"
    fi

    mkdir -p "$AGY_PREFIX/glibc/etc"
    [ -f "$AGY_PREFIX/glibc/etc/resolv.conf" ] || printf 'nameserver 8.8.8.8\n' >"$AGY_PREFIX/glibc/etc/resolv.conf"
    [ -f "$AGY_PREFIX/glibc/etc/nsswitch.conf" ] || printf 'hosts: files dns\n' >"$AGY_PREFIX/glibc/etc/nsswitch.conf"
    [ -f "$AGY_PREFIX/glibc/etc/hosts" ] || printf '127.0.0.1 localhost\n' >"$AGY_PREFIX/glibc/etc/hosts"

    echo "Installed PATH command:"
    echo "  $AGY_USER_WRAPPER"
    echo "  $AGY_HOME/.local/bin/agy"
    echo "  $AGY_PREFIX/bin/agy"
    echo "  $AGY_EXEC_WRAPPER"
    echo "Installed runtime support:"
    echo "  $AGY_RUNTIME_DIR/lib.sh"
    echo "  $AGY_RUNTIME_DIR/build-runtime.py"
    echo "  $AGY_RUNTIME_DIR/verified-agy-version.env"
    echo "Installed shell fallback:"
    echo "  $AGY_RUNTIME_DIR/agy-shell-wrapper.sh"
    echo "Ensured startup PATH includes:"
    echo "  $HOME/bin"
    echo "Note: refresh shell command cache with 'hash -r' (bash) or 'rehash' (zsh)."
}

install_prefix_wrapper() {
    local prefix_wrapper backup
    prefix_wrapper="$AGY_PREFIX/bin/agy"
    mkdir -p "$(dirname "$prefix_wrapper")"

    if [ -e "$prefix_wrapper" ] && ! grep -Fq 'agy-termux managed prefix wrapper' "$prefix_wrapper" 2>/dev/null; then
        backup="$prefix_wrapper.backup-$(date +%Y%m%d-%H%M%S)"
        cp -p "$prefix_wrapper" "$backup"
        echo "Backed up existing PATH wrapper:"
        echo "  $backup"
    fi

    cat >"$prefix_wrapper" <<EOF
#!/bin/sh
# agy-termux managed prefix wrapper
exec "$AGY_USER_WRAPPER" "\$@"
EOF
    chmod 755 "$prefix_wrapper"
}

ensure_user_path() {
    local rc marker_begin marker_end line backup
    marker_begin="# >>> agy native path >>>"
    marker_end="# <<< agy native path <<<"
    line='export PATH="$HOME/bin:$PATH"'

    for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || touch "$rc"
        if grep -Fq "$marker_begin" "$rc"; then
            continue
        fi
        if grep -Fq '$HOME/bin' "$rc" || grep -Fq '~/bin' "$rc"; then
            continue
        fi
        backup="$AGY_STATE_DIR/$(basename "$rc").backup-$(date +%Y%m%d-%H%M%S)"
        cp -p "$rc" "$backup"
        {
            printf '\n%s\n' "$marker_begin"
            printf '%s\n' "$line"
            printf '%s\n' "$marker_end"
        } >>"$rc"
    done
}

init_state() {
    if ! agy_validate_patched; then
        echo "Current runtime copy is not valid; run --repair first." >&2
        return 1
    fi
    PATCHED_FROM_ORIGINAL_SHA256="$(agy_sha256 "$AGY_RAW")"
    PATCHED_SHA256="$(agy_sha256 "$AGY_PATCHED")"
    LAST_RAW_SHA256="$PATCHED_FROM_ORIGINAL_SHA256"
    NEEDS_REPATCH=0
    LAST_REPAIR_AT="${LAST_REPAIR_AT:-$(date -Is)}"
    LAST_SELF_UPDATE_AT="${LAST_SELF_UPDATE_AT:-}"
    VERIFIED_VERSION="$(agy_current_version)"
    agy_write_state
    echo "Initialized state: $AGY_STATE_FILE"
}

action="${1:---status}"
case "$action" in
    --install)
        agy_with_lock install_wrappers
        agy_with_lock migrate_legacy_raw
        agy_update_broker explicit
        ;;
    --status)
        agy_status
        ;;
    --repair)
        agy_with_lock install_wrappers
        agy_with_lock migrate_legacy_raw
        agy_repair setup
        ;;
    --install-wrappers)
        agy_with_lock install_wrappers
        agy_with_lock migrate_legacy_raw
        ;;
    --install-launcher)
        install_compiled_launcher
        ;;
    --install-shell-wrapper)
        install_shell_fallback
        cp "$AGY_RUNTIME_DIR/agy-shell-wrapper.sh" "$AGY_USER_WRAPPER"
        chmod 755 "$AGY_USER_WRAPPER"
        ;;
    --init-state)
        init_state
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
