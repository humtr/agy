#!/usr/bin/env bash
set -u

AGY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_PROJECT_ROOT="${AGY_PROJECT_ROOT:-$(cd "$AGY_LIB_DIR/.." && pwd)}"
AGY_HOME="${AGY_HOME:-$HOME}"
AGY_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
AGY_NATIVE_ROOT="${AGY_NATIVE_ROOT:-$AGY_HOME/.local/lib/agy/native}"
AGY_RAW="${AGY_RAW:-$AGY_NATIVE_ROOT/raw/agy}"
AGY_RUNTIME_DIR="${AGY_RUNTIME_DIR:-$AGY_NATIVE_ROOT/runtime}"
AGY_PATCHED="${AGY_PATCHED:-$AGY_RUNTIME_DIR/agy}"
AGY_STATE_DIR="${AGY_STATE_DIR:-$AGY_HOME/.local/share/agy/native}"
AGY_STATE_FILE="${AGY_STATE_FILE:-$AGY_STATE_DIR/state.json}"
AGY_DOCTOR_BASE="${AGY_DOCTOR_BASE:-$AGY_STATE_DIR/doctor}"
AGY_LOCK_FILE="${AGY_LOCK_FILE:-$AGY_STATE_DIR/native.lock}"
AGY_LOCK_WAIT_SECONDS="${AGY_LOCK_WAIT_SECONDS:-30}"
AGY_DIAG_KEEP="${AGY_DIAG_KEEP:-20}"
if [ -z "${AGY_RUNTIME_BUILDER:-}" ]; then
    if [ -f "$AGY_LIB_DIR/build-runtime.py" ]; then
        AGY_RUNTIME_BUILDER="$AGY_LIB_DIR/build-runtime.py"
    else
        AGY_RUNTIME_BUILDER="$AGY_PROJECT_ROOT/tools/build-runtime.py"
    fi
fi
AGY_LOADER="${AGY_LOADER:-$AGY_PREFIX/glibc/lib/ld-linux-aarch64.so.1}"
AGY_GLIBC_LIB="${AGY_GLIBC_LIB:-$AGY_PREFIX/glibc/lib}"
AGY_CERT_FILE="${AGY_CERT_FILE:-$AGY_PREFIX/etc/tls/cert.pem}"
AGY_CERT_DIR="${AGY_CERT_DIR:-$AGY_PREFIX/etc/tls/certs}"
AGY_RESOLV_CONF="${AGY_RESOLV_CONF:-$AGY_PREFIX/etc/resolv.conf}"
AGY_RESOLVER_FD=33
AGY_RESOLVER_PROBE_HOST="${AGY_RESOLVER_PROBE_HOST:-oauth2.googleapis.com}"
AGY_REPO_URL="${AGY_REPO_URL:-https://github.com/humtr/agy.git}"
AGY_BRANCH="${AGY_BRANCH:-main}"
AGY_MANAGED_LAUNCHER_MARKER="${AGY_MANAGED_LAUNCHER_MARKER:-agy native managed launcher}"
AGY_MANIFEST_URL="${AGY_MANIFEST_URL:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json}"
AGY_AUTO_UPDATE_TIMEOUT="${AGY_AUTO_UPDATE_TIMEOUT:-4}"
agy_sha256() {
    [ -f "$1" ] || return 0
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

agy_file_has_marker() {
    local path="$1" marker="${2:-$AGY_MANAGED_LAUNCHER_MARKER}"
    [ -e "$path" ] || [ -L "$path" ] || return 1
    grep -aFq "$marker" "$path" 2>/dev/null
}

agy_state_defaults() {
    NEEDS_REPATCH=1
    PATCHED_FROM_ORIGINAL_SHA256=""
    PATCHED_SHA256=""
    LAST_RAW_SHA256=""
    LAST_REPAIR_AT=""
    LAST_SELF_UPDATE_AT=""
    VERIFIED_VERSION=""
    VERIFIED_WRAPPER_VERSION=""
    VERIFIED_WRAPPER_COMMIT=""
    VERIFIED_RAW_SHA256=""
    VERIFIED_PATCHED_SHA256=""
    VERIFIED_AT=""
    VERIFIED_ENTRYPOINT=""
    LAST_SEEN_UPSTREAM_VERSION=""
    LAST_FAILED_UPDATE_VERSION=""
    LAST_FAILED_UPDATE_STATUS=""
    LAST_FAILED_UPDATE_AT=""
    LAST_FAILED_UPDATE_CASE=""
}

agy_safe_state_kv() {
    local key="$1" val="$2"
    case "$key" in
        PATCHED_FROM_ORIGINAL_SHA256|PATCHED_SHA256|LAST_RAW_SHA256|LAST_REPAIR_AT|LAST_SELF_UPDATE_AT|VERIFIED_VERSION|VERIFIED_WRAPPER_VERSION|VERIFIED_WRAPPER_COMMIT|VERIFIED_RAW_SHA256|VERIFIED_PATCHED_SHA256|VERIFIED_AT|VERIFIED_ENTRYPOINT|LAST_SEEN_UPSTREAM_VERSION|LAST_FAILED_UPDATE_VERSION|LAST_FAILED_UPDATE_STATUS|LAST_FAILED_UPDATE_AT|LAST_FAILED_UPDATE_CASE|NEEDS_REPATCH) ;;
        *) return 1 ;;
    esac
    case "$val" in
        *[\`\$\\\"\']* ) return 1 ;;
    esac
    return 0
}

agy_state_read_json() {
    local path="$1"
    python3 - "$path" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.exists():
    raise SystemExit(0)
d=json.loads(p.read_text())
keys=[
 "PATCHED_FROM_ORIGINAL_SHA256","PATCHED_SHA256","LAST_RAW_SHA256","LAST_REPAIR_AT",
 "LAST_SELF_UPDATE_AT","VERIFIED_VERSION","VERIFIED_WRAPPER_VERSION",
 "VERIFIED_WRAPPER_COMMIT","VERIFIED_RAW_SHA256","VERIFIED_PATCHED_SHA256",
 "VERIFIED_AT","VERIFIED_ENTRYPOINT","LAST_SEEN_UPSTREAM_VERSION",
 "LAST_FAILED_UPDATE_VERSION","LAST_FAILED_UPDATE_STATUS","LAST_FAILED_UPDATE_AT",
 "LAST_FAILED_UPDATE_CASE","NEEDS_REPATCH"]
for k in keys:
    v=d.get(k,"")
    if isinstance(v,bool):
        v="1" if v else "0"
    elif v is None:
        v=""
    else:
        v=str(v)
    print(f"{k}\t{v}")
PY
}

agy_state_write_json() {
    mkdir -p "$AGY_STATE_DIR"
    python3 - \
        "$AGY_STATE_FILE" \
        "$PATCHED_FROM_ORIGINAL_SHA256" \
        "$PATCHED_SHA256" \
        "$LAST_RAW_SHA256" \
        "$NEEDS_REPATCH" \
        "$LAST_REPAIR_AT" \
        "$LAST_SELF_UPDATE_AT" \
        "$VERIFIED_VERSION" \
        "$VERIFIED_WRAPPER_VERSION" \
        "$VERIFIED_WRAPPER_COMMIT" \
        "$VERIFIED_RAW_SHA256" \
        "$VERIFIED_PATCHED_SHA256" \
        "$VERIFIED_AT" \
        "$VERIFIED_ENTRYPOINT" \
        "$LAST_SEEN_UPSTREAM_VERSION" \
        "$LAST_FAILED_UPDATE_VERSION" \
        "$LAST_FAILED_UPDATE_STATUS" \
        "$LAST_FAILED_UPDATE_AT" \
        "$LAST_FAILED_UPDATE_CASE" <<'PY'
import json,os,sys,tempfile
path=sys.argv[1]
dirp=os.path.dirname(path)
state={
 "PATCHED_FROM_ORIGINAL_SHA256":sys.argv[2],
 "PATCHED_SHA256":sys.argv[3],
 "LAST_RAW_SHA256":sys.argv[4],
 "NEEDS_REPATCH":sys.argv[5],
 "LAST_REPAIR_AT":sys.argv[6],
 "LAST_SELF_UPDATE_AT":sys.argv[7],
 "VERIFIED_VERSION":sys.argv[8],
 "VERIFIED_WRAPPER_VERSION":sys.argv[9],
 "VERIFIED_WRAPPER_COMMIT":sys.argv[10],
 "VERIFIED_RAW_SHA256":sys.argv[11],
 "VERIFIED_PATCHED_SHA256":sys.argv[12],
 "VERIFIED_AT":sys.argv[13],
 "VERIFIED_ENTRYPOINT":sys.argv[14],
 "LAST_SEEN_UPSTREAM_VERSION":sys.argv[15],
 "LAST_FAILED_UPDATE_VERSION":sys.argv[16],
 "LAST_FAILED_UPDATE_STATUS":sys.argv[17],
 "LAST_FAILED_UPDATE_AT":sys.argv[18],
 "LAST_FAILED_UPDATE_CASE":sys.argv[19],
}
fd,tmp=tempfile.mkstemp(prefix=".state.",suffix=".tmp",dir=dirp)
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(state,f,ensure_ascii=True,sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp,0o600)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
}

agy_load_state() {
    local k v
    agy_state_defaults
    if [ -f "$AGY_STATE_FILE" ]; then
        while IFS=$'\t' read -r k v; do
            [ -n "$k" ] || continue
            if ! agy_safe_state_kv "$k" "$v"; then
                continue
            fi
            case "$k" in
                PATCHED_FROM_ORIGINAL_SHA256) PATCHED_FROM_ORIGINAL_SHA256="$v" ;;
                PATCHED_SHA256) PATCHED_SHA256="$v" ;;
                LAST_RAW_SHA256) LAST_RAW_SHA256="$v" ;;
                NEEDS_REPATCH) NEEDS_REPATCH="$v" ;;
                LAST_REPAIR_AT) LAST_REPAIR_AT="$v" ;;
                LAST_SELF_UPDATE_AT) LAST_SELF_UPDATE_AT="$v" ;;
                VERIFIED_VERSION) VERIFIED_VERSION="$v" ;;
                VERIFIED_WRAPPER_VERSION) VERIFIED_WRAPPER_VERSION="$v" ;;
                VERIFIED_WRAPPER_COMMIT) VERIFIED_WRAPPER_COMMIT="$v" ;;
                VERIFIED_RAW_SHA256) VERIFIED_RAW_SHA256="$v" ;;
                VERIFIED_PATCHED_SHA256) VERIFIED_PATCHED_SHA256="$v" ;;
                VERIFIED_AT) VERIFIED_AT="$v" ;;
                VERIFIED_ENTRYPOINT) VERIFIED_ENTRYPOINT="$v" ;;
                LAST_SEEN_UPSTREAM_VERSION) LAST_SEEN_UPSTREAM_VERSION="$v" ;;
                LAST_FAILED_UPDATE_VERSION) LAST_FAILED_UPDATE_VERSION="$v" ;;
                LAST_FAILED_UPDATE_STATUS) LAST_FAILED_UPDATE_STATUS="$v" ;;
                LAST_FAILED_UPDATE_AT) LAST_FAILED_UPDATE_AT="$v" ;;
                LAST_FAILED_UPDATE_CASE) LAST_FAILED_UPDATE_CASE="$v" ;;
            esac
        done < <(agy_state_read_json "$AGY_STATE_FILE")
    fi
}

agy_write_state() {
    agy_state_write_json
}

agy_native_resolver_ok() {
    [ -r "$AGY_RESOLV_CONF" ] || return 1
    (
        exec 33<"$AGY_RESOLV_CONF"
        [ -r "/proc/self/fd/$AGY_RESOLVER_FD" ]
    )
}

agy_runtime_resolver_counts() {
    local target="${1:-$AGY_PATCHED}"
    [ -r "$target" ] || { printf 'missing missing\n'; return 1; }
    python3 - "$target" <<'PY'
from pathlib import Path
import sys
b = Path(sys.argv[1]).read_bytes()
print(b.count(b"/etc/resolv.conf"), b.count(b"/proc/self/fd/33"))
PY
}

agy_runtime_command() {
    local cert_dir_env=()
    local runtime_env=()
    local executable
    executable="$1"
    shift
    if [ -d "$AGY_CERT_DIR" ]; then
        cert_dir_env=("SSL_CERT_DIR=$AGY_CERT_DIR")
    fi
    runtime_env=(env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        HOME="$AGY_HOME" \
        XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$AGY_HOME/.config}" \
        XDG_CACHE_HOME="${XDG_CACHE_HOME:-$AGY_HOME/.cache}" \
        XDG_DATA_HOME="${XDG_DATA_HOME:-$AGY_HOME/.local/share}" \
        GODEBUG="${GODEBUG:-netdns=go}" \
        SSL_CERT_FILE="$AGY_CERT_FILE" \
        "${cert_dir_env[@]}")
    if ! agy_native_resolver_ok; then
        printf 'agy: resolver source is unavailable: %s\n' "$AGY_RESOLV_CONF" >&2
        return 66
    fi
    "${runtime_env[@]}" "$AGY_LOADER" --library-path "$AGY_GLIBC_LIB" "$executable" "$@" \
        33<"$AGY_RESOLV_CONF"
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

agy_build_runtime_candidate() {
    local raw_input="$1"
    local runtime_output="$2"
    local log_file="$3"

    if ! python3 "$AGY_RUNTIME_BUILDER" "$raw_input" --output "$runtime_output" >"$log_file" 2>&1; then
        return 70
    fi
    if command -v patchelf >/dev/null 2>&1; then
        if ! patchelf --set-interpreter "$AGY_LOADER" "$runtime_output" >>"$log_file" 2>&1; then
            return 71
        fi
    fi
    chmod 755 "$runtime_output"
    if ! agy_run_candidate "$runtime_output" --version >>"$log_file" 2>&1; then
        return 72
    fi
    return 0
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
        -e 's/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/[REDACTED_EMAIL]/g' \
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
    chmod 600 "$case_dir/raw.log" "$case_dir/safe.log"
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
        printf '%s\n' '- prefer agy doctor or agy setup as recovery commands'
        printf '%s\n' '- state whether automatic editing is safe'
    } >"$case_dir/install_prompt.txt"
    agy_redact_file "$case_dir/install_prompt.txt" "$case_dir/install_prompt.redacted"
    mv "$case_dir/install_prompt.redacted" "$case_dir/install_prompt.txt"
    chmod 600 "$case_dir/install_prompt.txt" "$case_dir/env.log"
    agy_diag_prune
    agy_set_last_case "$case_dir"
    printf '%s\n' "$case_dir"
}

agy_diag_prune() {
    [ -d "$AGY_DOCTOR_BASE" ] || return 0
    local keep="$AGY_DIAG_KEEP"
    local count=0 path
    while IFS= read -r path; do
        count=$((count + 1))
        if [ "$count" -gt "$keep" ]; then
            rm -rf "$path"
        fi
    done < <(ls -1dt "$AGY_DOCTOR_BASE"/* 2>/dev/null || true)
}

agy_wrapper_coherent() {
    [ -x "$AGY_PREFIX/bin/agy" ] || return 1
    agy_file_has_marker "$AGY_PREFIX/bin/agy" || return 1
    [ -x "$AGY_RUNTIME_DIR/managed.sh" ] || return 1
    [ -r "$AGY_RUNTIME_DIR/lib.sh" ] || return 1
    [ -x "$AGY_RUNTIME_BUILDER" ] || return 1
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
            if ! flock -w "$AGY_LOCK_WAIT_SECONDS" -x 9; then
                printf 'agy: another mutation operation is in progress (lock: %s).\n' "$AGY_LOCK_FILE" >&2
                return 99
            fi
            "$@"
        ) 9>"$AGY_LOCK_FILE"
    else
        local lock="$AGY_LOCK_FILE.d" waited=0
        while ! mkdir "$lock" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
            if [ "$waited" -ge "$AGY_LOCK_WAIT_SECONDS" ]; then
                printf 'agy: another mutation operation is in progress (lock: %s).\n' "$lock" >&2
                return 99
            fi
        done
        trap 'rmdir "$lock" 2>/dev/null || true' RETURN
        "$@"
    fi
}

agy_rebuild_runtime_unlocked() {
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
    tmp_dir=$(mktemp -d "$AGY_STATE_DIR/rebuild.XXXXXX") || return 1
    candidate="$tmp_dir/agy"

    local build_status
    set +e
    agy_build_runtime_candidate "$AGY_RAW" "$candidate" "$tmp_dir/build.log"
    build_status=$?
    set -e
    if [ "$build_status" -ne 0 ]; then
        agy_make_case "$build_status" "$tmp_dir/build.log" >/dev/null
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

agy_rebuild_runtime() {
    agy_with_lock agy_rebuild_runtime_unlocked "${1:-manual}"
}

agy_preflight() {
    if agy_needs_repatch; then
        printf 'agy: preparing runtime copy...\n' >&2
        agy_rebuild_runtime preflight
    fi
}

agy_cheap_launch_guard() {
    [ -x "$AGY_PATCHED" ] || { printf 'agy: patched runtime missing: %s\n' "$AGY_PATCHED" >&2; return 65; }
    [ -x "$AGY_LOADER" ] || { printf 'agy: loader missing: %s\n' "$AGY_LOADER" >&2; return 65; }
    [ -r "$AGY_RESOLV_CONF" ] || { printf 'agy: resolver source unreadable: %s\n' "$AGY_RESOLV_CONF" >&2; return 66; }
    return 0
}

agy_light_preflight() {
    agy_cheap_launch_guard || return $?
    agy_load_state
    if agy_needs_repatch; then
        printf 'agy: runtime drift detected; run "agy setup".\n' >&2
    fi
    return 0
}

agy_mode_for_args() {
    local first="${1:-}"
    case "$first" in
        "")
            printf 'bare\n'
            return 0
            ;;
        setup)
            printf 'setup\n'
            return 0
            ;;
        update)
            printf 'update\n'
            return 0
            ;;
        remove)
            printf 'remove\n'
            return 0
            ;;
        doctor)
            printf 'doctor\n'
            return 0
            ;;
        version)
            printf 'version\n'
            return 0
            ;;
        --help|-h|help)
            printf 'help\n'
            return 0
            ;;
        --print|-p|--prompt|--print-timeout)
            printf 'headless\n'
            return 0
            ;;
        --continue|--conversation|--prompt-interactive|--add-dir|--sandbox|--log-file|--dangerously-skip-permissions)
            printf 'automation\n'
            return 0
            ;;
        plugin|plugins|changelog)
            printf 'automation\n'
            return 0
            ;;
        *)
            printf 'normal\n'
            return 0
            ;;
    esac
}

agy_current_version() {
    agy_run_candidate "$AGY_PATCHED" --version 2>/dev/null | sed -n '1p'
}

agy_reload_wrapper_version() {
    unset AGY_WRAPPER_VERSION AGY_WRAPPER_CHANNEL AGY_WRAPPER_COMMIT AGY_WRAPPER_REPO AGY_WRAPPER_INSTALLED_AT
    if [ -f "$AGY_RUNTIME_DIR/wrapper-version.env" ]; then
        # shellcheck disable=SC1090
        . "$AGY_RUNTIME_DIR/wrapper-version.env"
    fi
}

agy_mark_runtime_success() {
    local version="${1:-}"
    [ -n "$version" ] || return 0
    agy_load_state
    agy_reload_wrapper_version
    VERIFIED_VERSION="$version"
    VERIFIED_WRAPPER_VERSION="${AGY_WRAPPER_VERSION:-unknown}"
    VERIFIED_WRAPPER_COMMIT="${AGY_WRAPPER_COMMIT:-unknown}"
    VERIFIED_RAW_SHA256="$(agy_sha256 "$AGY_RAW")"
    VERIFIED_PATCHED_SHA256="$(agy_sha256 "$AGY_PATCHED")"
    VERIFIED_AT="$(date -Is)"
    VERIFIED_ENTRYPOINT="agy"
    PATCHED_FROM_ORIGINAL_SHA256="$VERIFIED_RAW_SHA256"
    PATCHED_SHA256="$VERIFIED_PATCHED_SHA256"
    LAST_RAW_SHA256="$VERIFIED_RAW_SHA256"
    NEEDS_REPATCH=0
    LAST_SEEN_UPSTREAM_VERSION="$version"
    agy_write_state
}

agy_print_version_summary() {
    local upstream="${1:-}" wrapper_version
    agy_reload_wrapper_version
    wrapper_version="${AGY_WRAPPER_VERSION:-unknown}"
    printf '%-8s : %s\n' agy "${upstream:-unknown}"
    printf '%-8s : %s\n' wrapper "$wrapper_version"
}

agy_wrapper_help() {
    printf '\n'
    printf 'Wrapper commands\n'
    printf '  %-8s  %s\n' 'agy' 'Managed entrypoint; bare execution performs light preflight and may refresh the upstream binary.'
    printf '  %-8s  %s\n' 'setup' 'Refresh launcher/support files and ensure raw/runtime are ready.'
    printf '  %-8s  %s\n' 'update' 'Update the official upstream binary only.'
    printf '  %-8s  %s\n' 'doctor' 'Check PATH, launcher, runtime, resolver, CA, and state.'
    printf '  %-8s  %s\n' 'version' 'Print `agy :` and `wrapper :` version rows.'
    printf '  %-8s  %s\n' 'remove' 'Remove the managed launcher, runtime, raw copy, state, and obsolete shims.'
}

agy_version_report() {
    local upstream status
    set +e
    upstream="$(agy_runtime_command "$AGY_PATCHED" --version 2>/dev/null)"
    status=$?
    set -e
    upstream="$(printf '%s\n' "$upstream" | sed -n '1p')"
    [ "$status" -eq 0 ] || return "$status"
    agy_print_version_summary "$upstream"
}

agy_bootstrap_setup() {
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/agy-install.XXXXXX") || return 1
    trap 'rm -rf "${tmp_dir:-}"' EXIT INT TERM
    git clone --quiet --depth 1 --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$tmp_dir/repo" || return 1
    (cd "$tmp_dir/repo" && AGY_USE_CWD_SOURCE=1 bash ./install.sh)
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


agy_validate_tarball_safe() {
    local tar_path="$1"
    python3 - "$tar_path" <<'PY'
import os,sys,tarfile,pathlib

tar_path=sys.argv[1]
reject_types={"chr","blk","fifo","dev"}
with tarfile.open(tar_path,"r:gz") as tf:
    for m in tf.getmembers():
        n=m.name
        p=pathlib.PurePosixPath(n)
        if not n or n.startswith("/") or p.is_absolute():
            raise SystemExit(f"unsafe tar entry path: {n}")
        if ".." in p.parts:
            raise SystemExit(f"unsafe tar traversal: {n}")
        if m.issym():
            raise SystemExit(f"unsafe tar symlink entry: {n}")
        if m.islnk():
            raise SystemExit(f"unsafe tar hardlink entry: {n}")
        if m.ischr() or m.isblk() or m.isfifo() or m.isdev():
            raise SystemExit(f"unsafe tar special entry: {n}")
print("ok")
PY
}

agy_record_update_failure() {
    local version="$1"
    local status="$2"
    local case_path="${3:-}"
    agy_load_state
    LAST_FAILED_UPDATE_VERSION="$version"
    LAST_FAILED_UPDATE_STATUS="$status"
    LAST_FAILED_UPDATE_AT="$(date -Is)"
    LAST_FAILED_UPDATE_CASE="$case_path"
    agy_write_state
}

agy_clear_update_failure() {
    agy_load_state
    LAST_FAILED_UPDATE_VERSION=""
    LAST_FAILED_UPDATE_STATUS=""
    LAST_FAILED_UPDATE_AT=""
    LAST_FAILED_UPDATE_CASE=""
    agy_write_state
}

agy_set_seen_upstream() {
    local version="$1"
    agy_load_state
    LAST_SEEN_UPSTREAM_VERSION="$version"
    agy_write_state
}

agy_update_broker_once() {
    local manifest_url="$1"
    local source_label="$2"
    local network_mode="${3:-auto}"
    local display_mode="${4:-$network_mode}"
    local before current latest tmp_dir manifest status

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
    if [ "$network_mode" = "auto" ]; then
        curl -fsSL --connect-timeout "$AGY_AUTO_UPDATE_TIMEOUT" --max-time "$AGY_AUTO_UPDATE_TIMEOUT" "$manifest_url" >"$manifest" 2>"$tmp_dir/update.log"
    else
        curl -fsSL "$manifest_url" >"$manifest" 2>"$tmp_dir/update.log"
    fi
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
        agy_set_seen_upstream "$latest"
        agy_load_state
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
    agy_set_seen_upstream "$latest"
    agy_load_state
    if [ "$display_mode" = "run" ] && [ "${LAST_FAILED_UPDATE_VERSION:-}" = "$latest" ]; then
        printf 'agy: update %s is available but not yet verified for Termux.\n' "$latest" >&2
        if [ -n "${VERIFIED_VERSION:-$current}" ]; then
            printf 'agy: running verified version %s.\n' "${VERIFIED_VERSION:-$current}" >&2
        fi
        printf 'agy: run "agy update" to retry the update.\n' >&2
        rm -rf "$tmp_dir"
        return 0
    fi

    local url expected_sha actual_sha extracted candidate_raw candidate_runtime raw_backup runtime_backup case_dir build_status
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
    if [ "$network_mode" = "auto" ]; then
        curl -fsSL --connect-timeout "$AGY_AUTO_UPDATE_TIMEOUT" --max-time "$AGY_AUTO_UPDATE_TIMEOUT" "$url" >"$tmp_dir/agy.tgz" 2>"$tmp_dir/update.log"
    else
        curl -fsSL "$url" >"$tmp_dir/agy.tgz" 2>"$tmp_dir/update.log"
    fi
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        case_dir=$(agy_make_case "$status" "$tmp_dir/update.log")
        agy_record_update_failure "$latest" "download_failed" "$case_dir"
        rm -rf "$tmp_dir"
        return "$status"
    fi

    actual_sha=$(sha512sum "$tmp_dir/agy.tgz" | awk '{print $1}')
    if [ "$actual_sha" != "$expected_sha" ]; then
        printf 'sha512 mismatch\nexpected=%s\nactual=%s\n' "$expected_sha" "$actual_sha" >"$tmp_dir/update.log"
        case_dir=$(agy_make_case 75 "$tmp_dir/update.log")
        agy_record_update_failure "$latest" "sha512_failed" "$case_dir"
        rm -rf "$tmp_dir"
        return 75
    fi

    mkdir -p "$tmp_dir/extract"
    set +e
    agy_validate_tarball_safe "$tmp_dir/agy.tgz" >>"$tmp_dir/update.log" 2>&1
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        case_dir=$(agy_make_case "$status" "$tmp_dir/update.log")
        agy_record_update_failure "$latest" "tar_safety_failed" "$case_dir"
        rm -rf "$tmp_dir"
        return 78
    fi
    set +e
    tar -xzf "$tmp_dir/agy.tgz" -C "$tmp_dir/extract" >>"$tmp_dir/update.log" 2>&1
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        case_dir=$(agy_make_case "$status" "$tmp_dir/update.log")
        agy_record_update_failure "$latest" "extract_failed" "$case_dir"
        rm -rf "$tmp_dir"
        return "$status"
    fi

    extracted="$tmp_dir/extract/antigravity"
    if [ ! -s "$extracted" ]; then
        printf 'expected extracted antigravity binary not found\n' >"$tmp_dir/update.log"
        case_dir=$(agy_make_case 76 "$tmp_dir/update.log")
        agy_record_update_failure "$latest" "extract_missing_binary" "$case_dir"
        rm -rf "$tmp_dir"
        return 76
    fi

    candidate_raw="$tmp_dir/agy.raw"
    candidate_runtime="$tmp_dir/agy.runtime"
    mv "$extracted" "$candidate_raw"
    chmod 755 "$candidate_raw"
    set +e
    agy_build_runtime_candidate "$candidate_raw" "$candidate_runtime" "$tmp_dir/build.log"
    build_status=$?
    set -e
    if [ "$build_status" -ne 0 ]; then
        case_dir=$(agy_make_case "$build_status" "$tmp_dir/build.log")
        agy_record_update_failure "$latest" "validation_failed" "$case_dir"
        if [ "$display_mode" != "quiet" ]; then
            printf 'agy: update %s could not be prepared for Termux.\n' "$latest" >&2
            if [ -n "${VERIFIED_VERSION:-$current}" ]; then
                printf 'agy: keeping verified version %s.\n' "${VERIFIED_VERSION:-$current}" >&2
            fi
        fi
        rm -rf "$tmp_dir"
        return 77
    fi

    raw_backup="$AGY_STATE_DIR/agy.raw.$(date +%Y%m%d-%H%M%S).bak"
    runtime_backup="$AGY_STATE_DIR/agy.runtime.$(date +%Y%m%d-%H%M%S).bak"
    mkdir -p "$(dirname "$AGY_RAW")"
    mkdir -p "$(dirname "$AGY_PATCHED")"
    if [ -e "$AGY_RAW" ]; then
        cp -p "$AGY_RAW" "$raw_backup"
    fi
    if [ -e "$AGY_PATCHED" ]; then
        cp -p "$AGY_PATCHED" "$runtime_backup"
    fi
    mv "$candidate_raw" "$AGY_RAW"
    mv "$candidate_runtime" "$AGY_PATCHED"
    chmod 755 "$AGY_RAW"
    chmod 755 "$AGY_PATCHED"
    if [ "$display_mode" != "quiet" ]; then
        printf 'agy: update %s is ready.\n' "$latest" >&2
    fi
    PATCHED_FROM_ORIGINAL_SHA256="$(agy_sha256 "$AGY_RAW")"
    PATCHED_SHA256="$(agy_sha256 "$AGY_PATCHED")"
    LAST_RAW_SHA256="$PATCHED_FROM_ORIGINAL_SHA256"
    NEEDS_REPATCH=0
    LAST_REPAIR_AT="$(date -Is)"
    LAST_SELF_UPDATE_AT="${LAST_SELF_UPDATE_AT:-}"
    LAST_SEEN_UPSTREAM_VERSION="$latest"
    LAST_FAILED_UPDATE_VERSION=""
    LAST_FAILED_UPDATE_STATUS=""
    LAST_FAILED_UPDATE_AT=""
    LAST_FAILED_UPDATE_CASE=""
    agy_write_state
    rm -rf "$tmp_dir"
}

agy_update_broker() {
    local mode="${1:-auto}" status
    local display_mode="${2:-$mode}"

    if agy_with_lock agy_update_broker_once "$AGY_MANIFEST_URL" "current" "$mode" "$display_mode"; then
        return 0
    fi
    status=$?

    if [ "$mode" != "explicit" ]; then
        agy_load_state
        if [ -n "${LAST_FAILED_UPDATE_VERSION:-}" ]; then
            printf 'agy: update %s could not be prepared for Termux.\n' "$LAST_FAILED_UPDATE_VERSION" >&2
            if [ -n "${VERIFIED_VERSION:-}" ]; then
                printf 'agy: keeping verified version %s.\n' "$VERIFIED_VERSION" >&2
            fi
            printf 'agy: run "agy update" to retry the update.\n' >&2
        else
            printf 'agy: update check failed; continuing with current runtime copy.\n' >&2
        fi
        return 0
    fi

    if [ "$mode" = "explicit" ]; then
        printf 'agy: update failed; keeping the currently installed runtime.\n' >&2
    fi
    return "$status"
}

agy_auto_update() {
    [ "${AGY_SKIP_AUTO_UPDATE:-0}" = "1" ] && return 0
    [ "${1:-}" = "auth" ] && return 0
    [ "${1:-}" = "--version" ] && return 0
    [ "${1:-}" = "version" ] && return 0
    agy_update_broker auto run
}

agy_remove_tree() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        rm -rf "$path"
        printf 'removed %s\n' "$path"
    fi
}

agy_remove_file_or_link() {
    local path="$1" label="${2:-path}"
    if [ -L "$path" ] || [ -f "$path" ]; then
        rm -f "$path"
        printf 'removed %s\n' "$path"
    elif [ -d "$path" ]; then
        printf 'skipped %s directory %s\n' "$label" "$path"
    fi
}

agy_remove_managed_launcher() {
    local path="$1"
    if [ -L "$path" ] || [ -f "$path" ]; then
        if agy_file_has_marker "$path"; then
            rm -f "$path"
            printf 'removed %s\n' "$path"
        else
            printf 'skipped unmanaged launcher %s\n' "$path"
        fi
    elif [ -d "$path" ]; then
        printf 'skipped launcher directory %s\n' "$path"
    fi
}

agy_remove_rc_path_block() {
    local rc="$1" marker_begin marker_end
    marker_begin="# >>> agy native path >>>"
    marker_end="# <<< agy native path <<<"
    [ -f "$rc" ] || return 0
    grep -Fq "$marker_begin" "$rc" 2>/dev/null || return 0
    python3 - "$rc" "$marker_begin" "$marker_end" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
marker_begin = sys.argv[2]
marker_end = sys.argv[3]
lines = path.read_text().splitlines(keepends=True)
out = []
skip = False
changed = False
for line in lines:
    if marker_begin in line:
        skip = True
        changed = True
        continue
    if skip:
        if marker_end in line:
            skip = False
        continue
    out.append(line)
if changed:
    path.write_text("".join(out))
PY
    printf 'removed PATH block from %s\n' "$rc"
}

agy_remove_obsolete_control_shims() {
    local path
    for path in \
        "$AGY_HOME/.local/bin/agy" \
        "$AGY_HOME/bin/agy" \
        "$AGY_HOME/.local/bin/agy-t" \
        "$AGY_HOME/bin/agy-t" \
        "$AGY_HOME/bin/agy-termux" \
        "$AGY_PREFIX/bin/agy-t" \
        "$AGY_PREFIX/bin/agy-termux"; do
        agy_remove_file_or_link "$path" "obsolete shim"
    done
}

agy_remove_run() {
    printf 'agy remove: removing managed Termux runtime files...\n' >&2
    agy_remove_managed_launcher "$AGY_PREFIX/bin/agy"
    agy_remove_obsolete_control_shims
    agy_remove_tree "$AGY_NATIVE_ROOT"
    agy_remove_tree "$AGY_STATE_DIR"
    agy_remove_tree "$AGY_HOME/.local/glibc-shim"
    agy_remove_rc_path_block "$AGY_HOME/.profile"
    agy_remove_rc_path_block "$AGY_HOME/.bashrc"
    agy_remove_rc_path_block "$AGY_HOME/.zshrc"
    printf 'agy remove: completed. OAuth/user Antigravity config outside the managed runtime was not removed.\n' >&2
}

agy_remove() {
    local answer
    if [ "$#" -ne 0 ]; then
        printf 'agy remove: unexpected argument: %s\n' "$1" >&2
        printf 'usage: agy remove\n' >&2
        return 2
    fi
    if [ ! -t 0 ]; then
        printf 'agy remove: refusing to remove in a non-interactive shell.\n' >&2
        return 2
    fi
    printf 'Remove agy managed launcher, runtime, raw binary, state, and obsolete shims? [y/N] ' >&2
    read -r answer || answer=""
    case "$answer" in
        y|Y|yes|YES) ;;
        *) printf 'agy remove: cancelled.\n' >&2; return 1 ;;
    esac
    agy_remove_run
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

agy_doctor() {
    agy_load_state
    local failures=0 warnings=0 active patched_version interp
    local current_raw_hash current_patched_hash current_wrapper_version current_wrapper_commit

    agy_doctor_ok() { printf 'ok    %s\n' "$*"; }
    agy_doctor_warn() { warnings=$((warnings + 1)); printf 'warn  %s\n' "$*"; }
    agy_doctor_fail() { failures=$((failures + 1)); printf 'fail  %s\n' "$*"; }

    printf 'agy doctor\n'
    active="$(command -v agy 2>/dev/null || true)"
    case "$active" in
        "$AGY_PREFIX/bin/agy")
            agy_doctor_ok "PATH resolves agy to managed entrypoint: $active"
            ;;
        "")
            agy_doctor_fail 'agy is not on PATH'
            ;;
        *)
            agy_doctor_fail "PATH resolves agy to unexpected path: $active"
            ;;
    esac

    [ -x "$AGY_PREFIX/bin/agy" ] && agy_doctor_ok "launcher exists: $AGY_PREFIX/bin/agy" || agy_doctor_fail "launcher missing or not executable: $AGY_PREFIX/bin/agy"
    [ -r "$AGY_RUNTIME_DIR/lib.sh" ] && agy_doctor_ok "runtime library installed: $AGY_RUNTIME_DIR/lib.sh" || agy_doctor_fail "runtime library missing: $AGY_RUNTIME_DIR/lib.sh"
    [ -x "$AGY_RUNTIME_BUILDER" ] && agy_doctor_ok "runtime builder installed: $AGY_RUNTIME_BUILDER" || agy_doctor_fail "runtime builder missing: $AGY_RUNTIME_BUILDER"
    [ -r "$AGY_RUNTIME_DIR/wrapper-version.env" ] && agy_doctor_ok "wrapper metadata installed: $AGY_RUNTIME_DIR/wrapper-version.env" || agy_doctor_warn "wrapper metadata missing: $AGY_RUNTIME_DIR/wrapper-version.env"

    [ -x "$AGY_RAW" ] && agy_doctor_ok "raw upstream binary exists: $AGY_RAW" || agy_doctor_fail "raw upstream binary missing: $AGY_RAW"
    [ -x "$AGY_PATCHED" ] && agy_doctor_ok "patched runtime exists: $AGY_PATCHED" || agy_doctor_fail "patched runtime missing: $AGY_PATCHED"
    [ -x "$AGY_LOADER" ] && agy_doctor_ok "glibc loader exists: $AGY_LOADER" || agy_doctor_fail "glibc loader missing: $AGY_LOADER"
    [ -d "$AGY_GLIBC_LIB" ] && agy_doctor_ok "glibc library dir exists: $AGY_GLIBC_LIB" || agy_doctor_fail "glibc library dir missing: $AGY_GLIBC_LIB"
    [ -f "$AGY_CERT_FILE" ] && agy_doctor_ok "CA bundle exists: $AGY_CERT_FILE" || agy_doctor_fail "CA bundle missing: $AGY_CERT_FILE"
    [ -r "$AGY_RESOLV_CONF" ] && agy_doctor_ok "resolver source readable: $AGY_RESOLV_CONF" || agy_doctor_fail "resolver source unreadable: $AGY_RESOLV_CONF"

    if agy_native_resolver_ok; then
        agy_doctor_ok "resolver fd $AGY_RESOLVER_FD can be opened"
    else
        agy_doctor_fail "resolver fd $AGY_RESOLVER_FD cannot be opened from $AGY_RESOLV_CONF"
    fi

    if ! resolver_counts="$(agy_runtime_resolver_counts "$AGY_PATCHED" 2>/dev/null)"; then
        resolver_counts='missing missing'
    fi
    etc_count="$(printf '%s' "$resolver_counts" | awk '{print $1}')"
    fd33_count="$(printf '%s' "$resolver_counts" | awk '{print $2}')"
    if [ "$etc_count" = "0" ] && [ "$fd33_count" != "0" ] && [ "$fd33_count" != "missing" ]; then
        agy_doctor_ok "runtime resolver rewrite present (/etc=$etc_count fd33=$fd33_count)"
    else
        agy_doctor_fail "runtime resolver rewrite unexpected (/etc=$etc_count fd33=$fd33_count)"
    fi

    if command -v patchelf >/dev/null 2>&1 && [ -x "$AGY_PATCHED" ]; then
        interp="$(patchelf --print-interpreter "$AGY_PATCHED" 2>/dev/null || true)"
        [ "$interp" = "$AGY_LOADER" ] && agy_doctor_ok "runtime interpreter matches loader" || agy_doctor_fail "runtime interpreter mismatch: ${interp:-unknown}"
    else
        agy_doctor_warn 'patchelf unavailable or runtime missing; skipped interpreter check'
    fi

    if [ -x "$AGY_PATCHED" ] && [ -x "$AGY_LOADER" ] && [ -r "$AGY_RESOLV_CONF" ]; then
        patched_version="$(AGY_SKIP_AUTO_UPDATE=1 agy_run_candidate "$AGY_PATCHED" --version 2>/dev/null || true)"
        [ -n "$patched_version" ] && agy_doctor_ok "patched runtime starts: $patched_version" || agy_doctor_fail 'patched runtime --version failed'
    fi

    if agy_needs_repatch; then
        agy_doctor_warn 'state/runtime drift detected; run agy setup'
    else
        agy_doctor_ok 'state matches current raw/runtime hashes'
    fi

    if [ -n "${VERIFIED_AT:-}" ]; then
        agy_reload_wrapper_version
        current_raw_hash="$(agy_sha256 "$AGY_RAW")"
        current_patched_hash="$(agy_sha256 "$AGY_PATCHED")"
        current_wrapper_version="${AGY_WRAPPER_VERSION:-unknown}"
        current_wrapper_commit="${AGY_WRAPPER_COMMIT:-unknown}"
        if [ "${VERIFIED_ENTRYPOINT:-}" = "agy" ] \
            && [ "${VERIFIED_RAW_SHA256:-}" = "$current_raw_hash" ] \
            && [ "${VERIFIED_PATCHED_SHA256:-}" = "$current_patched_hash" ] \
            && [ "${VERIFIED_WRAPPER_VERSION:-}" = "$current_wrapper_version" ] \
            && [ "${VERIFIED_WRAPPER_COMMIT:-}" = "$current_wrapper_commit" ]; then
            agy_doctor_ok "last successful agy runtime tuple matches current files: $VERIFIED_AT"
        else
            agy_doctor_warn 'last successful agy runtime tuple differs from current files'
        fi
    else
        agy_doctor_ok 'last successful agy runtime tuple not recorded yet'
    fi

    [ -f "$AGY_STATE_FILE" ] && agy_doctor_ok "state file exists: $AGY_STATE_FILE" || agy_doctor_warn "state file missing: $AGY_STATE_FILE"
    printf 'summary: %s failure(s), %s warning(s)\n' "$failures" "$warnings"
    [ "$failures" -eq 0 ]
}

agy_main() {
    local first="${1:-}"
    local mode
    local before after temp_raw exit_code case_dir

    mode="$(agy_mode_for_args "$first")"

    case "$mode" in
        setup)
            shift || true
            agy_bootstrap_setup
            return $?
            ;;
        update)
            agy_preflight || return $?
            agy_update_broker explicit || return $?
            agy_version_report
            return $?
            ;;
        remove)
            shift || true
            agy_remove "$@"
            return $?
            ;;
        doctor)
            shift || true
            agy_doctor
            return $?
            ;;
        version)
            shift || true
            agy_cheap_launch_guard || return $?
            agy_version_report
            return $?
            ;;
        help)
            shift || true
            agy_cheap_launch_guard || return $?
            agy_runtime_command "$AGY_PATCHED" --help "$@"
            status=$?
            agy_wrapper_help
            return "$status"
            ;;
    esac

    if [ "$mode" = "bare" ]; then
        agy_light_preflight || return $?
        agy_auto_update "$first" || return $?
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
            printf 'agy: raw changed during execution; rebuilding runtime copy.\n' >&2
            agy_rebuild_runtime postflight-update
        fi
        if [ "$exit_code" -eq 0 ]; then
            agy_mark_runtime_success "$(agy_current_version 2>/dev/null || true)"
        fi
        if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 130 ]; then
            case_dir=$(agy_make_case "$exit_code" "$temp_raw")
            printf 'agy failed with status %s.\n' "$exit_code" >&2
            printf 'Termux diagnostic case created:\n  %s\n' "$case_dir" >&2
            printf 'Next:\n  agy doctor\n' >&2
        fi
        rm -f "$temp_raw"
        return "$exit_code"
    fi

    agy_cheap_launch_guard || return $?
    set +e
    agy_load_state
    agy_runtime_command "$AGY_PATCHED" "$@"
    exit_code=$?
    set -e
    return "$exit_code"
}
