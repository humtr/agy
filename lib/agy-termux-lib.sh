#!/usr/bin/env bash
set -u

AGY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_PROJECT_ROOT="${AGY_PROJECT_ROOT:-$(cd "$AGY_LIB_DIR/.." && pwd)}"
AGY_HOME="${AGY_HOME:-$HOME}"
AGY_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
AGY_RAW="${AGY_RAW:-$AGY_HOME/.local/bin/agy}"
AGY_RUNTIME_DIR="${AGY_RUNTIME_DIR:-$AGY_HOME/.local/lib/agy-termux}"
AGY_PATCHED="${AGY_PATCHED:-$AGY_RUNTIME_DIR/agy}"
AGY_EXEC_WRAPPER="${AGY_EXEC_WRAPPER:-$AGY_RUNTIME_DIR/run}"
AGY_USER_WRAPPER="${AGY_USER_WRAPPER:-$AGY_HOME/bin/agy}"
AGY_STATE_DIR="${AGY_STATE_DIR:-$AGY_HOME/.local/share/agy-termux}"
AGY_STATE_FILE="${AGY_STATE_FILE:-$AGY_STATE_DIR/state.env}"
AGY_DOCTOR_BASE="${AGY_DOCTOR_BASE:-$AGY_STATE_DIR/doctor}"
if [ -z "${AGY_RUNTIME_BUILDER:-}" ]; then
    if [ -f "$AGY_LIB_DIR/build-runtime.py" ]; then
        AGY_RUNTIME_BUILDER="$AGY_LIB_DIR/build-runtime.py"
    else
        AGY_RUNTIME_BUILDER="$AGY_PROJECT_ROOT/tools/build-runtime.py"
    fi
fi
AGY_LOADER="${AGY_LOADER:-$AGY_PREFIX/glibc/lib/ld-linux-aarch64.so.1}"
AGY_GLIBC_LIB="${AGY_GLIBC_LIB:-$AGY_PREFIX/glibc/lib}"
AGY_SHIM_DIR="${AGY_SHIM_DIR:-$AGY_HOME/.local/glibc-shim}"
AGY_CERT_FILE="${AGY_CERT_FILE:-$AGY_PREFIX/etc/tls/cert.pem}"
AGY_CERT_DIR="${AGY_CERT_DIR:-$AGY_PREFIX/etc/tls/certs}"
AGY_RESOLV_CONF="${AGY_RESOLV_CONF:-$AGY_PREFIX/etc/resolv.conf}"
AGY_RESOLVER_MODE="${AGY_RESOLVER_MODE:-auto}"
AGY_RESOLVER_PROBE_HOST="${AGY_RESOLVER_PROBE_HOST:-oauth2.googleapis.com}"
AGY_MANIFEST_URL="${AGY_MANIFEST_URL:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json}"
AGY_VERSIONED_MANIFEST_BASE="${AGY_VERSIONED_MANIFEST_BASE:-https://storage.googleapis.com/antigravity-public/antigravity-cli}"
if [ -z "${AGY_FALLBACK_VERSION_FILE:-}" ]; then
    if [ -f "$AGY_LIB_DIR/verified-agy-version.env" ]; then
        AGY_FALLBACK_VERSION_FILE="$AGY_LIB_DIR/verified-agy-version.env"
    else
        AGY_FALLBACK_VERSION_FILE="$AGY_PROJECT_ROOT/config/verified-agy-version.env"
    fi
fi
if [ -z "${AGY_VERIFIED_FALLBACK_VERSION:-}" ] && [ -f "$AGY_FALLBACK_VERSION_FILE" ]; then
    # shellcheck disable=SC1090
    . "$AGY_FALLBACK_VERSION_FILE"
fi

agy_sha256() {
    [ -f "$1" ] || return 0
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

agy_load_state() {
    NEEDS_REPATCH=1
    PATCHED_FROM_ORIGINAL_SHA256=""
    PATCHED_SHA256=""
    LAST_RAW_SHA256=""
    LAST_REPAIR_AT=""
    LAST_SELF_UPDATE_AT=""
    if [ -f "$AGY_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$AGY_STATE_FILE"
    fi
}

agy_write_state() {
    mkdir -p "$AGY_STATE_DIR"
    local tmp="$AGY_STATE_FILE.tmp.$$"
    {
        printf 'PATCHED_FROM_ORIGINAL_SHA256=%s\n' "${PATCHED_FROM_ORIGINAL_SHA256:-}"
        printf 'PATCHED_SHA256=%s\n' "${PATCHED_SHA256:-}"
        printf 'LAST_RAW_SHA256=%s\n' "${LAST_RAW_SHA256:-}"
        printf 'NEEDS_REPATCH=%s\n' "${NEEDS_REPATCH:-1}"
        printf 'LAST_REPAIR_AT=%s\n' "${LAST_REPAIR_AT:-}"
        printf 'LAST_SELF_UPDATE_AT=%s\n' "${LAST_SELF_UPDATE_AT:-}"
    } >"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$AGY_STATE_FILE"
}

agy_native_resolver_ok() {
    local getent_bin="$AGY_PREFIX/glibc/bin/getent"
    [ -f "$AGY_PREFIX/glibc/etc/resolv.conf" ] || return 1
    [ -f "$AGY_PREFIX/glibc/etc/nsswitch.conf" ] || return 1
    if [ -x "$getent_bin" ]; then
        env -u LD_PRELOAD -u LD_LIBRARY_PATH \
            LD_LIBRARY_PATH="$AGY_GLIBC_LIB" \
            "$getent_bin" hosts "$AGY_RESOLVER_PROBE_HOST" >/dev/null 2>&1
        return $?
    fi
    return 0
}

agy_select_resolver_mode() {
    case "${AGY_RESOLVER_MODE:-auto}" in
        native)
            printf 'native\n'
            ;;
        proot)
            printf 'proot\n'
            ;;
        auto|"")
            if agy_native_resolver_ok; then
                printf 'native\n'
            elif command -v proot >/dev/null 2>&1 && [ -f "$AGY_RESOLV_CONF" ]; then
                printf 'proot\n'
            else
                printf 'native\n'
            fi
            ;;
        *)
            printf 'native\n'
            ;;
    esac
}

agy_runtime_command() {
    local cert_dir_env=()
    local runtime_env=()
    local resolver_mode
    resolver_mode=$(agy_select_resolver_mode)
    if [ -d "$AGY_CERT_DIR" ]; then
        cert_dir_env=("SSL_CERT_DIR=$AGY_CERT_DIR")
    fi
    runtime_env=(env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        GODEBUG="${GODEBUG:-netdns=cgo}" \
        SSL_CERT_FILE="$AGY_CERT_FILE" \
        LD_LIBRARY_PATH="$AGY_SHIM_DIR:$AGY_GLIBC_LIB" \
        "${cert_dir_env[@]}")
    if [ "$resolver_mode" = "proot" ] && command -v proot >/dev/null 2>&1 && [ -f "$AGY_RESOLV_CONF" ]; then
        proot -b "$AGY_RESOLV_CONF:/etc/resolv.conf" "${runtime_env[@]}" "$@"
    else
        "${runtime_env[@]}" "$@"
    fi
}

agy_run_patched() {
    agy_load_state
    agy_runtime_command "$AGY_PATCHED" "$@"
}

agy_run_candidate() {
    local candidate="$1"
    shift
    agy_load_state
    agy_runtime_command "$candidate" "$@"
}

agy_redact_file() {
    local src="$1"
    local dst="$2"
    sed -E \
        -e 's/(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/Ig' \
        -e 's/(Cookie:[[:space:]]*)[^[:cntrl:]]+/\1[REDACTED]/Ig' \
        -e 's/(Set-Cookie:[[:space:]]*)[^[:cntrl:]]+/\1[REDACTED]/Ig' \
        -e 's/([?&](access_token|refresh_token|id_token|oauth_token|code|state)=)[^&[:space:]]+/\1[REDACTED]/Ig' \
        -e 's/\b(access_token|refresh_token|id_token|oauth_token|code|state)[[:space:]]*[:=][[:space:]]*[^,[:space:]}"]+/\1=[REDACTED]/Ig' \
        -e 's#https?://[^[:space:]]*(code|token|state|oauth)[^[:space:]]*#https://[REDACTED_URL]#Ig' \
        -e 's/TESTSECRET/[REDACTED]/g' \
        -e 's/TEST_ACCESS_TOKEN/[REDACTED]/g' \
        -e 's/TEST_REFRESH_TOKEN/[REDACTED]/g' \
        -e 's/TEST_ID_TOKEN/[REDACTED]/g' \
        -e 's/TEST_CODE/[REDACTED]/g' \
        -e 's/TEST_STATE/[REDACTED]/g' \
        -e 's/TEST_COOKIE/[REDACTED]/g' \
        "$src" >"$dst"
}

agy_last_case_path() {
    if [ -L "$AGY_DOCTOR_BASE/last" ]; then
        readlink -f "$AGY_DOCTOR_BASE/last" 2>/dev/null
    elif [ -f "$AGY_DOCTOR_BASE/last" ]; then
        sed -n '1p' "$AGY_DOCTOR_BASE/last"
    fi
}

agy_set_last_case() {
    local case_dir="$1"
    rm -f "$AGY_DOCTOR_BASE/last"
    ln -s "$(basename "$case_dir")" "$AGY_DOCTOR_BASE/last" 2>/dev/null || printf '%s\n' "$case_dir" >"$AGY_DOCTOR_BASE/last"
}

agy_make_case() {
    local exit_code="$1"
    local raw_log="$2"
    local ts case_dir
    ts=$(date +%Y%m%d-%H%M%S)
    case_dir="$AGY_DOCTOR_BASE/$ts"
    mkdir -p "$case_dir"
    if [ -f "$raw_log" ]; then
        cp "$raw_log" "$case_dir/raw.log"
        agy_redact_file "$raw_log" "$case_dir/safe.log"
    else
        : >"$case_dir/raw.log"
        : >"$case_dir/safe.log"
    fi
    {
        printf 'date=%s\n' "$(date -Is)"
        printf 'exit_code=%s\n' "$exit_code"
        printf 'command_v_agy=%s\n' "$(command -v agy 2>/dev/null || true)"
        printf 'raw_path=%s\n' "$AGY_RAW"
        printf 'patched_path=%s\n' "$AGY_PATCHED"
        printf 'raw_sha256=%s\n' "$(agy_sha256 "$AGY_RAW")"
        printf 'patched_sha256=%s\n' "$(agy_sha256 "$AGY_PATCHED")"
        printf 'state_file=%s\n' "$AGY_STATE_FILE"
        printf 'loader=%s exists=%s\n' "$AGY_LOADER" "$([ -x "$AGY_LOADER" ] && echo yes || echo no)"
        printf 'cert_file=%s exists=%s\n' "$AGY_CERT_FILE" "$([ -f "$AGY_CERT_FILE" ] && echo yes || echo no)"
    } >"$case_dir/env.log"
    {
        printf 'You are diagnosing a Termux native agy wrapper failure.\n\n'
        printf 'Case path: %s\n' "$case_dir"
        printf 'Use safe.log and env.log. Treat raw.log as sensitive local evidence only.\n\n'
        printf 'Requirements:\n'
        printf '%s\n' '- identify the likely failure layer'
        printf '%s\n' '- separate evidence from interpretation'
        printf '%s\n' '- do not touch auth files or rerun auth login'
        printf '%s\n' '- do not overwrite or patch the raw official agy binary'
        printf '%s\n' '- propose minimal safe fix commands'
        printf '%s\n' '- propose rollback commands'
        printf '%s\n' '- state whether automatic editing is safe'
    } >"$case_dir/repair_prompt.txt"
    agy_redact_file "$case_dir/repair_prompt.txt" "$case_dir/repair_prompt.redacted"
    mv "$case_dir/repair_prompt.redacted" "$case_dir/repair_prompt.txt"
    agy_set_last_case "$case_dir"
    printf '%s\n' "$case_dir"
}

agy_wrapper_coherent() {
    [ -x "$AGY_EXEC_WRAPPER" ] || return 1
    grep -q 'agy_run_patched' "$AGY_EXEC_WRAPPER" 2>/dev/null || return 1
    [ -x "$AGY_LOADER" ] || return 1
    [ -f "$AGY_CERT_FILE" ] || return 1
    return 0
}

agy_validate_patched() {
    [ -x "$AGY_PATCHED" ] || return 1
    if command -v patchelf >/dev/null 2>&1; then
        [ "$(patchelf --print-interpreter "$AGY_PATCHED" 2>/dev/null)" = "$AGY_LOADER" ] || return 1
    fi
    agy_run_candidate "$AGY_PATCHED" --version >/dev/null 2>&1
}

agy_needs_repatch() {
    agy_load_state
    local raw_hash patched_hash
    raw_hash=$(agy_sha256 "$AGY_RAW")
    patched_hash=$(agy_sha256 "$AGY_PATCHED")
    [ -n "$raw_hash" ] || return 0
    [ -x "$AGY_PATCHED" ] || return 0
    [ "$raw_hash" = "${PATCHED_FROM_ORIGINAL_SHA256:-}" ] || return 0
    [ -n "$patched_hash" ] || return 0
    [ "$patched_hash" = "${PATCHED_SHA256:-}" ] || return 0
    [ "${NEEDS_REPATCH:-1}" = "0" ] || return 0
    agy_wrapper_coherent || return 0
    agy_validate_patched || return 0
    return 1
}

agy_with_lock() {
    mkdir -p "$AGY_STATE_DIR"
    if command -v flock >/dev/null 2>&1; then
        (
            flock -x 9
            "$@"
        ) 9>"$AGY_STATE_DIR/repair.lock"
    else
        local lock="$AGY_STATE_DIR/repair.lock.d"
        while ! mkdir "$lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$lock" 2>/dev/null || true' RETURN
        "$@"
    fi
}

agy_repair_unlocked() {
    local reason="${1:-preflight}"
    mkdir -p "$AGY_STATE_DIR" "$AGY_DOCTOR_BASE" "$(dirname "$AGY_PATCHED")"
    if [ ! -x "$AGY_RAW" ]; then
        printf 'Raw agy missing or not executable: %s\n' "$AGY_RAW" >&2
        return 1
    fi
    if [ ! -x "$AGY_LOADER" ]; then
        printf 'glibc loader missing: %s\n' "$AGY_LOADER" >&2
        return 1
    fi
    if [ ! -f "$AGY_CERT_FILE" ]; then
        printf 'Termux CA bundle missing: %s\n' "$AGY_CERT_FILE" >&2
        return 1
    fi

    local tmp_dir candidate raw_hash patched_hash old_backup
    tmp_dir=$(mktemp -d "$AGY_STATE_DIR/repair.XXXXXX") || return 1
    candidate="$tmp_dir/agy"

    if ! python3 "$AGY_RUNTIME_BUILDER" "$AGY_RAW" --output "$candidate" >"$tmp_dir/build.log" 2>&1; then
        agy_make_case 70 "$tmp_dir/build.log" >/dev/null
        rm -rf "$tmp_dir"
        return 1
    fi
    if command -v patchelf >/dev/null 2>&1; then
        if ! patchelf --set-interpreter "$AGY_LOADER" "$candidate" >>"$tmp_dir/build.log" 2>&1; then
            agy_make_case 71 "$tmp_dir/build.log" >/dev/null
            rm -rf "$tmp_dir"
            return 1
        fi
    fi
    chmod 755 "$candidate"
    if ! agy_run_candidate "$candidate" --version >>"$tmp_dir/build.log" 2>&1; then
        agy_make_case 72 "$tmp_dir/build.log" >/dev/null
        rm -rf "$tmp_dir"
        return 1
    fi

    if [ -e "$AGY_PATCHED" ]; then
        old_backup="$AGY_STATE_DIR/agy.runtime.$(date +%Y%m%d-%H%M%S).bak"
        cp -p "$AGY_PATCHED" "$old_backup"
    fi
    mv "$candidate" "$AGY_PATCHED"
    chmod 755 "$AGY_PATCHED"
    raw_hash=$(agy_sha256 "$AGY_RAW")
    patched_hash=$(agy_sha256 "$AGY_PATCHED")
    PATCHED_FROM_ORIGINAL_SHA256="$raw_hash"
    PATCHED_SHA256="$patched_hash"
    LAST_RAW_SHA256="$raw_hash"
    NEEDS_REPATCH=0
    LAST_REPAIR_AT="$(date -Is)"
    LAST_SELF_UPDATE_AT="${LAST_SELF_UPDATE_AT:-}"
    agy_write_state
    rm -rf "$tmp_dir"
    printf 'agy: runtime ready (%s)\n' "$reason" >&2
}

agy_repair() {
    agy_with_lock agy_repair_unlocked "${1:-manual}"
}

agy_preflight() {
    if agy_needs_repatch; then
        printf 'agy: preparing runtime copy...\n' >&2
        agy_repair preflight
    fi
}

agy_current_version() {
    agy_run_candidate "$AGY_PATCHED" --version 2>/dev/null | sed -n '1p'
}

agy_manifest_version() {
    local manifest="$1"
    python3 - "$manifest" <<'PY'
import json
import sys
from pathlib import Path

print(json.loads(Path(sys.argv[1]).read_text()).get("version", ""))
PY
}

agy_manifest_field() {
    local manifest="$1"
    local field="$2"
    python3 - "$manifest" "$field" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
field = sys.argv[2]
value = data.get(field, "")
if not value:
    value = data.get("platforms", {}).get("linux-arm", {}).get(field, "")
print(value)
PY
}

agy_versioned_manifest_url() {
    printf '%s/%s/manifest.json\n' "$AGY_VERSIONED_MANIFEST_BASE" "$1"
}

agy_update_broker_once() {
    local manifest_url="$1"
    local source_label="$2"
    local display_mode="${3:-auto}"
    local before after current latest tmp_dir manifest status

    tmp_dir=$(mktemp -d "$AGY_STATE_DIR/update.XXXXXX") || return 1
    manifest="$tmp_dir/manifest.json"
    before=$(agy_sha256 "$AGY_RAW")
    if [ -x "$AGY_PATCHED" ]; then
        current=$(agy_current_version)
    else
        current="none"
    fi

    if [ "$display_mode" = "quiet" ]; then
        :
    elif [ "$display_mode" = "run" ]; then
        printf 'agy: checking for updates...\n' >&2
    else
        printf 'agy: checking %s update source...\n' "$source_label" >&2
    fi
    set +e
    curl -fsSL "$manifest_url" >"$manifest" 2>"$tmp_dir/update.log"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi

    latest=$(agy_manifest_version "$manifest")
    if [ -z "$latest" ]; then
        printf 'agy: update manifest did not contain a version.\n' >"$tmp_dir/update.log"
        agy_make_case 73 "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return 73
    fi

    if [ "$current" = "$latest" ] && [ -x "$AGY_RAW" ]; then
        if [ "$display_mode" = "quiet" ]; then
            :
        elif [ "$display_mode" = "run" ]; then
            printf 'agy: version %s is current.\n' "$latest" >&2
        else
            printf 'agy: already on upstream version %s.\n' "$latest" >&2
        fi
        rm -rf "$tmp_dir"
        return 0
    fi

    local url expected_sha actual_sha extracted raw_backup
    url=$(agy_manifest_field "$manifest" url)
    expected_sha=$(agy_manifest_field "$manifest" sha512)
    if [ -z "$url" ] || [ -z "$expected_sha" ]; then
        printf 'agy: update manifest missing url or sha512.\n' >"$tmp_dir/update.log"
        agy_make_case 74 "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return 74
    fi

    if [ "$display_mode" = "quiet" ]; then
        :
    elif [ "$display_mode" = "run" ]; then
        printf 'agy: installing update %s -> %s...\n' "${current:-unknown}" "$latest" >&2
    else
        printf 'agy: updating official binary %s -> %s from %s...\n' "${current:-unknown}" "$latest" "$source_label" >&2
    fi
    set +e
    curl -fsSL "$url" >"$tmp_dir/agy.tgz" 2>"$tmp_dir/update.log"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi

    actual_sha=$(sha512sum "$tmp_dir/agy.tgz" | awk '{print $1}')
    if [ "$actual_sha" != "$expected_sha" ]; then
        printf 'sha512 mismatch\nexpected=%s\nactual=%s\n' "$expected_sha" "$actual_sha" >"$tmp_dir/update.log"
        agy_make_case 75 "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return 75
    fi

    mkdir -p "$tmp_dir/extract"
    set +e
    tar -xzf "$tmp_dir/agy.tgz" -C "$tmp_dir/extract" >>"$tmp_dir/update.log" 2>&1
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi

    extracted="$tmp_dir/extract/antigravity"
    if [ ! -s "$extracted" ]; then
        printf 'expected extracted antigravity binary not found\n' >"$tmp_dir/update.log"
        agy_make_case 76 "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return 76
    fi

    chmod 755 "$extracted"
    raw_backup="$AGY_STATE_DIR/agy.raw.$(date +%Y%m%d-%H%M%S).bak"
    mkdir -p "$(dirname "$AGY_RAW")"
    if [ -e "$AGY_RAW" ]; then
        cp -p "$AGY_RAW" "$raw_backup"
    fi
    mv "$extracted" "$AGY_RAW"
    chmod 755 "$AGY_RAW"

    after=$(agy_sha256 "$AGY_RAW")
    if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
        agy_mark_raw_changed
    fi
    if [ "$display_mode" != "quiet" ]; then
        printf 'agy: preparing runtime copy for version %s...\n' "$latest" >&2
    fi
    if ! agy_repair wrapper-update; then
        rm -rf "$tmp_dir"
        return 77
    fi
    rm -rf "$tmp_dir"
}

agy_update_broker() {
    local mode="${1:-auto}" status fallback_url fallback_label
    local display_mode="${2:-$mode}"

    if agy_update_broker_once "$AGY_MANIFEST_URL" "current" "$display_mode"; then
        return 0
    fi
    status=$?

    if [ "$mode" != "explicit" ]; then
        printf 'agy: update check failed; continuing with current runtime copy.\n' >&2
        return 0
    fi

    if [ -z "${AGY_VERIFIED_FALLBACK_VERSION:-}" ]; then
        printf 'agy: current update failed and no verified fallback version is configured.\n' >&2
        return "$status"
    fi

    fallback_url=$(agy_versioned_manifest_url "$AGY_VERIFIED_FALLBACK_VERSION")
    fallback_label="verified fallback $AGY_VERIFIED_FALLBACK_VERSION"
    printf 'agy: current update failed; trying %s...\n' "$fallback_label" >&2
    agy_update_broker_once "$fallback_url" "$fallback_label" "$display_mode"
}

agy_auto_update() {
    [ "${AGY_SKIP_AUTO_UPDATE:-0}" = "1" ] && return 0
    [ "${1:-}" = "auth" ] && return 0
    [ "${1:-}" = "--version" ] && { agy_update_broker auto quiet; return $?; }
    agy_update_broker auto run
}

agy_mark_raw_changed() {
    agy_load_state
    local raw_hash
    raw_hash=$(agy_sha256 "$AGY_RAW")
    LAST_RAW_SHA256="$raw_hash"
    NEEDS_REPATCH=1
    LAST_SELF_UPDATE_AT="$(date -Is)"
    agy_write_state
}

agy_status() {
    agy_load_state
    printf 'command -v agy: %s\n' "$(command -v agy 2>/dev/null || true)"
    printf 'type -a agy:\n'
    bash -lc 'type -a agy' 2>/dev/null || true
    printf 'raw agy: %s\n' "$AGY_RAW"
    printf 'raw sha256: %s\n' "$(agy_sha256 "$AGY_RAW")"
    printf 'raw version: not executed directly on Termux\n'
    printf 'patched agy: %s\n' "$AGY_PATCHED"
    printf 'patched sha256: %s\n' "$(agy_sha256 "$AGY_PATCHED")"
    printf 'patched version: '
    agy_run_candidate "$AGY_PATCHED" --version 2>/dev/null || true
    printf 'PATCHED_FROM_ORIGINAL_SHA256: %s\n' "${PATCHED_FROM_ORIGINAL_SHA256:-}"
    printf 'NEEDS_REPATCH: %s\n' "${NEEDS_REPATCH:-1}"
    printf 'glibc loader: %s (%s)\n' "$AGY_LOADER" "$([ -x "$AGY_LOADER" ] && echo ok || echo missing)"
    printf 'SSL_CERT_FILE: %s (%s)\n' "$AGY_CERT_FILE" "$([ -f "$AGY_CERT_FILE" ] && echo ok || echo missing)"
    printf 'SSL_CERT_DIR: %s (%s)\n' "$AGY_CERT_DIR" "$([ -d "$AGY_CERT_DIR" ] && echo ok || echo missing)"
    printf 'resolver mode: %s\n' "${AGY_RESOLVER_MODE:-auto}"
    printf 'resolver selected: %s\n' "$(agy_select_resolver_mode)"
    printf 'resolver native probe: %s (%s)\n' "$AGY_RESOLVER_PROBE_HOST" "$(agy_native_resolver_ok && echo ok || echo failed)"
    printf 'resolv.conf bind source: %s (%s)\n' "$AGY_RESOLV_CONF" "$([ -f "$AGY_RESOLV_CONF" ] && echo ok || echo missing)"
    printf 'proot availability: %s\n' "$(command -v proot >/dev/null 2>&1 && echo available || echo unavailable)"
    printf 'glibc hosts: %s\n' "$AGY_PREFIX/glibc/etc/hosts $([ -f "$AGY_PREFIX/glibc/etc/hosts" ] && echo present || echo missing)"
    printf 'glibc nsswitch: %s\n' "$AGY_PREFIX/glibc/etc/nsswitch.conf $([ -f "$AGY_PREFIX/glibc/etc/nsswitch.conf" ] && echo present || echo missing)"
    printf 'tcmalloc shim policy: removed from runtime and active source\n'
    printf 'update broker: current manifest sha512 verification'
    if [ -n "${AGY_VERIFIED_FALLBACK_VERSION:-}" ]; then
        printf ' with verified fallback %s' "$AGY_VERIFIED_FALLBACK_VERSION"
    fi
    printf '\n'
    printf 'last diagnostic case: %s\n' "$(agy_last_case_path)"
}

agy_show_prompt_path() {
    local last
    last=$(agy_last_case_path)
    if [ -n "$last" ] && [ -f "$last/repair_prompt.txt" ]; then
        printf '%s\n' "$last/repair_prompt.txt"
    else
        printf 'No diagnostic case found.\n'
    fi
}

agy_send_prompt() {
    local tool="$1"
    local prompt
    prompt=$(agy_show_prompt_path)
    if [ ! -f "$prompt" ]; then
        printf '%s\n' "$prompt"
        return 1
    fi
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '%s missing. Prompt path: %s\n' "$tool" "$prompt"
        return 1
    fi
    case "$tool" in
        codex)
            codex exec "$(cat "$prompt")"
            ;;
        gemini)
            gemini <"$prompt"
            ;;
        *)
            "$tool" <"$prompt"
            ;;
    esac
}

agy_termux_menu() {
    while true; do
        printf '\n1. status\n2. show last diagnostic log\n3. show repair prompt path\n4. send last case to Gemini\n5. send last case to Codex\n6. send last case to both\n7. repair-check\n8. exit\n'
        printf 'Select: '
        IFS= read -r opt || return 0
        case "$opt" in
            1) agy_status ;;
            2) last=$(agy_last_case_path); if [ -n "$last" ] && [ -f "$last/safe.log" ]; then sed -n '1,220p' "$last/safe.log"; else printf 'No diagnostic log found.\n'; fi ;;
            3) agy_show_prompt_path ;;
            4) agy_send_prompt gemini ;;
            5) agy_send_prompt codex ;;
            6) agy_send_prompt gemini; agy_send_prompt codex ;;
            7)
                if agy_needs_repatch; then
                    printf 'Repair is needed. Run repair now? [y/N] '
                    IFS= read -r yesno || yesno=n
                    case "$yesno" in
                        y|Y|yes|YES) agy_repair menu ;;
                        *) printf 'No changes made.\n' ;;
                    esac
                else
                    printf 'Repair not needed.\n'
                fi
                ;;
            8) return 0 ;;
            *) printf 'Invalid selection.\n' ;;
        esac
    done
}

agy_main() {
    if [ "${1:-}" = "termux" ] && [ "${AGY_PASSTHROUGH_TERMUX:-0}" != "1" ]; then
        agy_termux_menu
        return 0
    fi

    if [ "${1:-}" = "update" ]; then
        agy_preflight || return $?
        agy_update_broker explicit
        return $?
    fi

    agy_preflight || return $?
    agy_auto_update "${1:-}" || return $?
    agy_preflight || return $?
    if [ "${1:-}" != "--version" ]; then
        printf 'agy: starting Antigravity CLI...\n' >&2
    fi
    local before after temp_raw exit_code case_dir
    before=$(agy_sha256 "$AGY_RAW")
    temp_raw="${TMPDIR:-/tmp}/agy_raw_$$"
    : >"$temp_raw"
    set +e
    agy_load_state
    agy_runtime_command "$AGY_PATCHED" "$@" 2> >(tee "$temp_raw" >&2)
    exit_code=$?
    set -e
    after=$(agy_sha256 "$AGY_RAW")
    if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
        agy_mark_raw_changed
        printf 'Raw agy changed during execution. Rebuilding runtime copy now...\n' >&2
        agy_repair postflight-update
    fi
    if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 130 ]; then
        case_dir=$(agy_make_case "$exit_code" "$temp_raw")
        printf 'agy failed with status %s.\n' "$exit_code" >&2
        printf 'Termux diagnostic case created:\n  %s\n' "$case_dir" >&2
        printf 'Next:\n  agy termux\n' >&2
    fi
    rm -f "$temp_raw"
    return "$exit_code"
}
