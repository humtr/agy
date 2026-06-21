#!/usr/bin/env bash
set -u

AGY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_PROJECT_ROOT="${AGY_PROJECT_ROOT:-$(cd "$AGY_LIB_DIR/.." && pwd)}"
AGY_HOME="${AGY_HOME:-$HOME}"
AGY_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
AGY_TERMUX_ROOT="${AGY_TERMUX_ROOT:-$AGY_HOME/.local/lib/agy/termux}"
AGY_RAW="${AGY_RAW:-$AGY_TERMUX_ROOT/raw/agy}"
AGY_RUNTIME_DIR="${AGY_RUNTIME_DIR:-$AGY_TERMUX_ROOT/runtime}"
AGY_PATCHED="${AGY_PATCHED:-$AGY_RUNTIME_DIR/agy}"
AGY_MANAGED_SHELL="${AGY_MANAGED_SHELL:-$AGY_RUNTIME_DIR/managed.sh}"
AGY_STATE_DIR="${AGY_STATE_DIR:-$AGY_HOME/.local/share/agy/termux}"
AGY_STATE_FILE="${AGY_STATE_FILE:-$AGY_STATE_DIR/state.json}"
AGY_REGISTRY_FILE="${AGY_REGISTRY_FILE:-$AGY_STATE_DIR/registry.json}"
AGY_STORE_DIR="${AGY_STORE_DIR:-$AGY_STATE_DIR/store}"
AGY_DOCTOR_BASE="${AGY_DOCTOR_BASE:-$AGY_STATE_DIR/doctor}"
AGY_LOCK_FILE="${AGY_LOCK_FILE:-$AGY_STATE_DIR/termux.lock}"
AGY_LOCK_WAIT_SECONDS="${AGY_LOCK_WAIT_SECONDS:-30}"
AGY_DIAG_KEEP="${AGY_DIAG_KEEP:-20}"
AGY_STORE_KEEP_RAW="${AGY_STORE_KEEP_RAW:-5}"
AGY_STORE_KEEP_WRAPPER="${AGY_STORE_KEEP_WRAPPER:-5}"
AGY_STORE_KEEP_RUNTIME="${AGY_STORE_KEEP_RUNTIME:-8}"
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
AGY_MANAGED_LAUNCHER_MARKER="${AGY_MANAGED_LAUNCHER_MARKER:-agy termux managed launcher}"
AGY_MANIFEST_URL="${AGY_MANIFEST_URL:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json}"
AGY_UPSTREAM_UPDATE_DISABLED_BASE_URL="${AGY_UPSTREAM_UPDATE_DISABLED_BASE_URL:-http://127.0.0.1:9/disabled}"
AGY_AUTO_UPDATE_TIMEOUT="${AGY_AUTO_UPDATE_TIMEOUT:-4}"
AGY_REMOTE_CANDIDATE_LIMIT="${AGY_REMOTE_CANDIDATE_LIMIT:-10}"
AGY_PROFILE_ROOT="${AGY_PROFILE_ROOT:-$HOME/.agy-profiles}"
AGY_PROFILE_HOME="${AGY_PROFILE_HOME:-}"

# ANSI Color & Formatting Variables
agy_init_terminal_colors() {
    if [ -t 1 ] || [ -t 2 ]; then
        T_RESET=$'\e[0m'
        T_BOLD=$'\e[1m'
        T_DIM=$'\e[2m'
        T_UNDERLINE=$'\e[4m'
        
        T_RED=$'\e[31m'
        T_GREEN=$'\e[32m'
        T_YELLOW=$'\e[33m'
        T_BLUE=$'\e[34m'
        T_MAGENTA=$'\e[35m'
        T_CYAN=$'\e[36m'
        T_WHITE=$'\e[37m'
        T_GRAY=$'\e[90m'
        
        C_HEADER="${T_BOLD}${T_CYAN}"
        C_TITLE="${T_BOLD}${T_WHITE}"
        C_MUTED="${T_DIM}${T_GRAY}"
        C_NUMBER="${T_BOLD}${T_MAGENTA}"
        C_LABEL="${T_WHITE}"
        C_BORDER="${T_CYAN}"
        C_PROMPT="${T_BOLD}${T_BLUE}"
        
        # Tags / Badges
        C_TAG_PREFERRED="${T_BOLD}${T_GREEN}"
        C_TAG_VERIFIED="${T_BOLD}${T_CYAN}"
        C_TAG_SMOKE="${T_YELLOW}"
        C_TAG_CACHED="${T_GRAY}"
        C_TAG_BUILD="${T_MAGENTA}"
        C_TAG_REMOTE="${T_BLUE}"
    else
        T_RESET=""
        T_BOLD=""
        T_DIM=""
        T_UNDERLINE=""
        
        T_RED=""
        T_GREEN=""
        T_YELLOW=""
        T_BLUE=""
        T_MAGENTA=""
        T_CYAN=""
        T_WHITE=""
        T_GRAY=""
        
        C_HEADER=""
        C_TITLE=""
        C_MUTED=""
        C_NUMBER=""
        C_LABEL=""
        C_BORDER=""
        C_PROMPT=""
        
        C_TAG_PREFERRED=""
        C_TAG_VERIFIED=""
        C_TAG_SMOKE=""
        C_TAG_CACHED=""
        C_TAG_BUILD=""
        C_TAG_REMOTE=""
    fi
}
# Initialize colors immediately
agy_init_terminal_colors

# Beautiful Box Header
agy_print_header() {
    local title="$1"
    local subtitle="${2:-}"
    local width=52
    
    printf '  %s╭%s╮%s\n' "${C_BORDER}" "$(printf '─%.0s' $(seq 1 $width))" "${T_RESET}" >&2
    
    # Calculate title padding
    local title_len=${#title}
    local title_pad_right=$((width - title_len - 3))
    if [ $title_pad_right -lt 0 ]; then title_pad_right=0; fi
    printf '  %s│  %s%s%s%s│%s\n' "${C_BORDER}" "${C_HEADER}" "${title}" "${T_RESET}" "$(printf ' %.0s' $(seq 1 $title_pad_right))" "${C_BORDER}${T_RESET}" >&2
    
    if [ -n "$subtitle" ]; then
        local sub_len=${#subtitle}
        local sub_pad_right=$((width - sub_len - 3))
        if [ $sub_pad_right -lt 0 ]; then sub_pad_right=0; fi
        printf '  %s│  %s%s%s%s│%s\n' "${C_BORDER}" "${C_MUTED}" "${subtitle}" "${T_RESET}" "$(printf ' %.0s' $(seq 1 $sub_pad_right))" "${C_BORDER}${T_RESET}" >&2
    fi
    
    printf '  %s╰%s╯%s\n' "${C_BORDER}" "$(printf '─%.0s' $(seq 1 $width))" "${T_RESET}" >&2
}

# Beautiful tag formatter
agy_format_flags() {
    local raw_flags="$1"
    local formatted=""
    
    if [ -z "$T_RESET" ]; then
        printf ' [%s]' "${raw_flags//,/] [}"
        return 0
    fi
    
    local IFS=',' flag
    for flag in $raw_flags; do
        case "$flag" in
            preferred)
                formatted="${formatted} ${C_TAG_PREFERRED}🟢 preferred${T_RESET}"
                ;;
            verified)
                formatted="${formatted} ${C_TAG_VERIFIED}✅ verified${T_RESET}"
                ;;
            smoke)
                formatted="${formatted} ${C_TAG_SMOKE}⚡ tested${T_RESET}"
                ;;
            cached)
                formatted="${formatted} ${C_TAG_CACHED}📦 cached${T_RESET}"
                ;;
            build)
                formatted="${formatted} ${C_TAG_BUILD}🛠️ build${T_RESET}"
                ;;
            remote)
                formatted="${formatted} ${C_TAG_REMOTE}🌐 remote${T_RESET}"
                ;;
            *)
                formatted="${formatted} ${T_DIM}[${flag}]${T_RESET}"
                ;;
        esac
    done
    printf '%s' "$formatted"
}

agy_registry_default_json() {
    printf '{"schema":1,"raw":{},"runtime":{},"wrapper":{}}\n'
}

agy_registry_ensure() {
    mkdir -p "$AGY_STATE_DIR"
    [ -f "$AGY_REGISTRY_FILE" ] || agy_registry_default_json >"$AGY_REGISTRY_FILE"
}

agy_registry_py() {
    local mode="$1"
    shift
    python3 - "$AGY_REGISTRY_FILE" "$mode" "$@" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]
args = sys.argv[3:]

def default():
    return {"schema": 1, "raw": {}, "runtime": {}, "wrapper": {}}

if path.exists():
    try:
        data = json.loads(path.read_text())
    except Exception:
        data = default()
else:
    data = default()

data.setdefault("schema", 1)
data.setdefault("raw", {})
data.setdefault("runtime", {})
data.setdefault("wrapper", {})

def write():
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=True, sort_keys=True) + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)

if mode == "dump":
    print(json.dumps(data, ensure_ascii=True, sort_keys=True))
elif mode == "list-raw":
    for key in sorted(data["raw"], key=lambda k: (data["raw"][k].get("added_at", ""), k), reverse=True):
        entry = data["raw"][key]
        print("\t".join([
            key,
            str(entry.get("version", "")),
            str(entry.get("sha256", "")),
            str(entry.get("sha512", "")),
            str(entry.get("path", "")),
            str(entry.get("url", "")),
            str(entry.get("source", "")),
            str(entry.get("added_at", "")),
        ]))
elif mode == "list-wrapper":
    for key in sorted(data["wrapper"], key=lambda k: (data["wrapper"][k].get("added_at", ""), k), reverse=True):
        entry = data["wrapper"][key]
        print("\t".join([
            key,
            str(entry.get("version", "")),
            str(entry.get("commit", "")),
            str(entry.get("path", "")),
            str(entry.get("added_at", "")),
        ]))
elif mode == "list-runtime":
    for key in sorted(data["runtime"], key=lambda k: (data["runtime"][k].get("verified_at", data["runtime"][k].get("smoke_tested_at", "")), k), reverse=True):
        entry = data["runtime"][key]
        print("\t".join([
            key,
            str(entry.get("raw_id", "")),
            str(entry.get("wrapper_id", "")),
            str(entry.get("path", "")),
            str(entry.get("patched_sha256", "")),
            str(entry.get("smoke_tested_at", "")),
            str(entry.get("verified_at", "")),
        ]))
elif mode == "has-runtime":
    print("1" if args and args[0] in data["runtime"] else "0")
elif mode == "add-raw":
    raw_id, version, sha256, sha512, raw_path, url, source, added_at = args[:8]
    data["raw"][raw_id] = {
        "version": version,
        "sha256": sha256,
        "sha512": sha512,
        "path": raw_path,
        "url": url,
        "source": source,
        "added_at": added_at,
    }
    write()
elif mode == "add-wrapper":
    wrapper_id, version, commit, wrapper_path, added_at = args[:5]
    data["wrapper"][wrapper_id] = {
        "version": version,
        "commit": commit,
        "path": wrapper_path,
        "added_at": added_at,
    }
    write()
elif mode == "add-runtime":
    tuple_id, raw_id, wrapper_id, runtime_path, patched_sha256, smoke_tested_at, verified_at = args[:7]
    data["runtime"][tuple_id] = {
        "raw_id": raw_id,
        "wrapper_id": wrapper_id,
        "path": runtime_path,
        "patched_sha256": patched_sha256,
        "smoke_tested_at": smoke_tested_at,
        "verified_at": verified_at,
    }
    write()
elif mode == "delete-raw":
    if args and args[0] in data["raw"]:
        del data["raw"][args[0]]
        write()
elif mode == "delete-wrapper":
    if args and args[0] in data["wrapper"]:
        del data["wrapper"][args[0]]
        write()
elif mode == "delete-runtime":
    if args and args[0] in data["runtime"]:
        del data["runtime"][args[0]]
        write()
else:
    raise SystemExit(f"unknown registry mode: {mode}")
PY
}

agy_registry_raw_dir() {
    printf '%s/raw\n' "$AGY_STORE_DIR"
}

agy_registry_wrapper_dir() {
    printf '%s/wrapper\n' "$AGY_STORE_DIR"
}

agy_registry_runtime_dir() {
    printf '%s/runtime\n' "$AGY_STORE_DIR"
}

agy_raw_id() {
    printf 'agy-%s+%s\n' "$1" "${2:-unknown}"
}

agy_wrapper_id() {
    printf 'wrapper-%s+%s\n' "$1" "${2:-unknown}"
}

agy_tuple_id() {
    printf '%s__%s\n' "$1" "$2"
}

agy_store_path_safe() {
    case "$1" in
        *[!A-Za-z0-9._+-]*|'') return 1 ;;
    esac
    return 0
}

agy_store_raw_path() {
    local raw_id="$1"
    printf '%s/raw/%s/agy\n' "$AGY_STORE_DIR" "$raw_id"
}

agy_store_wrapper_path() {
    local wrapper_id="$1"
    printf '%s/wrapper/%s\n' "$AGY_STORE_DIR" "$wrapper_id"
}

agy_store_runtime_path() {
    local tuple_id="$1"
    printf '%s/runtime/%s/agy\n' "$AGY_STORE_DIR" "$tuple_id"
}

agy_current_wrapper_version() {
    agy_reload_wrapper_version
    printf '%s\n' "${AGY_WRAPPER_VERSION:-unknown}"
}

agy_current_wrapper_commit() {
    agy_reload_wrapper_version
    printf '%s\n' "${AGY_WRAPPER_COMMIT:-unknown}"
}

agy_current_wrapper_id() {
    agy_wrapper_id "$(agy_current_wrapper_version)" "$(agy_current_wrapper_commit)"
}

agy_current_tuple_id() {
    local raw_id wrapper_id
    raw_id="${1:-}"
    wrapper_id="${2:-$(agy_current_wrapper_id)}"
    [ -n "$raw_id" ] || return 1
    agy_tuple_id "$raw_id" "$wrapper_id"
}

agy_store_copy_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
}

agy_store_record_raw() {
    local raw_id="$1" version="$2" sha256="$3" sha512="$4" url="$5" source="$6" added_at="$7"
    local dst
    dst="$(agy_store_raw_path "$raw_id")"
    mkdir -p "$(dirname "$dst")"
    cp -p "$AGY_RAW" "$dst"
    chmod 755 "$dst"
    agy_registry_py add-raw "$raw_id" "$version" "$sha256" "$sha512" "$dst" "$url" "$source" "$added_at"
}

agy_store_record_raw_file() {
    local src="$1" version="$2" sha256="$3" sha512="$4" url="$5" source="$6" added_at="$7"
    local raw_id dst
    raw_id="$(agy_raw_id "$version" "${sha256:0:6}")"
    dst="$(agy_store_raw_path "$raw_id")"
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
    chmod 755 "$dst"
    agy_registry_py add-raw "$raw_id" "$version" "$sha256" "$sha512" "$dst" "$url" "$source" "$added_at"
    printf '%s\n' "$raw_id"
}

agy_store_record_runtime_file() {
    local runtime_src="$1" tuple_id="$2" raw_id="$3" wrapper_id="$4" smoke_tested_at="$5" verified_at="${6:-}"
    local dst
    dst="$(agy_store_runtime_path "$tuple_id")"
    mkdir -p "$(dirname "$dst")"
    cp -p "$runtime_src" "$dst"
    chmod 755 "$dst"
    agy_registry_py add-runtime "$tuple_id" "$raw_id" "$wrapper_id" "$dst" "$(agy_sha256 "$dst")" "$smoke_tested_at" "$verified_at"
    printf '%s\n' "$dst"
}

agy_store_record_wrapper() {
    local wrapper_id="$1" version="$2" commit="$3" added_at="$4"
    local dst
    dst="$(agy_store_wrapper_path "$wrapper_id")"
    mkdir -p "$dst"
    if [ -f "$AGY_RUNTIME_DIR/lib.sh" ]; then
        cp -p "$AGY_RUNTIME_DIR/lib.sh" "$dst/lib.sh"
        chmod 755 "$dst/lib.sh"
    fi
    if [ -f "$AGY_RUNTIME_DIR/managed.sh" ]; then
        cp -p "$AGY_RUNTIME_DIR/managed.sh" "$dst/managed.sh"
        chmod 755 "$dst/managed.sh"
    fi
    if [ -f "$AGY_RUNTIME_DIR/build-runtime.py" ]; then
        cp -p "$AGY_RUNTIME_DIR/build-runtime.py" "$dst/build-runtime.py"
        chmod 755 "$dst/build-runtime.py"
    fi
    if [ -f "$AGY_RUNTIME_DIR/wrapper-version.env" ]; then
        cp -p "$AGY_RUNTIME_DIR/wrapper-version.env" "$dst/wrapper-version.env"
    fi
    agy_registry_py add-wrapper "$wrapper_id" "$version" "$commit" "$dst" "$added_at"
}

agy_registry_record_current_wrapper() {
    agy_registry_ensure
    agy_store_record_wrapper "$(agy_current_wrapper_id)" "$(agy_current_wrapper_version)" "$(agy_current_wrapper_commit)" "$(date -Is)"
}

agy_store_record_runtime() {
    local tuple_id="$1" raw_id="$2" wrapper_id="$3" patched_sha256="$4" smoke_tested_at="$5" verified_at="$6"
    local dst
    dst="$(agy_store_runtime_path "$tuple_id")"
    mkdir -p "$(dirname "$dst")"
    cp -p "$AGY_PATCHED" "$dst"
    chmod 755 "$dst"
    agy_registry_py add-runtime "$tuple_id" "$raw_id" "$wrapper_id" "$dst" "$patched_sha256" "$smoke_tested_at" "$verified_at"
}

agy_registry_list_raw() {
    agy_registry_ensure
    agy_registry_py list-raw
}

agy_registry_list_wrapper() {
    agy_registry_ensure
    agy_registry_py list-wrapper
}

agy_registry_list_runtime() {
    agy_registry_ensure
    agy_registry_py list-runtime
}

agy_registry_has_runtime() {
    agy_registry_ensure
    agy_registry_py has-runtime "$1"
}

agy_registry_raw_field() {
    python3 - "$AGY_REGISTRY_FILE" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
field = sys.argv[3]
data = json.loads(path.read_text()) if path.exists() else {"raw": {}}
print(data.get("raw", {}).get(key, {}).get(field, ""))
PY
}

agy_registry_wrapper_field() {
    python3 - "$AGY_REGISTRY_FILE" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
field = sys.argv[3]
data = json.loads(path.read_text()) if path.exists() else {"wrapper": {}}
print(data.get("wrapper", {}).get(key, {}).get(field, ""))
PY
}

agy_registry_runtime_field() {
    python3 - "$AGY_REGISTRY_FILE" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
field = sys.argv[3]
data = json.loads(path.read_text()) if path.exists() else {"runtime": {}}
print(data.get("runtime", {}).get(key, {}).get(field, ""))
PY
}

agy_registry_raw_id_for_version() {
    local version="$1"
    agy_registry_list_raw | awk -F'\t' -v v="$version" '$2 == v { print $1; exit }'
}

agy_registry_wrapper_path() {
    agy_registry_wrapper_field "$1" path
}

agy_registry_runtime_exists() {
    local tuple_id="$1" runtime_path
    runtime_path="$(agy_registry_runtime_field "$tuple_id" path)"
    [ -n "$runtime_path" ] && [ -x "$runtime_path" ]
}

agy_compact_runtime_label() {
    local raw_version="${1:-unknown}" wrapper_version="${2:-unknown}" wrapper_commit="${3:-unknown}" short_commit
    short_commit="${wrapper_commit:-unknown}"
    short_commit="${short_commit:0:6}"
    [ -n "$short_commit" ] || short_commit="unknown"
    
    # Format the wrapper version (YYMMDD.NN) into a clean date (20YY-MM-DD)
    local formatted_wrapper="$wrapper_version"
    if [[ "$wrapper_version" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})\.[0-9]+$ ]]; then
        formatted_wrapper="20${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    elif [[ "$wrapper_version" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        formatted_wrapper="20${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    fi

    if [ -n "$T_RESET" ]; then
        printf 'agy %s%s%s / %s%s%s' \
            "${T_BOLD}${T_WHITE}" "$raw_version" "${T_RESET}" \
            "${C_MUTED}" "$formatted_wrapper" "${T_RESET}"
        if [ "$short_commit" != "unknown" ]; then
            printf ' %s(%s)%s' "${T_DIM}" "$short_commit" "${T_RESET}"
        fi
    else
        if [ "$short_commit" != "unknown" ]; then
            printf 'agy %s / %s (%s)' "$raw_version" "$formatted_wrapper" "$short_commit"
        else
            printf 'agy %s / %s' "$raw_version" "$formatted_wrapper"
        fi
    fi
}

agy_registry_print_candidates() {
    python3 - "$AGY_REGISTRY_FILE" "$AGY_STATE_FILE" <<'PY'
import json
import sys
from pathlib import Path

reg_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])
reg = json.loads(reg_path.read_text()) if reg_path.exists() else {"raw": {}, "wrapper": {}, "runtime": {}}
state = json.loads(state_path.read_text()) if state_path.exists() else {}
raws = reg.get("raw", {})
wrappers = reg.get("wrapper", {})
runtimes = reg.get("runtime", {})
preferred = state.get("PREFERRED_TUPLE_ID", "")
verified = state.get("VERIFIED_TUPLE_ID", "")
active = state.get("ACTIVE_TUPLE_ID", "")
seen = set()

def raw_key(raw_id):
    e = raws.get(raw_id, {})
    return (e.get("added_at", ""), e.get("version", ""), raw_id)

def wrapper_key(wrapper_id):
    e = wrappers.get(wrapper_id, {})
    return (e.get("added_at", ""), e.get("version", ""), wrapper_id)

def runtime_key(item):
    tuple_id, e = item
    score = 0
    if tuple_id == preferred: score += 400
    if tuple_id == verified: score += 300
    if tuple_id == active: score += 100
    if e.get("verified_at"): score += 20
    if e.get("smoke_tested_at"): score += 10
    return (score, e.get("verified_at") or e.get("smoke_tested_at") or "", tuple_id)

for tuple_id, e in sorted(runtimes.items(), key=runtime_key, reverse=True):
    raw_id = e.get("raw_id", "")
    wrapper_id = e.get("wrapper_id", "")
    if raw_id not in raws or wrapper_id not in wrappers:
        continue
    seen.add(tuple_id)
    raw = raws.get(raw_id, {})
    wrapper = wrappers.get(wrapper_id, {})
    flags = []
    if tuple_id == preferred: flags.append("preferred")
    if tuple_id == verified or e.get("verified_at"): flags.append("verified")
    elif e.get("smoke_tested_at"): flags.append("smoke")
    flags.append("cached")
    print("\t".join(["runtime", tuple_id, raw_id, wrapper_id, raw.get("version", "unknown"), wrapper.get("version", "unknown"), wrapper.get("commit", "unknown"), ",".join(flags), e.get("path", "")]))

for raw_id in sorted(raws, key=raw_key, reverse=True):
    for wrapper_id in sorted(wrappers, key=wrapper_key, reverse=True):
        tuple_id = f"{raw_id}__{wrapper_id}"
        if tuple_id in seen:
            continue
        raw = raws.get(raw_id, {})
        wrapper = wrappers.get(wrapper_id, {})
        print("\t".join(["build", tuple_id, raw_id, wrapper_id, raw.get("version", "unknown"), wrapper.get("version", "unknown"), wrapper.get("commit", "unknown"), "build", ""]))
PY
}

agy_registry_latest_raw_id() {
    agy_registry_list_raw | sed -n '1p' | awk -F'\t' '{print $1}'
}

agy_registry_latest_wrapper_id() {
    agy_registry_list_wrapper | sed -n '1p' | awk -F'\t' '{print $1}'
}

agy_registry_latest_runtime_id() {
    agy_registry_list_runtime | sed -n '1p' | awk -F'\t' '{print $1}'
}

agy_registry_prune() {
    python3 - "$AGY_REGISTRY_FILE" "$AGY_STATE_FILE" "$AGY_STORE_KEEP_RAW" "$AGY_STORE_KEEP_WRAPPER" "$AGY_STORE_KEEP_RUNTIME" "$AGY_STORE_DIR" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

reg_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])
keep_raw = max(0, int(sys.argv[3] or 0))
keep_wrapper = max(0, int(sys.argv[4] or 0))
keep_runtime = max(0, int(sys.argv[5] or 0))
store_root = Path(sys.argv[6])

def load_json(path, default):
    if not path.exists():
        return default
    try:
        data = json.loads(path.read_text())
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return default

registry = load_json(reg_path, {"schema": 1, "raw": {}, "wrapper": {}, "runtime": {}})
state = load_json(state_path, {})
registry.setdefault("schema", 1)
registry.setdefault("raw", {})
registry.setdefault("wrapper", {})
registry.setdefault("runtime", {})

protected_raw = set()
protected_wrapper = set()
protected_runtime = set()

for tuple_id in filter(None, [
    state.get("ACTIVE_TUPLE_ID", ""),
    state.get("PREFERRED_TUPLE_ID", ""),
    state.get("VERIFIED_TUPLE_ID", ""),
]):
    entry = registry.get("runtime", {}).get(tuple_id)
    if not entry:
        continue
    protected_runtime.add(tuple_id)
    if entry.get("raw_id"):
        protected_raw.add(entry["raw_id"])
    if entry.get("wrapper_id"):
        protected_wrapper.add(entry["wrapper_id"])

def remove_entry(kind, key, entry):
    raw_path = str(entry.get("path", ""))
    if not raw_path:
        return
    path = Path(raw_path)
    if kind == "wrapper":
        target = path
    else:
        target = path.parent
    if target.exists():
        shutil.rmtree(target, ignore_errors=True)
    elif path.exists():
        try:
            path.unlink()
        except Exception:
            pass

def prune(kind, keep, protected):
    entries = registry.get(kind, {})
    if not entries:
        return
    timestamp_key = "added_at" if kind != "runtime" else "verified_at"
    if kind == "runtime":
        def keyfn(item):
            key, entry = item
            return (entry.get("verified_at") or entry.get("smoke_tested_at") or "", key)
    else:
        def keyfn(item):
            key, entry = item
            return (entry.get(timestamp_key) or "", key)
    ordered = sorted(entries.items(), key=keyfn, reverse=True)
    keep_keys = set(protected)
    keep_keys.update(key for key, _ in ordered[:keep])
    for key, entry in list(entries.items()):
        if key in keep_keys:
            continue
        remove_entry(kind, key, entry)
        del entries[key]

prune("raw", keep_raw, protected_raw)
prune("wrapper", keep_wrapper, protected_wrapper)
prune("runtime", keep_runtime, protected_runtime)

tmp = reg_path.with_name("." + reg_path.name + ".tmp")
tmp.parent.mkdir(parents=True, exist_ok=True)
tmp.write_text(json.dumps(registry, ensure_ascii=True, sort_keys=True) + "\n")
os.chmod(tmp, 0o600)
os.replace(tmp, reg_path)
PY
}

agy_registry_record_current_tuple() {
    local version="${1:-}"
    local source_url="${2:-${AGY_MANIFEST_URL:-}}"
    local source_label="${3:-local}"
    local smoke_tested_at="${4:-$(date -Is)}"
    local verified_at="${5:-}"
    local raw_sha512="${6:-}"
    local raw_sha raw_id wrapper_id tuple_id

    [ -n "$version" ] || return 1
    [ -x "$AGY_RAW" ] || return 1
    [ -x "$AGY_PATCHED" ] || return 1
    raw_sha="$(agy_sha256 "$AGY_RAW")"
    [ -n "$raw_sha" ] || return 1
    raw_id="$(agy_raw_id "$version" "${raw_sha:0:6}")"
    wrapper_id="$(agy_current_wrapper_id)"
    tuple_id="$(agy_tuple_id "$raw_id" "$wrapper_id")"
    agy_store_record_raw "$raw_id" "$version" "$raw_sha" "$raw_sha512" "$source_url" "$source_label" "$smoke_tested_at"
    agy_store_record_wrapper "$wrapper_id" "$(agy_current_wrapper_version)" "$(agy_current_wrapper_commit)" "$smoke_tested_at"
    agy_store_record_runtime "$tuple_id" "$raw_id" "$wrapper_id" "$(agy_sha256 "$AGY_PATCHED")" "$smoke_tested_at" "$verified_at"
    printf '%s\t%s\t%s\n' "$raw_id" "$wrapper_id" "$tuple_id"
}

agy_state_set_active_tuple() {
    local tuple_id="$1"
    agy_load_state
    ACTIVE_TUPLE_ID="$tuple_id"
    agy_write_state
}

agy_state_set_preferred_tuple() {
    local tuple_id="$1" label="${2:-}" set_at="${3:-$(date -Is)}"
    agy_load_state
    PREFERRED_TUPLE_ID="$tuple_id"
    PREFERRED_LABEL="$label"
    PREFERRED_SET_AT="$set_at"
    agy_write_state
}

agy_state_clear_preferred_tuple() {
    agy_load_state
    PREFERRED_TUPLE_ID=""
    PREFERRED_LABEL=""
    PREFERRED_SET_AT=""
    agy_write_state
}

agy_registry_bootstrap_from_current() {
    local raw_version tuple_info raw_id wrapper_id tuple_id
    local now

    agy_registry_ensure
    agy_load_state
    now="$(date -Is)"
    agy_registry_record_current_wrapper
    raw_version="${VERIFIED_VERSION:-${LAST_SEEN_UPSTREAM_VERSION:-}}"
    if [ -z "$raw_version" ] && [ -x "$AGY_PATCHED" ]; then
        raw_version="$(agy_current_version 2>/dev/null || true)"
    fi
    if [ ! -x "$AGY_RAW" ] || [ ! -x "$AGY_PATCHED" ]; then
        return 0
    fi
    tuple_info="$(agy_registry_record_current_tuple "${raw_version:-unknown}" "${AGY_MANIFEST_URL:-}" "local" "$now" "")" || return 1
    raw_id="$(printf '%s\n' "$tuple_info" | awk -F'\t' '{print $1}')"
    wrapper_id="$(printf '%s\n' "$tuple_info" | awk -F'\t' '{print $2}')"
    tuple_id="$(printf '%s\n' "$tuple_info" | awk -F'\t' '{print $3}')"
    ACTIVE_TUPLE_ID="$tuple_id"
    agy_write_state
    agy_registry_prune
}

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
    ACTIVE_TUPLE_ID=""
    PREFERRED_TUPLE_ID=""
    PREFERRED_LABEL=""
    PREFERRED_SET_AT=""
    VERIFIED_TUPLE_ID=""
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
    LAST_KILL_SWITCH_STATUS=""
    LAST_KILL_SWITCH_AT=""
    LAST_KILL_SWITCH_CASE=""
}

agy_safe_state_kv() {
    local key="$1" val="$2"
    case "$key" in
        PATCHED_FROM_ORIGINAL_SHA256|PATCHED_SHA256|LAST_RAW_SHA256|LAST_REPAIR_AT|LAST_SELF_UPDATE_AT|ACTIVE_TUPLE_ID|PREFERRED_TUPLE_ID|PREFERRED_LABEL|PREFERRED_SET_AT|VERIFIED_TUPLE_ID|VERIFIED_VERSION|VERIFIED_WRAPPER_VERSION|VERIFIED_WRAPPER_COMMIT|VERIFIED_RAW_SHA256|VERIFIED_PATCHED_SHA256|VERIFIED_AT|VERIFIED_ENTRYPOINT|LAST_SEEN_UPSTREAM_VERSION|LAST_FAILED_UPDATE_VERSION|LAST_FAILED_UPDATE_STATUS|LAST_FAILED_UPDATE_AT|LAST_FAILED_UPDATE_CASE|LAST_KILL_SWITCH_STATUS|LAST_KILL_SWITCH_AT|LAST_KILL_SWITCH_CASE|NEEDS_REPATCH) ;;
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
 "LAST_SELF_UPDATE_AT","ACTIVE_TUPLE_ID","PREFERRED_TUPLE_ID","PREFERRED_LABEL",
 "PREFERRED_SET_AT","VERIFIED_TUPLE_ID","VERIFIED_VERSION","VERIFIED_WRAPPER_VERSION",
 "VERIFIED_WRAPPER_COMMIT","VERIFIED_RAW_SHA256","VERIFIED_PATCHED_SHA256",
 "VERIFIED_AT","VERIFIED_ENTRYPOINT","LAST_SEEN_UPSTREAM_VERSION",
 "LAST_FAILED_UPDATE_VERSION","LAST_FAILED_UPDATE_STATUS","LAST_FAILED_UPDATE_AT",
 "LAST_FAILED_UPDATE_CASE","LAST_KILL_SWITCH_STATUS","LAST_KILL_SWITCH_AT",
 "LAST_KILL_SWITCH_CASE","NEEDS_REPATCH"]
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
        "$ACTIVE_TUPLE_ID" \
        "$PREFERRED_TUPLE_ID" \
        "$PREFERRED_LABEL" \
        "$PREFERRED_SET_AT" \
        "$VERIFIED_TUPLE_ID" \
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
        "$LAST_FAILED_UPDATE_CASE" \
        "$LAST_KILL_SWITCH_STATUS" \
        "$LAST_KILL_SWITCH_AT" \
        "$LAST_KILL_SWITCH_CASE" <<'PY'
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
 "ACTIVE_TUPLE_ID":sys.argv[8],
 "PREFERRED_TUPLE_ID":sys.argv[9],
 "PREFERRED_LABEL":sys.argv[10],
 "PREFERRED_SET_AT":sys.argv[11],
 "VERIFIED_TUPLE_ID":sys.argv[12],
 "VERIFIED_VERSION":sys.argv[13],
 "VERIFIED_WRAPPER_VERSION":sys.argv[14],
 "VERIFIED_WRAPPER_COMMIT":sys.argv[15],
 "VERIFIED_RAW_SHA256":sys.argv[16],
 "VERIFIED_PATCHED_SHA256":sys.argv[17],
 "VERIFIED_AT":sys.argv[18],
 "VERIFIED_ENTRYPOINT":sys.argv[19],
 "LAST_SEEN_UPSTREAM_VERSION":sys.argv[20],
 "LAST_FAILED_UPDATE_VERSION":sys.argv[21],
 "LAST_FAILED_UPDATE_STATUS":sys.argv[22],
 "LAST_FAILED_UPDATE_AT":sys.argv[23],
 "LAST_FAILED_UPDATE_CASE":sys.argv[24],
 "LAST_KILL_SWITCH_STATUS":sys.argv[25],
 "LAST_KILL_SWITCH_AT":sys.argv[26],
 "LAST_KILL_SWITCH_CASE":sys.argv[27],
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
                ACTIVE_TUPLE_ID) ACTIVE_TUPLE_ID="$v" ;;
                PREFERRED_TUPLE_ID) PREFERRED_TUPLE_ID="$v" ;;
                PREFERRED_LABEL) PREFERRED_LABEL="$v" ;;
                PREFERRED_SET_AT) PREFERRED_SET_AT="$v" ;;
                VERIFIED_TUPLE_ID) VERIFIED_TUPLE_ID="$v" ;;
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
                LAST_KILL_SWITCH_STATUS) LAST_KILL_SWITCH_STATUS="$v" ;;
                LAST_KILL_SWITCH_AT) LAST_KILL_SWITCH_AT="$v" ;;
                LAST_KILL_SWITCH_CASE) LAST_KILL_SWITCH_CASE="$v" ;;
            esac
        done < <(agy_state_read_json "$AGY_STATE_FILE")
    fi
}

agy_write_state() {
    agy_state_write_json
}

agy_termux_resolver_ok() {
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
    local run_home
    executable="$1"
    shift
    run_home="${AGY_PROFILE_HOME:-$HOME}"
    if [ -d "$AGY_CERT_DIR" ]; then
        cert_dir_env=("SSL_CERT_DIR=$AGY_CERT_DIR")
    fi
    runtime_env=(env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        HOME="$run_home" \
        XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$run_home/.config}" \
        XDG_CACHE_HOME="${XDG_CACHE_HOME:-$run_home/.cache}" \
        XDG_DATA_HOME="${XDG_DATA_HOME:-$run_home/.local/share}" \
        GODEBUG="${GODEBUG:-netdns=go}" \
        SSL_CERT_FILE="$AGY_CERT_FILE" \
        "${cert_dir_env[@]}")
    if ! agy_termux_resolver_ok; then
        printf 'agy: resolver source is unavailable: %s\n' "$AGY_RESOLV_CONF" >&2
        return 66
    fi
    "${runtime_env[@]}" "$AGY_LOADER" --library-path "$AGY_GLIBC_LIB" "$executable" \
        --release_base_url="$AGY_UPSTREAM_UPDATE_DISABLED_BASE_URL" "$@" \
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

agy_profile_validate_name() {
    local profile="${1:-}"
    case "$profile" in
        ""|default)
            return 0
            ;;
        termux|-*|.*|*/*|*..*|*[[:space:]]*)
            return 1
            ;;
    esac
    return 0
}

agy_profile_root() {
    printf '%s\n' "${AGY_PROFILE_ROOT:-$HOME/.agy-profiles}"
}

agy_profile_dir() {
    local profile="${1:-}"
    printf '%s/%s\n' "$(agy_profile_root)" "$profile"
}

agy_list_profiles() {
    local root
    root="$(agy_profile_root)"
    [ -d "$root" ] || return 0
    find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sed -n 's#.*/##p' \
        | grep -Ev '^(default|termux)$' \
        | grep -Ev '^[.]' \
        | LC_ALL=C sort -f
}

agy_prompt_choice() {
    local prompt="${1:-profile> }" _max_items="${2:-9}" reply rest
    
    # Format the prompt with nice color and arrow if color is enabled
    if [ -n "$T_RESET" ]; then
        local styled_prompt="${prompt%> }"
        styled_prompt="${styled_prompt% }"
        prompt="  ${C_PROMPT}${styled_prompt} ❯ ${T_RESET}"
    else
        prompt="  ${prompt}"
    fi
    
    printf '%s' "$prompt" >&2
    if [ -t 0 ]; then
        local old_tty status
        old_tty="$(stty -g 2>/dev/null || true)"
        [ -z "$old_tty" ] || stty -echo -icanon min 1 time 0 2>/dev/null || true
        IFS= read -r -N 1 reply
        status=$?
        [ -z "$old_tty" ] || stty "$old_tty" 2>/dev/null || true
        if [ "$status" -ne 0 ]; then
            printf '\n' >&2
            return 1
        fi
    elif ! IFS= read -r -N 1 reply; then
        printf '\n' >&2
        return 1
    fi
    case "$reply" in
        $'\e')
            printf '\n' >&2
            return 130
            ;;
        $'\n'|$'\r'|'')
            printf '\n' >&2
            return 0
            ;;
        [1-9])
            if [ "$_max_items" -le 9 ]; then
                printf '%s\n' "$reply" >&2
                printf '%s\n' "$reply"
                return 0
            fi
            ;;
        *)
            ;;
    esac
    rest=""
    printf '%s' "$reply" >&2
    IFS= read -r rest || true
    printf '%s%s\n' "$reply" "$rest"
    return 0
}


agy_bare_resume_prompt() {
    local choice

    if [ ! -t 0 ]; then
        printf 'latest\n'
        return 0
    fi

    agy_bare_print_resume_candidates >&2
    choice="$(agy_prompt_choice 'agy> ' 2)" || return $?
    case "$choice" in
        ""|"1"|"previous"|"prev"|"p"|"P")
            printf 'previous\n'
            return 0
            ;;
        "2"|"latest"|"l"|"L")
            printf 'latest\n'
            return 0
            ;;
        $'\e')
            printf '  %sagy: cancelled.%s\n' "${C_MUTED}" "${T_RESET}" >&2
            return 130
            ;;
        *)
            printf '  %sagy: invalid selection: %s%s\n' "${T_RED}" "$choice" "${T_RESET}" >&2
            return 2
            ;;
    esac
}

agy_bare_print_resume_candidates() {
    local raw_id wrapper_id raw_version wrapper_version wrapper_commit latest_raw_id latest_wrapper_id latest_raw_version latest_wrapper_version latest_wrapper_commit
    agy_load_state
    
    agy_print_header "agy" "Resume or start new session"
    
    latest_raw_id="$(agy_registry_latest_raw_id)"
    latest_wrapper_id="$(agy_registry_latest_wrapper_id)"
    latest_raw_version="$(agy_registry_raw_field "$latest_raw_id" version)"
    latest_wrapper_version="$(agy_registry_wrapper_field "$latest_wrapper_id" version)"
    latest_wrapper_commit="$(agy_registry_wrapper_field "$latest_wrapper_id" commit)"
    
    if [ -n "${PREFERRED_TUPLE_ID:-}" ]; then
        raw_id="$(agy_registry_runtime_field "$PREFERRED_TUPLE_ID" raw_id)"
        wrapper_id="$(agy_registry_runtime_field "$PREFERRED_TUPLE_ID" wrapper_id)"
        raw_version="$(agy_registry_raw_field "$raw_id" version)"
        wrapper_version="$(agy_registry_wrapper_field "$wrapper_id" version)"
        wrapper_commit="$(agy_registry_wrapper_field "$wrapper_id" commit)"
        local prev_label
        prev_label="$(agy_compact_runtime_label "$raw_version" "$wrapper_version" "$wrapper_commit")"
        printf '  %s1.%s %s%-10s%s  %s\n' "${C_NUMBER}" "${T_RESET}" "${T_BOLD}" "previous" "${T_RESET}" "$prev_label"
    else
        printf '  %s1.%s %s%-10s%s  %sunavailable%s\n' "${C_NUMBER}" "${T_RESET}" "${T_BOLD}" "previous" "${T_RESET}" "${C_MUTED}" "${T_RESET}"
    fi
    
    if [ -n "$latest_raw_id" ] && [ -n "$latest_wrapper_id" ]; then
        local latest_label
        latest_label="$(agy_compact_runtime_label "$latest_raw_version" "$latest_wrapper_version" "$latest_wrapper_commit")"
        printf '  %s2.%s %s%-10s%s  %s\n' "${C_NUMBER}" "${T_RESET}" "${T_BOLD}" "latest" "${T_RESET}" "$latest_label"
    else
        printf '  %s2.%s %s%-10s%s  %srefresh wrapper and upstream binary%s\n' "${C_NUMBER}" "${T_RESET}" "${T_BOLD}" "latest" "${T_RESET}" "${C_MUTED}" "${T_RESET}"
    fi
    printf '\n' >&2
}

agy_use_prompt_selection() {
    local max_items="${1:-0}" choice

    if [ ! -t 0 ]; then
        return 1
    fi

    choice="$(agy_prompt_choice 'agy use> ' "$max_items")" || return $?
    printf '%s\n' "$choice"
    return 0
}

agy_run_bare_runtime() {
    local first="${1:-}"
    local before after temp_raw exit_code case_dir bare_action raw_id wrapper_id
    agy_light_preflight || return $?
    agy_load_state
    bare_action="latest"
    if [ -n "${PREFERRED_TUPLE_ID:-}" ] && [ -t 0 ]; then
        bare_action="$(agy_bare_resume_prompt)" || return $?
    fi
    case "$bare_action" in
        previous)
            agy_load_state
            if [ -n "${PREFERRED_TUPLE_ID:-}" ]; then
                raw_id="$(agy_registry_runtime_field "$PREFERRED_TUPLE_ID" raw_id)"
                wrapper_id="$(agy_registry_runtime_field "$PREFERRED_TUPLE_ID" wrapper_id)"
                if [ -n "$raw_id" ] && [ -n "$wrapper_id" ] && agy_use_activate_tuple "$PREFERRED_TUPLE_ID" "$raw_id" "$wrapper_id"; then
                    agy_run_selected_runtime "$AGY_PATCHED"
                    return $?
                fi
            fi
            agy_state_clear_preferred_tuple
            printf 'agy: previous tuple unavailable; using latest.\n' >&2
            ;;
        latest)
            agy_state_clear_preferred_tuple
            ;;
    esac
    if [ "$bare_action" = "latest" ]; then
        agy_refresh_wrapper_and_reexec_if_needed quiet "$@" || return $?
    fi
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
}

agy_run_selected_runtime() {
    local runtime_path="${1:-$AGY_PATCHED}"
    shift || true
    local before after temp_raw exit_code case_dir

    before=$(agy_sha256 "$AGY_RAW")
    temp_raw="${TMPDIR:-/tmp}/agy_raw_$$"
    : >"$temp_raw"
    set +e
    agy_load_state
    agy_runtime_command "$runtime_path" "$@" 2> >(tee "$temp_raw" >&2)
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
}

agy_tuple_runtime_path() {
    local tuple_id="$1" raw_id="$2" wrapper_id="$3" log_file="${4:-}"
    local runtime_path raw_path tmp_dir candidate status
    runtime_path="$(agy_registry_runtime_field "$tuple_id" path)"
    if [ -n "$runtime_path" ] && [ -x "$runtime_path" ]; then
        printf '%s\n' "$runtime_path"
        return 0
    fi
    raw_path="$(agy_registry_raw_field "$raw_id" path)"
    [ -n "$raw_path" ] && [ -x "$raw_path" ] || return 1
    tmp_dir=$(mktemp -d "$AGY_STATE_DIR/tuple.XXXXXX") || return 1
    candidate="$tmp_dir/agy"
    : "${log_file:=$tmp_dir/build.log}"
    set +e
    agy_build_runtime_candidate "$raw_path" "$candidate" "$log_file" "$wrapper_id"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$log_file" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi
    runtime_path="$(agy_store_record_runtime_file "$candidate" "$tuple_id" "$raw_id" "$wrapper_id" "$(date -Is)" "")"
    rm -rf "$tmp_dir"
    agy_registry_prune
    printf '%s\n' "$runtime_path"
}

agy_use_activate_tuple() {
    local tuple_id="$1" raw_id="$2" wrapper_id="$3"
    local raw_path runtime_path raw_version raw_hash patched_hash
    raw_path="$(agy_registry_raw_field "$raw_id" path)"
    raw_version="$(agy_registry_raw_field "$raw_id" version)"
    [ -n "$raw_path" ] && [ -x "$raw_path" ] || return 1
    runtime_path="$(agy_tuple_runtime_path "$tuple_id" "$raw_id" "$wrapper_id")" || return $?
    [ -n "$runtime_path" ] && [ -x "$runtime_path" ] || return 1
    mkdir -p "$(dirname "$AGY_RAW")" "$(dirname "$AGY_PATCHED")"
    cp -p "$raw_path" "$AGY_RAW"
    cp -p "$runtime_path" "$AGY_PATCHED"
    chmod 755 "$AGY_RAW" "$AGY_PATCHED"
    raw_hash="$(agy_sha256 "$AGY_RAW")"
    patched_hash="$(agy_sha256 "$AGY_PATCHED")"
    agy_load_state
    ACTIVE_TUPLE_ID="$tuple_id"
    PATCHED_FROM_ORIGINAL_SHA256="$raw_hash"
    PATCHED_SHA256="$patched_hash"
    LAST_RAW_SHA256="$raw_hash"
    LAST_SEEN_UPSTREAM_VERSION="${raw_version:-${LAST_SEEN_UPSTREAM_VERSION:-}}"
    NEEDS_REPATCH=0
    agy_write_state
    return 0
}

agy_use_print_candidates() {
    local count=0 kind tuple_id raw_id wrapper_id raw_version wrapper_version wrapper_commit flags runtime_path label
    local version manifest_url url sha512 latest_wrapper_id latest_wrapper_version latest_wrapper_commit
    local interactive_limit=0 truncated=0

    if [ -t 0 ]; then
        interactive_limit=9
    fi

    agy_registry_bootstrap_from_current
    latest_wrapper_id="$(agy_registry_latest_wrapper_id)"
    latest_wrapper_version="$(agy_registry_wrapper_field "$latest_wrapper_id" version)"
    latest_wrapper_commit="$(agy_registry_wrapper_field "$latest_wrapper_id" commit)"

    agy_print_header "agy use" "Select Termux runtime configuration"

    while IFS=$'\t' read -r kind tuple_id raw_id wrapper_id raw_version wrapper_version wrapper_commit flags runtime_path; do
        [ -n "$tuple_id" ] || continue
        if [ "$interactive_limit" -gt 0 ] && [ "$count" -ge "$interactive_limit" ]; then
            truncated=1
            continue
        fi
        count=$((count + 1))
        label="$(agy_compact_runtime_label "$raw_version" "$wrapper_version" "$wrapper_commit")"
        local badges
        badges="$(agy_format_flags "$flags")"
        printf '  %s%2d.%s %s %s\n' "${C_NUMBER}" "$count" "${T_RESET}" "$label" "$badges"
    done < <(agy_registry_print_candidates)

    while IFS=$'\t' read -r version manifest_url url sha512; do
        [ -n "$version" ] || continue
        if [ "$interactive_limit" -gt 0 ] && [ "$count" -ge "$interactive_limit" ]; then
            truncated=1
            continue
        fi
        count=$((count + 1))
        label="$(agy_compact_runtime_label "$version" "${latest_wrapper_version:-unknown}" "${latest_wrapper_commit:-unknown}")"
        local badges
        badges="$(agy_format_flags "remote")"
        printf '  %s%2d.%s %s %s\n' "${C_NUMBER}" "$count" "${T_RESET}" "$label" "$badges"
    done < <(agy_remote_raw_candidates)

    AGY_USE_MENU_COUNT="$count"
    if [ "$truncated" -eq 1 ]; then
        printf '  %s(More options: %sagy use <version>%s)\n\n' "${C_MUTED}" "${T_UNDERLINE}" "${T_RESET}" >&2
    else
        printf '\n' >&2
    fi
}

agy_select_remote_raw() {
    local version="$1" manifest_url="$2" url="$3" expected_sha="$4"
    local tmp_dir status actual_sha extracted raw_id
    tmp_dir=$(mktemp -d "$AGY_STATE_DIR/use-remote.XXXXXX") || return 1
    set +e
    curl -fsSL --connect-timeout "$AGY_AUTO_UPDATE_TIMEOUT" --max-time "$AGY_AUTO_UPDATE_TIMEOUT" "$url" >"$tmp_dir/agy.tgz" 2>"$tmp_dir/download.log"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/download.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi
    actual_sha=$(sha512sum "$tmp_dir/agy.tgz" | awk '{print $1}')
    if [ "$actual_sha" != "$expected_sha" ]; then
        printf 'sha512 mismatch\nexpected=%s\nactual=%s\n' "$expected_sha" "$actual_sha" >"$tmp_dir/download.log"
        agy_make_case 75 "$tmp_dir/download.log" >/dev/null
        rm -rf "$tmp_dir"
        return 75
    fi
    mkdir -p "$tmp_dir/extract"
    if ! agy_validate_tarball_safe "$tmp_dir/agy.tgz" >"$tmp_dir/extract.log" 2>&1; then
        agy_make_case 78 "$tmp_dir/extract.log" >/dev/null
        rm -rf "$tmp_dir"
        return 78
    fi
    set +e
    tar -xzf "$tmp_dir/agy.tgz" -C "$tmp_dir/extract" >>"$tmp_dir/extract.log" 2>&1
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/extract.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi
    extracted="$tmp_dir/extract/antigravity"
    if [ ! -s "$extracted" ]; then
        printf 'expected extracted antigravity binary not found\n' >"$tmp_dir/extract.log"
        agy_make_case 76 "$tmp_dir/extract.log" >/dev/null
        rm -rf "$tmp_dir"
        return 76
    fi
    chmod 755 "$extracted"
    raw_id="$(agy_store_record_raw_file "$extracted" "$version" "$(agy_sha256 "$extracted")" "$expected_sha" "$manifest_url" "remote" "$(date -Is)")"
    rm -rf "$tmp_dir"
    printf '%s\n' "$raw_id"
}

agy_use_select_candidate() {
    local selection="$1"
    local selected_kind="" selected_tuple_id="" selected_raw_id="" selected_wrapper_id="" selected_manifest_url="" selected_version="" selected_url="" selected_sha="" selected_label=""
    local kind tuple_id raw_id wrapper_id raw_version wrapper_version wrapper_commit flags runtime_path count=0
    local version manifest_url url sha512 latest_wrapper_id current_latest_raw_id current_latest_wrapper_id current_latest_tuple_id

    agy_registry_bootstrap_from_current
    latest_wrapper_id="$(agy_registry_latest_wrapper_id)"

    while IFS=$'\t' read -r kind tuple_id raw_id wrapper_id raw_version wrapper_version wrapper_commit flags runtime_path; do
        [ -n "$tuple_id" ] || continue
        count=$((count + 1))
        if [ "$selection" = "$count" ] || [ "$selection" = "$tuple_id" ]; then
            selected_kind="$kind"
            selected_tuple_id="$tuple_id"
            selected_raw_id="$raw_id"
            selected_wrapper_id="$wrapper_id"
            break
        fi
    done < <(agy_registry_print_candidates)

    if [ -z "$selected_kind" ]; then
        while IFS=$'\t' read -r version manifest_url url sha512; do
            [ -n "$version" ] || continue
            count=$((count + 1))
            if [ "$selection" = "$count" ] || [ "$selection" = "$version" ]; then
                selected_kind="remote"
                selected_version="$version"
                selected_manifest_url="$manifest_url"
                selected_url="$url"
                selected_sha="$sha512"
                selected_wrapper_id="$latest_wrapper_id"
                break
            fi
        done < <(agy_remote_raw_candidates)
    fi

    if [ -z "$selected_kind" ]; then
        printf 'agy use: unknown selection: %s\n' "$selection" >&2
        return 2
    fi

    if [ "$selected_kind" = "remote" ]; then
        [ -n "$selected_manifest_url" ] && [ -n "$selected_url" ] && [ -n "$selected_sha" ] || return 74
        selected_raw_id="$(agy_select_remote_raw "$selected_version" "$selected_manifest_url" "$selected_url" "$selected_sha")" || return $?
        selected_tuple_id="$(agy_tuple_id "$selected_raw_id" "$selected_wrapper_id")"
    fi

    selected_label="$(agy_compact_runtime_label \
        "$(agy_registry_raw_field "$selected_raw_id" version)" \
        "$(agy_registry_wrapper_field "$selected_wrapper_id" version)" \
        "$(agy_registry_wrapper_field "$selected_wrapper_id" commit)")"

    if ! agy_use_activate_tuple "$selected_tuple_id" "$selected_raw_id" "$selected_wrapper_id"; then
        printf 'agy use: tuple unavailable: %s\n' "$selected_tuple_id" >&2
        return 77
    fi
    current_latest_raw_id="$(agy_registry_latest_raw_id)"
    current_latest_wrapper_id="$(agy_registry_latest_wrapper_id)"
    current_latest_tuple_id="$(agy_tuple_id "$current_latest_raw_id" "$current_latest_wrapper_id")"
    if [ "$selected_tuple_id" = "$current_latest_tuple_id" ]; then
        agy_state_clear_preferred_tuple
    else
        agy_state_set_preferred_tuple "$selected_tuple_id" "$selected_label"
    fi
    agy_run_selected_runtime "$AGY_PATCHED"
}

agy_use() {
    local selection="${1:-}"
    shift || true
    if [ -z "$selection" ]; then
        agy_use_print_candidates
        if [ ! -t 0 ]; then
            return 0
        fi
        selection="$(agy_use_prompt_selection "${AGY_USE_MENU_COUNT:-0}")" || return $?
        if [ -z "$selection" ]; then
            printf '  %sagy use: cancelled.%s\n' "${C_MUTED}" "${T_RESET}" >&2
            return 1
        fi
    fi
    agy_use_select_candidate "$selection"
}

agy_profile_run() {
    local profile="${1:-}"
    shift || true
    local profile_dir
    if [ -z "$profile" ]; then
        agy_profile_select
        return $?
    fi
    if ! agy_profile_validate_name "$profile"; then
        printf 'agy profile: invalid profile name: %s\n' "$profile" >&2
        return 2
    fi
    if [ "$#" -ne 0 ]; then
        printf 'agy profile: unexpected argument: %s\n' "$1" >&2
        printf 'usage: agy profile [NAME]\n' >&2
        return 2
    fi
    profile_dir="$(agy_profile_dir "$profile")"
    if [ ! -d "$profile_dir" ]; then
        printf 'agy profile: profile not found: %s\n' "$profile" >&2
        printf 'create it first: mkdir -p %s\n' "$profile_dir" >&2
        return 2
    fi
    AGY_PROFILE_HOME="$profile_dir" agy_run_bare_runtime
}

agy_profile_select() {
    local root profiles profile choice i idx display_limit=0 truncated=0
    root="$(agy_profile_root)"
    mapfile -t profiles < <(agy_list_profiles)
    if [ "${#profiles[@]}" -eq 0 ]; then
        printf '  %sagy profile: no profiles found in %s%s\n' "${T_RED}" "$root" "${T_RESET}" >&2
        return 0
    fi
    if [ -t 0 ]; then
        display_limit=9
    fi
    
    agy_print_header "agy profile" "Select or enter an auth/session profile"
    
    idx=0
    for profile in "${profiles[@]}"; do
        idx=$((idx + 1))
        if [ "$display_limit" -gt 0 ] && [ "$idx" -gt "$display_limit" ]; then
            truncated=1
            continue
        fi
        printf '  %s%2d.%s %s%s%s\n' "${C_NUMBER}" "$idx" "${T_RESET}" "${T_BOLD}" "$profile" "${T_RESET}"
    done
    if [ "$truncated" -eq 1 ]; then
        printf '  %s(More options: %sagy profile NAME%s)\n\n' "${C_MUTED}" "${T_UNDERLINE}" "${T_RESET}" >&2
    else
        printf '\n' >&2
    fi
    if [ ! -t 0 ]; then
        return 0
    fi
    choice="$(agy_prompt_choice 'profile> ' "${#profiles[@]}")" || {
        local prompt_status=$?
        [ "$prompt_status" -eq 130 ] && printf '  %sagy profile: cancelled.%s\n' "${C_MUTED}" "${T_RESET}" >&2
        return "$prompt_status"
    }
    case "$choice" in
        "")
            printf '  %sagy profile: cancelled.%s\n' "${C_MUTED}" "${T_RESET}" >&2
            return 1
            ;;
        *[!0-9]*)
            for profile in "${profiles[@]}"; do
                if [ "$choice" = "$profile" ]; then
                    AGY_PROFILE_HOME="$(agy_profile_dir "$profile")" agy_run_bare_runtime
                    return $?
                fi
            done
            printf '  %sagy profile: unknown profile: %s%s\n' "${T_RED}" "$choice" "${T_RESET}" >&2
            return 2
            ;;
    esac
    i="$choice"
    if [ "$i" -lt 1 ] || [ "$i" -gt "${#profiles[@]}" ]; then
        printf '  %sagy profile: invalid selection: %s%s\n' "${T_RED}" "$choice" "${T_RESET}" >&2
        return 2
    fi
    profile="${profiles[$((i - 1))]}"
    AGY_PROFILE_HOME="$(agy_profile_dir "$profile")" agy_run_bare_runtime
}


agy_build_runtime_candidate() {
    local raw_input="$1"
    local runtime_output="$2"
    local log_file="$3"
    local wrapper_id="${4:-}"
    local builder="$AGY_RUNTIME_BUILDER" wrapper_dir
    local report_file="${log_file}.report.json"

    if [ -n "$wrapper_id" ]; then
        wrapper_dir="$(agy_registry_wrapper_path "$wrapper_id")"
        if [ -n "$wrapper_dir" ] && [ -f "$wrapper_dir/build-runtime.py" ]; then
            builder="$wrapper_dir/build-runtime.py"
        else
            printf 'wrapper builder missing for %s\n' "$wrapper_id" >"$log_file"
            return 70
        fi
    fi

    if ! python3 "$builder" "$raw_input" --output "$runtime_output" --report-json "$report_file" >"$log_file" 2>&1; then
        return 70
    fi
    if command -v patchelf >/dev/null 2>&1; then
        if ! patchelf --set-interpreter "$AGY_LOADER" "$runtime_output" >>"$log_file" 2>&1; then
            return 71
        fi
    fi
    chmod 755 "$runtime_output"
    if ! agy_run_candidate "$runtime_output" --version >>"$log_file" 2>&1; then
        agy_load_state
        LAST_KILL_SWITCH_STATUS="failed"
        LAST_KILL_SWITCH_AT="$(date -Is)"
        LAST_KILL_SWITCH_CASE="$log_file"
        agy_write_state
        return 72
    fi
    agy_load_state
    LAST_KILL_SWITCH_STATUS="ok"
    LAST_KILL_SWITCH_AT="$(date -Is)"
    LAST_KILL_SWITCH_CASE=""
    agy_write_state
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
        printf 'You are diagnosing a Termux runtime agy wrapper failure.\n\n'
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
    if [ -f "${raw_log}.report.json" ]; then
        cp "${raw_log}.report.json" "$case_dir/build-report.json"
        chmod 600 "$case_dir/build-report.json"
    fi
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

    local tmp_dir candidate raw_hash patched_hash old_backup tuple_info
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
    if tuple_info="$(agy_registry_record_current_tuple "${LAST_SEEN_UPSTREAM_VERSION:-${VERIFIED_VERSION:-unknown}}" "${AGY_MANIFEST_URL:-}" "local" "$(date -Is)" "")"; then
        ACTIVE_TUPLE_ID="$(printf '%s\n' "$tuple_info" | awk -F'\t' '{print $3}')"
    fi
    agy_write_state
    agy_registry_prune
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
        profile)
            printf 'profile\n'
            return 0
            ;;
        use)
            printf 'use\n'
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
    local raw_sha raw_id wrapper_id tuple_id now tuple_info runtime_path
    [ -n "$version" ] || return 0
    agy_load_state
    agy_reload_wrapper_version
    raw_sha="$(agy_sha256 "$AGY_RAW")"
    [ -n "$raw_sha" ] || return 0
    now="$(date -Is)"

    if [ -n "${ACTIVE_TUPLE_ID:-}" ]; then
        raw_id="$(agy_registry_runtime_field "$ACTIVE_TUPLE_ID" raw_id)"
        wrapper_id="$(agy_registry_runtime_field "$ACTIVE_TUPLE_ID" wrapper_id)"
        runtime_path="$(agy_registry_runtime_field "$ACTIVE_TUPLE_ID" path)"
        if [ -n "$raw_id" ] && [ -n "$wrapper_id" ]; then
            tuple_id="$ACTIVE_TUPLE_ID"
            if [ -x "$AGY_PATCHED" ]; then
                agy_store_record_runtime_file "$AGY_PATCHED" "$tuple_id" "$raw_id" "$wrapper_id" "$now" "$now" >/dev/null || true
            elif [ -n "$runtime_path" ] && [ -x "$runtime_path" ]; then
                agy_registry_py add-runtime "$tuple_id" "$raw_id" "$wrapper_id" "$runtime_path" "$(agy_sha256 "$runtime_path")" "$now" "$now"
            fi
        fi
    fi

    if [ -z "${tuple_id:-}" ]; then
        raw_id="$(agy_raw_id "$version" "${raw_sha:0:6}")"
        wrapper_id="$(agy_current_wrapper_id)"
        tuple_id="$(agy_tuple_id "$raw_id" "$wrapper_id")"
        tuple_info="$(agy_registry_record_current_tuple "$version" "${AGY_MANIFEST_URL:-}" "local" "$now" "$now")" || return 0
        tuple_id="$(printf '%s\n' "$tuple_info" | awk -F'\t' '{print $3}')"
    fi

    VERIFIED_VERSION="$version"
    VERIFIED_WRAPPER_VERSION="$(agy_registry_wrapper_field "$wrapper_id" version)"
    VERIFIED_WRAPPER_COMMIT="$(agy_registry_wrapper_field "$wrapper_id" commit)"
    VERIFIED_WRAPPER_VERSION="${VERIFIED_WRAPPER_VERSION:-${AGY_WRAPPER_VERSION:-unknown}}"
    VERIFIED_WRAPPER_COMMIT="${VERIFIED_WRAPPER_COMMIT:-${AGY_WRAPPER_COMMIT:-unknown}}"
    VERIFIED_RAW_SHA256="$raw_sha"
    VERIFIED_PATCHED_SHA256="$(agy_sha256 "$AGY_PATCHED")"
    VERIFIED_AT="$now"
    VERIFIED_ENTRYPOINT="agy"
    PATCHED_FROM_ORIGINAL_SHA256="$raw_sha"
    PATCHED_SHA256="$VERIFIED_PATCHED_SHA256"
    LAST_RAW_SHA256="$raw_sha"
    NEEDS_REPATCH=0
    LAST_SEEN_UPSTREAM_VERSION="$version"
    ACTIVE_TUPLE_ID="$tuple_id"
    VERIFIED_TUPLE_ID="$tuple_id"
    agy_write_state
    agy_registry_prune
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
    printf '  %-8s  %s\n' 'agy' 'Managed entrypoint; bare execution may refresh wrapper support and upstream binary.'
    printf '  %-8s  %s\n' 'setup' 'Refresh launcher/support files and ensure raw/runtime are ready.'
    printf '  %-8s  %s\n' 'update' 'Refresh wrapper support, update upstream binary, patch, and promote only after validation.'
    printf '  %-8s  %s\n' 'use' 'List cached, buildable, and remote tuples; run the selected combination.'
    printf '  %-8s  %s\n' 'profile' 'List numbered profiles or enter a named profile.'
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

agy_refresh_wrapper_support() {
    local display_mode="${1:-quiet}"
    local before after tmp_dir status target_version target_commit target
    [ "${AGY_DISABLE_WRAPPER_REFRESH:-0}" = "1" ] && return 0
    [ "${AGY_WRAPPER_REFRESHED:-0}" = "1" ] && return 0
    before="$(agy_current_wrapper_version)+$(agy_current_wrapper_commit)"
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/agy-wrapper.XXXXXX") || return 1
    if [ "$display_mode" != "quiet" ]; then
        printf 'agy: refreshing wrapper support...\n' >&2
    fi
    set +e
    git clone --quiet --depth 1 --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$tmp_dir/repo" 2>"$tmp_dir/refresh.log"
    status=$?
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/refresh.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi
    target_version="$(
        unset AGY_WRAPPER_VERSION AGY_WRAPPER_CHANNEL AGY_WRAPPER_COMMIT AGY_WRAPPER_REPO AGY_WRAPPER_INSTALLED_AT
        if [ -f "$tmp_dir/repo/config/wrapper-version.env" ]; then
            # shellcheck disable=SC1090
            . "$tmp_dir/repo/config/wrapper-version.env" 2>/dev/null || true
        fi
        printf '%s\n' "${AGY_WRAPPER_VERSION:-unknown}"
    )"
    target_commit="$(git -C "$tmp_dir/repo" rev-parse --short=6 HEAD 2>/dev/null || printf 'unknown\n')"
    target="$target_version+$target_commit"
    if [ "$target" = "$before" ]; then
        rm -rf "$tmp_dir"
        set -e
        return 0
    fi
    set +e
    (cd "$tmp_dir/repo" && AGY_SKIP_AUTO_UPDATE=1 bash ./bin/install-runtime.sh support) >>"$tmp_dir/refresh.log" 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        agy_make_case "$status" "$tmp_dir/refresh.log" >/dev/null
        rm -rf "$tmp_dir"
        return "$status"
    fi
    agy_reload_wrapper_version
    after="$(agy_current_wrapper_version)+$(agy_current_wrapper_commit)"
    rm -rf "$tmp_dir"
    if [ "$before" != "$after" ]; then
        return 10
    fi
    set -e
    return 0
}

agy_refresh_wrapper_and_reexec_if_needed() {
    local display_mode="$1"
    shift || true
    local status bash_path
    set +e
    agy_refresh_wrapper_support "$display_mode"
    status=$?
    set -e
    case "$status" in
        0)
            return 0
            ;;
        10)
            bash_path="${AGY_BASH:-$AGY_PREFIX/bin/bash}"
            if [ -x "$AGY_MANAGED_SHELL" ] && [ -x "$bash_path" ]; then
                export AGY_WRAPPER_REFRESHED=1
                exec "$bash_path" "$AGY_MANAGED_SHELL" "$@"
            fi
            return 0
            ;;
        *)
            if [ "$display_mode" != "quiet" ]; then
                printf 'agy: wrapper refresh failed; keeping current wrapper.\n' >&2
            fi
            return 0
            ;;
    esac
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

agy_remote_raw_candidates() {
    python3 - "$AGY_MANIFEST_URL" "$AGY_REMOTE_CANDIDATE_LIMIT" <<'PY'
import json
import re
import sys
from urllib.parse import urlencode
from urllib.request import urlopen

manifest_url = sys.argv[1]
limit = max(1, int(sys.argv[2] or "10"))
seen = set()
rows = []

def parse_version_key(v):
    parts = re.split(r"[.+-]", v)
    out = []
    for p in parts:
        out.append((0, int(p)) if p.isdigit() else (1, p))
    return out

def emit_manifest(url):
    try:
        with urlopen(url, timeout=6) as resp:
            manifest = json.load(resp)
    except Exception:
        return
    version = str(manifest.get("version", ""))
    platforms = manifest.get("platforms", {})
    linux_arm = platforms.get("linux-arm", {})
    raw_url = linux_arm.get("url", "") or manifest.get("url", "")
    sha512 = linux_arm.get("sha512", "") or manifest.get("sha512", "")
    if version and raw_url and sha512 and version not in seen:
        seen.add(version)
        rows.append((version, url, raw_url, sha512))

emit_manifest(manifest_url)

bucket_base = "https://storage.googleapis.com/storage/v1/b/antigravity-public/o"
page_token = ""
version_manifest_urls = {}
for _ in range(10):
    params = {"prefix": "antigravity-cli/", "maxResults": "1000"}
    if page_token:
        params["pageToken"] = page_token
    try:
        with urlopen(bucket_base + "?" + urlencode(params), timeout=6) as resp:
            bucket = json.load(resp)
    except Exception:
        break
    for item in bucket.get("items", []):
        name = item.get("name", "")
        m = re.match(r"antigravity-cli/([^/]+)/linux-arm/cli_linux_arm64\.tar\.gz$", name)
        if not m:
            continue
        version_build = m.group(1)
        version = version_build.split("-", 1)[0]
        version_manifest_urls.setdefault(version, f"https://storage.googleapis.com/antigravity-public/antigravity-cli/{version}/manifest.json")
    page_token = bucket.get("nextPageToken", "")
    if not page_token:
        break

for version in sorted(version_manifest_urls, key=parse_version_key, reverse=True):
    if len(rows) >= limit:
        break
    if version in seen:
        continue
    emit_manifest(version_manifest_urls[version])

for row in rows[:limit]:
    print("\t".join(row))
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
    agy_registry_record_current_wrapper
    if [ -z "$latest" ]; then
        printf 'agy: update manifest did not contain a version.\n' >"$tmp_dir/update.log"
        agy_make_case 73 "$tmp_dir/update.log" >/dev/null
        rm -rf "$tmp_dir"
        return 73
    fi

    if [ "$current" = "$latest" ] && [ -x "$AGY_RAW" ]; then
        agy_set_seen_upstream "$latest"
        agy_load_state
        agy_registry_bootstrap_from_current
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

    local url expected_sha actual_sha extracted candidate_raw candidate_runtime raw_backup runtime_backup case_dir build_status tuple_info
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
    agy_build_runtime_candidate "$candidate_raw" "$candidate_runtime" "$tmp_dir/build.log" "$(agy_current_wrapper_id)"
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
    if tuple_info="$(agy_registry_record_current_tuple "$latest" "$manifest_url" "remote" "$(date -Is)" "" "$expected_sha")"; then
        ACTIVE_TUPLE_ID="$(printf '%s\n' "$tuple_info" | awk -F'\t' '{print $3}')"
    fi
    agy_write_state
    agy_registry_prune
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
    marker_begin="# >>> agy termux path >>>"
    marker_end="# <<< agy termux path <<<"
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

# Obsolete cleanup policy:
# Older pre-release AGY installers created helper PATH shims outside the current
# managed Termux runtime surface. setup/support may remove only these fixed
# legacy file/link paths plus rc PATH blocks carrying AGY's explicit markers.
# Directories are skipped, and the current managed runtime/state roots are not
# removed by this cleanup path. Full managed runtime removal remains the job of
# `agy remove`.
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

agy_cleanup_obsolete_runtime_surface() {
    agy_remove_obsolete_control_shims
    agy_remove_rc_path_block "$AGY_HOME/.profile"
    agy_remove_rc_path_block "$AGY_HOME/.bashrc"
    agy_remove_rc_path_block "$AGY_HOME/.zshrc"
}

agy_remove_run() {
    printf 'agy remove: removing managed Termux runtime files...\n' >&2
    agy_remove_managed_launcher "$AGY_PREFIX/bin/agy"
    agy_cleanup_obsolete_runtime_surface
    agy_remove_tree "$AGY_TERMUX_ROOT"
    agy_remove_tree "$AGY_STATE_DIR"
    agy_remove_tree "$AGY_HOME/.local/glibc-shim"
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
    local failures=0 warnings=0 ok_count=0 idle_count=0
    local active patched_version interp resolver_counts etc_count fd33_count last_case_path last_build_profile current_raw_hash current_patched_hash
    local current_raw_hash current_patched_hash tuple_name tuple_id raw_id wrapper_id runtime_path
    local -a notes=()

    agy_doctor_ansi() {
        local code="$1" text="$2"
        if [ -t 1 ]; then
            printf '\033[%sm%s\033[0m' "$code" "$text"
        else
            printf '%s' "$text"
        fi
    }
    agy_doctor_std_ansi() {
        local code="$1" text="$2"
        if [ -t 1 ]; then
            printf '\033[%sm%s\033[39m' "$code" "$text"
        else
            printf '%s' "$text"
        fi
    }
    agy_doctor_bold() { agy_doctor_ansi 1 "$1"; }
    agy_doctor_dim() { agy_doctor_ansi 2 "$1"; }
    agy_doctor_green() { agy_doctor_std_ansi 32 "$1"; }
    agy_doctor_yellow() { agy_doctor_std_ansi 33 "$1"; }
    agy_doctor_red() { agy_doctor_std_ansi 31 "$1"; }
    agy_doctor_cyan240() {
        if [ -t 1 ]; then
            printf '\033[38;5;240m%s\033[39m' "$1"
        else
            printf '%s' "$1"
        fi
    }
    agy_doctor_blue117() {
        if [ -t 1 ]; then
            printf '\033[38;5;117m%s\033[39m' "$1"
        else
            printf '%s' "$1"
        fi
    }
    agy_doctor_ok() {
        ok_count=$((ok_count + 1))
        printf '  %s %-12s %s\n' "$(agy_doctor_green '✓')" "$(printf '%-12s' "$1")" "$(agy_doctor_dim "$2")"
    }
    agy_doctor_warn() {
        warnings=$((warnings + 1))
        notes+=("$1|$2")
        printf '  %s %-12s %s\n' "$(agy_doctor_yellow '⚠')" "$(printf '%-12s' "$1")" "$2"
    }
    agy_doctor_fail() {
        failures=$((failures + 1))
        printf '  %s %-12s %s\n' "$(agy_doctor_red '✗')" "$(printf '%-12s' "$1")" "$2"
    }
    agy_doctor_note_line() {
        printf '   %s %-12s %s\n' "$(agy_doctor_yellow '⚠')" "$1" "$2"
    }
    agy_doctor_detail() {
        printf '      %s %s\n' "$(agy_doctor_cyan240 "$(printf '%-24s' "$1")")" "$(agy_doctor_dim "$2")"
    }
    agy_doctor_path_detail() {
        printf '      %s %s\n' "$(agy_doctor_cyan240 "$(printf '%-24s' "$1")")" "$(agy_doctor_blue117 "$2")"
    }
    agy_doctor_section() {
        printf '\n%s\n' "$(agy_doctor_bold "$1")"
    }
    agy_doctor_divider() {
        printf '%s\n' "$(agy_doctor_dim '─────────────────────────────────────────────────────────────')"
    }
    patched_version="$(AGY_SKIP_AUTO_UPDATE=1 agy_run_candidate "$AGY_PATCHED" --version 2>/dev/null || true)"
    printf '%s %s\n' "$(agy_doctor_bold 'agy doctor')" "$(agy_doctor_dim "v${patched_version:-unknown} · Termux runtime")"
    agy_doctor_divider

    agy_doctor_section "Installation"
    active="$(command -v agy 2>/dev/null || true)"
    case "$active" in
        "$AGY_PREFIX/bin/agy")
            agy_doctor_ok "PATH" "resolves agy to managed entrypoint: $active"
            ;;
        "")
            agy_doctor_fail "PATH" 'agy is not on PATH'
            ;;
        *)
            agy_doctor_fail "PATH" "resolves agy to unexpected path: $active"
            ;;
    esac

    [ -x "$AGY_PREFIX/bin/agy" ] && agy_doctor_ok "launcher" "exists: $AGY_PREFIX/bin/agy" && agy_doctor_path_detail "path" "$AGY_PREFIX/bin/agy" || agy_doctor_fail "launcher" "missing or not executable: $AGY_PREFIX/bin/agy"
    [ -r "$AGY_RUNTIME_DIR/lib.sh" ] && agy_doctor_ok "runtime" "library installed: $AGY_RUNTIME_DIR/lib.sh" && agy_doctor_path_detail "path" "$AGY_RUNTIME_DIR/lib.sh" || agy_doctor_fail "runtime" "library missing: $AGY_RUNTIME_DIR/lib.sh"
    [ -x "$AGY_RUNTIME_BUILDER" ] && agy_doctor_ok "builder" "runtime builder installed: $AGY_RUNTIME_BUILDER" && agy_doctor_path_detail "path" "$AGY_RUNTIME_BUILDER" || agy_doctor_fail "builder" "runtime builder missing: $AGY_RUNTIME_BUILDER"
    [ -r "$AGY_RUNTIME_DIR/wrapper-version.env" ] && agy_doctor_ok "metadata" "wrapper metadata installed: $AGY_RUNTIME_DIR/wrapper-version.env" && agy_doctor_path_detail "path" "$AGY_RUNTIME_DIR/wrapper-version.env" || agy_doctor_warn "metadata" "wrapper metadata missing: $AGY_RUNTIME_DIR/wrapper-version.env"

    agy_doctor_section "Runtime"
    [ -x "$AGY_RAW" ] && agy_doctor_ok "raw" "upstream binary exists: $AGY_RAW" && agy_doctor_path_detail "binary" "$AGY_RAW" || agy_doctor_fail "raw" "upstream binary missing: $AGY_RAW"
    [ -x "$AGY_PATCHED" ] && agy_doctor_ok "patched" "runtime exists: $AGY_PATCHED" && agy_doctor_path_detail "runtime" "$AGY_PATCHED" || agy_doctor_fail "patched" "runtime missing: $AGY_PATCHED"
    [ -x "$AGY_LOADER" ] && agy_doctor_ok "loader" "glibc loader exists: $AGY_LOADER" && agy_doctor_path_detail "loader" "$AGY_LOADER" || agy_doctor_fail "loader" "glibc loader missing: $AGY_LOADER"
    [ -d "$AGY_GLIBC_LIB" ] && agy_doctor_ok "glibc" "library dir exists: $AGY_GLIBC_LIB" && agy_doctor_path_detail "lib dir" "$AGY_GLIBC_LIB" || agy_doctor_fail "glibc" "library dir missing: $AGY_GLIBC_LIB"

    agy_doctor_section "Environment"
    [ -f "$AGY_CERT_FILE" ] && agy_doctor_ok "ca" "bundle exists: $AGY_CERT_FILE" && agy_doctor_path_detail "bundle" "$AGY_CERT_FILE" || agy_doctor_fail "ca" "bundle missing: $AGY_CERT_FILE"
    [ -r "$AGY_RESOLV_CONF" ] && agy_doctor_ok "resolver" "source readable: $AGY_RESOLV_CONF" && agy_doctor_path_detail "source" "$AGY_RESOLV_CONF" || agy_doctor_fail "resolver" "source unreadable: $AGY_RESOLV_CONF"

    if agy_termux_resolver_ok; then
        agy_doctor_ok "resolver" "fd $AGY_RESOLVER_FD can be opened"
    else
        agy_doctor_fail "resolver" "fd $AGY_RESOLVER_FD cannot be opened from $AGY_RESOLV_CONF"
    fi

    if ! resolver_counts="$(agy_runtime_resolver_counts "$AGY_PATCHED" 2>/dev/null)"; then
        resolver_counts='missing missing'
    fi
    etc_count="$(printf '%s' "$resolver_counts" | awk '{print $1}')"
    fd33_count="$(printf '%s' "$resolver_counts" | awk '{print $2}')"
    if [ "$etc_count" = "0" ] && [ "$fd33_count" != "0" ] && [ "$fd33_count" != "missing" ]; then
        agy_doctor_ok "rewrite" "runtime resolver present (/etc=$etc_count fd33=$fd33_count)"
    else
        agy_doctor_fail "rewrite" "runtime resolver unexpected (/etc=$etc_count fd33=$fd33_count)"
    fi

    if command -v patchelf >/dev/null 2>&1 && [ -x "$AGY_PATCHED" ]; then
        interp="$(patchelf --print-interpreter "$AGY_PATCHED" 2>/dev/null || true)"
        [ "$interp" = "$AGY_LOADER" ] && agy_doctor_ok "interpreter" "runtime interpreter matches loader" || agy_doctor_fail "interpreter" "runtime interpreter mismatch: ${interp:-unknown}"
    else
        agy_doctor_warn "interpreter" 'patchelf unavailable or runtime missing; skipped interpreter check'
    fi

    if [ -x "$AGY_PATCHED" ] && [ -x "$AGY_LOADER" ] && [ -r "$AGY_RESOLV_CONF" ]; then
        patched_version="$(AGY_SKIP_AUTO_UPDATE=1 agy_run_candidate "$AGY_PATCHED" --version 2>/dev/null || true)"
        [ -n "$patched_version" ] && agy_doctor_ok "start" "patched runtime starts: $patched_version" || agy_doctor_fail 'start' 'patched runtime --version failed'
    fi

    agy_doctor_section "State"
    case "${LAST_KILL_SWITCH_STATUS:-}" in
        ok)
            agy_doctor_ok "kill-switch" "upstream update kill switch verified at ${LAST_KILL_SWITCH_AT:-unknown}"
            ;;
        failed)
            agy_doctor_warn "kill-switch" "upstream update kill switch failed or was unsupported${LAST_KILL_SWITCH_CASE:+: $LAST_KILL_SWITCH_CASE}"
            ;;
        *)
            agy_doctor_ok "kill-switch" 'upstream update kill switch status not recorded yet'
            ;;
    esac

    if agy_needs_repatch; then
        agy_doctor_warn "drift" 'state/runtime drift detected; run agy setup'
    else
        agy_doctor_ok "drift" 'state matches current raw/runtime hashes'
    fi

    last_case_path="$(agy_last_case_path 2>/dev/null || true)"
    if [ -n "$last_case_path" ] && [ -f "$last_case_path/build-report.json" ]; then
        last_build_profile="$(python3 - "$last_case_path/build-report.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    raise SystemExit(1)

profile = data.get("allocator_profile", "unknown")
missing = data.get("missing_required") or []
if missing:
    print(f"{profile} (missing: {', '.join(missing)})")
else:
    print(profile)
PY
)"
        if [ -n "$last_build_profile" ]; then
            agy_doctor_warn "build-profile" "last runtime build profile: $last_build_profile"
        fi
    fi

    if [ -n "${VERIFIED_AT:-}" ]; then
        current_raw_hash="$(agy_sha256 "$AGY_RAW")"
        current_patched_hash="$(agy_sha256 "$AGY_PATCHED")"
        if [ "${VERIFIED_ENTRYPOINT:-}" = "agy" ] \
            && [ "${VERIFIED_RAW_SHA256:-}" = "$current_raw_hash" ] \
            && [ "${VERIFIED_PATCHED_SHA256:-}" = "$current_patched_hash" ]; then
            agy_doctor_ok "tuple" "last successful agy runtime tuple matches current files: $VERIFIED_AT"
        else
            agy_doctor_warn "tuple" 'last successful agy runtime tuple differs from current files'
        fi
    else
        agy_doctor_ok "tuple" 'last successful agy runtime tuple not recorded yet'
    fi

    agy_doctor_section "Registry"
    if [ -f "$AGY_REGISTRY_FILE" ]; then
        agy_doctor_ok "registry" "file exists: $AGY_REGISTRY_FILE"
        for tuple_name in ACTIVE_TUPLE_ID PREFERRED_TUPLE_ID VERIFIED_TUPLE_ID; do
            tuple_id="${!tuple_name:-}"
            [ -z "$tuple_id" ] && continue
            raw_id="$(agy_registry_runtime_field "$tuple_id" raw_id)"
            wrapper_id="$(agy_registry_runtime_field "$tuple_id" wrapper_id)"
            runtime_path="$(agy_registry_runtime_field "$tuple_id" path)"
            if [ -n "$raw_id" ] && [ -n "$wrapper_id" ] && [ -x "$runtime_path" ]; then
                agy_doctor_ok "$tuple_name" "registry tuple exists: $tuple_id"
            else
                agy_doctor_warn "$tuple_name" "registry tuple incomplete or missing runtime: $tuple_id"
            fi
        done
    else
        agy_doctor_warn "registry" "file missing: $AGY_REGISTRY_FILE"
    fi

    [ -f "$AGY_STATE_FILE" ] && agy_doctor_ok "state" "file exists: $AGY_STATE_FILE" || agy_doctor_warn "state" "file missing: $AGY_STATE_FILE"
    if [ "${#notes[@]}" -gt 0 ]; then
        printf '\n%s\n' "$(agy_doctor_bold 'Notes')"
        for note in "${notes[@]}"; do
            IFS='|' read -r note_name note_text <<EOF
$note
EOF
            agy_doctor_note_line "$note_name" "$note_text"
        done
    fi
    agy_doctor_divider
    if [ "$failures" -gt 0 ]; then
        summary_status="fail"
        summary_tail="$(agy_doctor_bold "$(agy_doctor_red 'fail')")"
    elif [ "$warnings" -gt 0 ]; then
        summary_status="warn"
        summary_tail="$(agy_doctor_bold "$(agy_doctor_yellow 'warn')")"
    else
        summary_status="ok"
        summary_tail="$(agy_doctor_bold "$(agy_doctor_green 'ok')")"
    fi
    printf '%s %s · %s %s · %s %s · %s %s %s\n' \
        "$(agy_doctor_dim "$ok_count")" "$(agy_doctor_green 'ok')" \
        "$(agy_doctor_dim "$idle_count")" "$(agy_doctor_dim 'idle')" \
        "$(agy_doctor_dim "$warnings")" "$(agy_doctor_yellow 'warn')" \
        "$(agy_doctor_dim "$failures")" "$(agy_doctor_red 'fail')" \
        "$summary_tail"
    [ "$failures" -eq 0 ]
}

agy_main() {
    local first="${1:-}"
    local mode

    mode="$(agy_mode_for_args "$first")"

    case "$mode" in
        setup)
            shift || true
            agy_bootstrap_setup
            return $?
            ;;
        update)
            agy_refresh_wrapper_and_reexec_if_needed run update
            agy_preflight || return $?
            agy_update_broker explicit || return $?
            agy_version_report
            return $?
            ;;
        profile)
            shift || true
            agy_profile_run "$@"
            return $?
            ;;
        use)
            shift || true
            agy_use "$@"
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
        agy_run_bare_runtime "$@"
        return $?
    fi

    agy_cheap_launch_guard || return $?
    set +e
    agy_load_state
    agy_runtime_command "$AGY_PATCHED" "$@"
    exit_code=$?
    set -e
    return "$exit_code"
}
