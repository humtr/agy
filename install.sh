#!/usr/bin/env bash
set -euo pipefail

AGY_REPO_URL="${AGY_REPO_URL:-https://github.com/humtr/agy.git}"
AGY_BRANCH="${AGY_BRANCH:-main}"
AGY_INSTALL_ROOT="${AGY_INSTALL_ROOT:-$HOME/prj/agy}"
AGY_SOURCE_CACHE="${AGY_SOURCE_CACHE:-$HOME/.local/share/agy/native/source/main}"
AGY_INSTALL_DRY_RUN="${AGY_INSTALL_DRY_RUN:-0}"
AGY_KEEP_SOURCE="${AGY_KEEP_SOURCE:-0}"
AGY_USE_CWD_SOURCE="${AGY_USE_CWD_SOURCE:-0}"
AGY_SYNC_ONLY="${AGY_SYNC_ONLY:-0}"
AGY_REQUIRED_PACKAGES="${AGY_REQUIRED_PACKAGES:-git curl python tar patchelf coreutils ca-certificates proot}"
AGY_GLIBC_REPO_PACKAGE="${AGY_GLIBC_REPO_PACKAGE:-glibc-repo}"
AGY_GLIBC_PACKAGES="${AGY_GLIBC_PACKAGES:-glibc glibc-runner}"
AGY_NATIVE_ROOT="${AGY_NATIVE_ROOT:-$HOME/.local/lib/agy/native}"
AGY_RUNTIME_DIR="${AGY_RUNTIME_DIR:-$AGY_NATIVE_ROOT/runtime}"
AGY_VERSION_FILE="${AGY_VERSION_FILE:-$AGY_RUNTIME_DIR/wrapper-version.env}"
AGY_REPO_PATH=""
CURRENT_WRAPPER_VERSION="not-installed"
CURRENT_WRAPPER_COMMIT="unknown"
LATEST_WRAPPER_VERSION="unknown"
LATEST_WRAPPER_COMMIT="unknown"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

if [ "${AGY_MANAGED_MODE:-}" = "sync" ]; then
    AGY_SYNC_ONLY=1
fi

say() { printf 'agy install: %s\n' "$*" >&2; }

run() {
    if [ "$AGY_INSTALL_DRY_RUN" = "1" ]; then
        printf '+ %s\n' "$*" >&2
    else
        "$@" || return $?
    fi
}

pkg_update() { run pkg update -y; }

pkg_install() {
    run apt-get install -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"
}

fail() {
    printf 'agy install: ERROR: %s\n' "$*" >&2
    exit 1
}

need_termux() {
    [ -n "${PREFIX:-}" ] || fail 'PREFIX is not set. Run this inside Termux.'
    [ -x "$PREFIX/bin/pkg" ] || fail 'Termux pkg command not found.'
}

load_current_wrapper() {
    CURRENT_WRAPPER_VERSION="not-installed"
    CURRENT_WRAPPER_COMMIT="unknown"
    unset AGY_WRAPPER_VERSION AGY_WRAPPER_CHANNEL AGY_WRAPPER_COMMIT AGY_WRAPPER_REPO AGY_WRAPPER_INSTALLED_AT
    if [ -f "$AGY_VERSION_FILE" ]; then
        # shellcheck disable=SC1090
        . "$AGY_VERSION_FILE"
        CURRENT_WRAPPER_VERSION="${AGY_WRAPPER_VERSION:-unknown}"
        CURRENT_WRAPPER_COMMIT="${AGY_WRAPPER_COMMIT:-unknown}"
    fi
}

load_latest_wrapper() {
    local latest_file="$AGY_REPO_PATH/config/wrapper-version.env"
    LATEST_WRAPPER_VERSION="unknown"
    LATEST_WRAPPER_COMMIT="unknown"
    unset AGY_WRAPPER_VERSION AGY_WRAPPER_CHANNEL AGY_WRAPPER_COMMIT AGY_WRAPPER_REPO AGY_WRAPPER_INSTALLED_AT
    if [ -f "$latest_file" ]; then
        # shellcheck disable=SC1090
        . "$latest_file"
        LATEST_WRAPPER_VERSION="${AGY_WRAPPER_VERSION:-unknown}"
    fi
    if command -v git >/dev/null 2>&1 && git -C "$AGY_REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        LATEST_WRAPPER_COMMIT="$(git -C "$AGY_REPO_PATH" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
    fi
}

rev() { printf '%s (%s)' "$1" "$2"; }

install_dependencies() {
    local missing=() package
    for package in $AGY_REQUIRED_PACKAGES; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        say 'dependencies ok'
        return 0
    fi
    say "installing dependencies: ${missing[*]}"
    pkg_install "${missing[@]}" || fail "dependency install failed. Retry manually: apt-get install -y ${missing[*]}"
}

check_glibc() {
    local loader="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
    local libc="$PREFIX/glibc/lib/libc.so.6"
    if [ -x "$loader" ] && [ -f "$libc" ]; then
        say 'glibc ok'
        return 0
    fi
    say 'installing glibc support'
    pkg_install "$AGY_GLIBC_REPO_PACKAGE" || fail "glibc repository install failed. Retry manually: apt-get install -y $AGY_GLIBC_REPO_PACKAGE"
    pkg_update || fail 'pkg update failed after enabling the glibc repository. Run termux-change-repo, then retry.'
    pkg_install $AGY_GLIBC_PACKAGES || fail "Termux glibc runtime is missing. expected: $loader and $libc"
    [ -x "$loader" ] && [ -f "$libc" ] || fail "Termux glibc runtime is missing. expected: $loader and $libc"
    say 'glibc ok'
}

prepare_source_cache() {
    local cache_parent
    cache_parent="$(dirname "$AGY_SOURCE_CACHE")"
    run mkdir -p "$cache_parent" || fail 'failed to create source cache parent'
    if [ -d "$AGY_SOURCE_CACHE/.git" ]; then
        say 'source cache refreshing'
        run git -C "$AGY_SOURCE_CACHE" fetch --depth 1 origin "$AGY_BRANCH" || fail "failed to fetch $AGY_REPO_URL"
        run git -C "$AGY_SOURCE_CACHE" checkout -B "$AGY_BRANCH" FETCH_HEAD >/dev/null 2>&1 || fail "failed to checkout $AGY_BRANCH"
    elif [ -e "$AGY_SOURCE_CACHE" ]; then
        fail "source cache exists but is not a git repository: $AGY_SOURCE_CACHE"
    else
        say 'source cache cloning'
        run git clone --depth 1 --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$AGY_SOURCE_CACHE" || fail "failed to clone $AGY_REPO_URL"
    fi
    AGY_REPO_PATH="$AGY_SOURCE_CACHE"
}

prepare_repo() {
    if [ "$AGY_USE_CWD_SOURCE" = "1" ] && [ -f "./bin/install-runtime.sh" ] && [ -f "./lib/agy-termux-lib.sh" ]; then
        AGY_REPO_PATH=$(pwd)
        say 'source current-working-tree'
        return 0
    fi
    if [ "$AGY_KEEP_SOURCE" != "1" ]; then
        prepare_source_cache
        return 0
    fi
    if [ -d "$AGY_INSTALL_ROOT/.git" ]; then
        say 'source repo refreshing'
        run git -C "$AGY_INSTALL_ROOT" fetch --prune origin || fail "failed to fetch $AGY_REPO_URL"
        run git -C "$AGY_INSTALL_ROOT" checkout "$AGY_BRANCH" >/dev/null 2>&1 || fail "failed to checkout $AGY_BRANCH"
        run git -C "$AGY_INSTALL_ROOT" pull --ff-only origin "$AGY_BRANCH" >/dev/null || fail "failed to fast-forward $AGY_INSTALL_ROOT"
    else
        run mkdir -p "$(dirname "$AGY_INSTALL_ROOT")" || fail "failed to create $(dirname "$AGY_INSTALL_ROOT")"
        run git clone --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$AGY_INSTALL_ROOT" || fail "failed to clone $AGY_REPO_URL"
    fi
    AGY_REPO_PATH="$AGY_INSTALL_ROOT"
}

main() {
    need_termux
    install_dependencies
    check_glibc
    load_current_wrapper
    prepare_repo
    load_latest_wrapper

    if [ "$CURRENT_WRAPPER_VERSION" = "not-installed" ]; then
        say "wrapper install -> $(rev "$LATEST_WRAPPER_VERSION" "$LATEST_WRAPPER_COMMIT")"
    elif [ "$CURRENT_WRAPPER_VERSION" = "$LATEST_WRAPPER_VERSION" ] && [ "$CURRENT_WRAPPER_COMMIT" = "$LATEST_WRAPPER_COMMIT" ]; then
        say "wrapper overwrite $(rev "$LATEST_WRAPPER_VERSION" "$LATEST_WRAPPER_COMMIT")"
    else
        say "wrapper update $(rev "$CURRENT_WRAPPER_VERSION" "$CURRENT_WRAPPER_COMMIT") -> $(rev "$LATEST_WRAPPER_VERSION" "$LATEST_WRAPPER_COMMIT")"
    fi

    if [ "$AGY_SYNC_ONLY" = "1" ]; then
        run bash "$AGY_REPO_PATH/bin/install-runtime.sh" --install-wrappers
    else
        run bash "$AGY_REPO_PATH/bin/install-runtime.sh" --install
    fi
    load_current_wrapper
    say "wrapper installed $(rev "$CURRENT_WRAPPER_VERSION" "$CURRENT_WRAPPER_COMMIT")"
    if [ "$AGY_INSTALL_DRY_RUN" != "1" ]; then
        AGY_SKIP_AUTO_UPDATE=1 "$HOME/bin/agy" info >/dev/null
        say 'verified; use agy repair for local runtime repair'
    fi
}

main "$@"
