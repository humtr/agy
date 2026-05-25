#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/agy-termux-lib.sh"

usage() {
    cat <<'EOF'
Usage: bash setup_agy_termux.sh [--status|--repair|--install-wrappers|--init-state]

Default action: --status

Actions:
  --status           Print current wrapper/runtime status.
  --repair           Transactionally rebuild ~/.local/bin/agy.va39 from raw agy.
  --install-wrappers Install ~/bin/agy and ~/.local/bin/agy-va39 wrappers.
  --init-state       Initialize state.env after validating the current patched runtime.

This script never patches the raw official agy binary in place and never runs
agy auth login.
EOF
}

install_wrappers() {
    mkdir -p "$(dirname "$AGY_USER_WRAPPER")" "$(dirname "$AGY_EXEC_WRAPPER")" "$AGY_STATE_DIR"

    cat >"$AGY_USER_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/prj/agy"
# shellcheck disable=SC1091
. "$ROOT/lib/agy-termux-lib.sh"
agy_main "$@"
EOF

    cat >"$AGY_EXEC_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/prj/agy"
# shellcheck disable=SC1091
. "$ROOT/lib/agy-termux-lib.sh"
agy_run_patched "$@"
EOF

    chmod 755 "$AGY_USER_WRAPPER" "$AGY_EXEC_WRAPPER"

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
    echo "  $AGY_EXEC_WRAPPER"
}

init_state() {
    if ! agy_validate_patched; then
        echo "Current patched runtime is not valid; run --repair first." >&2
        return 1
    fi
    PATCHED_FROM_ORIGINAL_SHA256="$(agy_sha256 "$AGY_RAW")"
    PATCHED_SHA256="$(agy_sha256 "$AGY_PATCHED")"
    LAST_RAW_SHA256="$PATCHED_FROM_ORIGINAL_SHA256"
    NEEDS_REPATCH=0
    LAST_REPAIR_AT="${LAST_REPAIR_AT:-$(date -Is)}"
    LAST_SELF_UPDATE_AT="${LAST_SELF_UPDATE_AT:-}"
    TCMALLOC_POLICY="${TCMALLOC_POLICY:-gated}"
    agy_write_state
    echo "Initialized state: $AGY_STATE_FILE"
}

action="${1:---status}"
case "$action" in
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
