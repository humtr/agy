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

agy_source_commit() {
    if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown\n'
    else
        printf 'unknown\n'
    fi
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
VERSION_FILE="$AGY_RUNTIME_DIR/wrapper-version.env"
# shellcheck disable=SC1091
. "\$LIB"
if [ -f "\$VERSION_FILE" ]; then
    # shellcheck disable=SC1090
    . "\$VERSION_FILE"
fi
agy_wrapper_info() {
    printf 'agy wrapper: %s\n' "\${AGY_WRAPPER_VERSION:-unknown}"
    printf 'wrapper channel: %s\n' "\${AGY_WRAPPER_CHANNEL:-unknown}"
    printf 'wrapper commit: %s\n' "\${AGY_WRAPPER_COMMIT:-unknown}"
    printf 'wrapper repo: %s\n' "\${AGY_WRAPPER_REPO:-humtr/agy}"
    printf 'public command: %s\n' "$AGY_USER_WRAPPER"
    printf 'runtime raw: %s\n' "$AGY_RAW"
    printf 'runtime patched: %s\n' "$AGY_PATCHED"
    printf 'runtime support: %s\n' "$AGY_RUNTIME_DIR"
    printf 'state: %s\n' "$AGY_STATE_FILE"
    printf 'upstream version command: agy version\n'
}
case "\${1:-}" in
    info)
        shift
        agy_wrapper_info
        exit \$?
        ;;
    repair)
        shift
        echo "agy: starting offline repair..." >&2
        agy_repair manual
        rc=\$?
        if [ "\$rc" -eq 0 ]; then
            echo "agy: repair completed." >&2
        else
            echo "agy: repair failed with exit \$rc." >&2
        fi
        exit "\$rc"
        ;;
    sync)
        shift
        echo "agy: syncing Termux wrapper from main..." >&2
        curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
        rc=\$?
        if [ "\$rc" -eq 0 ]; then
            echo "agy: sync completed. Refresh shell command cache with: hash -r" >&2
        else
            echo "agy: sync failed with exit \$rc." >&2
        fi
        exit "\$rc"
        ;;
esac
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
    local wrapper_commit
    mkdir -p "$(dirname "$AGY_USER_WRAPPER")" "$AGY_RUNTIME_DIR" "$AGY_STATE_DIR"

    cp "$ROOT_DIR/lib/agy-termux-lib.sh" "$AGY_RUNTIME_DIR/lib.sh"
    chmod 755 "$AGY_RUNTIME_DIR/lib.sh"
    cp "$ROOT_DIR/tools/build-runtime.py" "$AGY_RUNTIME_DIR/build-runtime.py"
    chmod 755 "$AGY_RUNTIME_DIR/build-runtime.py"
    cp "$ROOT_DIR/config/verified-agy-version.env" "$AGY_RUNTIME_DIR/verified-agy-version.env"
    chmod 644 "$AGY_RUNTIME_DIR/verified-agy-version.env"
    if [ -f "$ROOT_DIR/config/wrapper-version.env" ]; then
        cp "$ROOT_DIR/config/wrapper-version.env" "$AGY_RUNTIME_DIR/wrapper-version.env"
    else
        printf 'AGY_WRAPPER_VERSION=unknown\nAGY_WRAPPER_CHANNEL=unknown\nAGY_WRAPPER_REPO=humtr/agy\n' >"$AGY_RUNTIME_DIR/wrapper-version.env"
    fi
    wrapper_commit="$(agy_source_commit)"
    {
        printf 'AGY_WRAPPER_COMMIT=%s\n' "$wrapper_commit"
        printf 'AGY_WRAPPER_INSTALLED_AT=%s\n' "$(date -Is)"
    } >>"$AGY_RUNTIME_DIR/wrapper-version.env"
    chmod 644 "$AGY_RUNTIME_DIR/wrapper-version.env"

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
    echo "  $AGY_RUNTIME_DIR/wrapper-version.env"
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
