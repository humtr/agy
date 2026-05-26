#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/agy-termux-lib.sh"

usage() {
    cat <<'EOF'
Usage: bash bin/install-runtime.sh [--install|--status|--repair|--install-wrappers|--init-state]

Default action: --status

Actions:
  --install          Install wrappers, download/update raw agy, and build the runtime copy.
  --status           Print current wrapper/runtime status.
  --repair           Transactionally rebuild ~/.local/lib/agy-termux/agy from raw agy.
  --install-wrappers Install ~/bin/agy and ~/.local/lib/agy-termux/run wrappers.
  --init-state       Initialize state.env after validating the current runtime copy.

This script never modifies the raw official agy binary in place and never runs
agy auth login.
EOF
}

install_wrappers() {
    mkdir -p "$(dirname "$AGY_USER_WRAPPER")" "$AGY_RUNTIME_DIR" "$AGY_STATE_DIR"

    install -m 755 "$ROOT_DIR/lib/agy-termux-lib.sh" "$AGY_RUNTIME_DIR/lib.sh"
    install -m 755 "$ROOT_DIR/tools/build-runtime.py" "$AGY_RUNTIME_DIR/build-runtime.py"
    install -m 644 "$ROOT_DIR/config/verified-agy-version.env" "$AGY_RUNTIME_DIR/verified-agy-version.env"

    cat >"$AGY_USER_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LIB="$AGY_RUNTIME_DIR/lib.sh"
# shellcheck disable=SC1091
. "\$LIB"
agy_main "\$@"
EOF

    cat >"$AGY_EXEC_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LIB="$AGY_RUNTIME_DIR/lib.sh"
# shellcheck disable=SC1091
. "\$LIB"
agy_run_patched "\$@"
EOF

    chmod 755 "$AGY_USER_WRAPPER" "$AGY_EXEC_WRAPPER"
    ensure_user_path
    install_prefix_wrapper

    mkdir -p "$AGY_SHIM_DIR"
    if [ -f "$AGY_GLIBC_LIB/libc.so.6" ]; then
        ln -sfn "$AGY_GLIBC_LIB/libc.so.6" "$AGY_SHIM_DIR/libc.so.6"
        ln -sfn "$AGY_GLIBC_LIB/libc.so.6" "$AGY_SHIM_DIR/libc.so"
    fi

    mkdir -p "$AGY_PREFIX/glibc/etc"
    [ -f "$AGY_PREFIX/glibc/etc/resolv.conf" ] || printf 'nameserver 8.8.8.8\n' >"$AGY_PREFIX/glibc/etc/resolv.conf"
    [ -f "$AGY_PREFIX/glibc/etc/nsswitch.conf" ] || printf 'hosts: files dns\n' >"$AGY_PREFIX/glibc/etc/nsswitch.conf"
    [ -f "$AGY_PREFIX/glibc/etc/hosts" ] || printf '127.0.0.1 localhost\n' >"$AGY_PREFIX/glibc/etc/hosts"

    echo "Installed wrappers:"
    echo "  $AGY_USER_WRAPPER"
    echo "  $AGY_PREFIX/bin/agy"
    echo "  $AGY_EXEC_WRAPPER"
    echo "Installed runtime support:"
    echo "  $AGY_RUNTIME_DIR/lib.sh"
    echo "  $AGY_RUNTIME_DIR/build-runtime.py"
    echo "  $AGY_RUNTIME_DIR/verified-agy-version.env"
    echo "Ensured startup PATH includes:"
    echo "  $HOME/bin"
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
#!/usr/bin/env bash
# agy-termux managed prefix wrapper
exec "$AGY_USER_WRAPPER" "\$@"
EOF
    chmod 755 "$prefix_wrapper"
}

ensure_user_path() {
    local rc marker line
    marker="# agy-termux PATH"
    line='export PATH="$HOME/bin:$PATH"'

    for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ] && grep -Fq "$marker" "$rc"; then
            continue
        fi
        if [ -f "$rc" ] && { grep -Fq '$HOME/bin' "$rc" || grep -Fq '~/bin' "$rc"; }; then
            continue
        fi
        {
            printf '\n%s\n' "$marker"
            printf '%s\n' "$line"
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
        install_wrappers
        agy_update_broker explicit
        ;;
    --status)
        agy_status
        ;;
    --repair)
        install_wrappers
        agy_repair setup
        ;;
    --install-wrappers)
        install_wrappers
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
