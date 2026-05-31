#!/usr/bin/env bash
set -euo pipefail

AGY_REPO_URL="${AGY_REPO_URL:-https://github.com/humtr/agy.git}"
AGY_BRANCH="${AGY_BRANCH:-main}"
AGY_USE_CWD_SOURCE="${AGY_USE_CWD_SOURCE:-0}"
AGY_REQUIRED_PACKAGES="${AGY_REQUIRED_PACKAGES:-git curl python tar patchelf coreutils ca-certificates proot}"
AGY_GLIBC_REPO_PACKAGE="${AGY_GLIBC_REPO_PACKAGE:-glibc-repo}"
AGY_GLIBC_PACKAGES="${AGY_GLIBC_PACKAGES:-glibc glibc-runner}"
AGY_LOG_PREFIX="agy setup"
AGY_REPO_PATH=""
AGY_TMP_DIR=""
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

say() {
    printf '%s: %s\n' "$AGY_LOG_PREFIX" "$*" >&2
}

fail() {
    printf '%s: ERROR: %s\n' "$AGY_LOG_PREFIX" "$*" >&2
    exit 1
}

need_termux() {
    [ -n "${PREFIX:-}" ] || fail 'PREFIX is not set. Run this inside Termux.'
    [ -x "$PREFIX/bin/pkg" ] || fail 'Termux pkg command not found.'
}

pkg_update() {
    pkg update -y
}

pkg_install() {
    apt-get install -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"
}

install_dependencies() {
    local missing=() package
    for package in $AGY_REQUIRED_PACKAGES; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    say "installing dependencies: ${missing[*]}"
    pkg_install "${missing[@]}" || fail "dependency install failed: ${missing[*]}"
}

check_glibc() {
    local loader="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
    local libc="$PREFIX/glibc/lib/libc.so.6"
    if [ -x "$loader" ] && [ -f "$libc" ]; then
        return 0
    fi
    say 'installing glibc support'
    pkg_install "$AGY_GLIBC_REPO_PACKAGE" || fail "glibc repository install failed: $AGY_GLIBC_REPO_PACKAGE"
    pkg_update || fail 'pkg update failed after enabling the glibc repository'
    pkg_install $AGY_GLIBC_PACKAGES || fail "Termux glibc runtime is missing: $loader and $libc"
    [ -x "$loader" ] && [ -f "$libc" ] || fail "Termux glibc runtime is missing: $loader and $libc"
}

prepare_repo() {
    if [ "$AGY_USE_CWD_SOURCE" = "1" ]; then
        if [ -f "./bin/install-runtime.sh" ] && [ -f "./lib/agy-termux-lib.sh" ]; then
            AGY_REPO_PATH="$(pwd)"
            return 0
        fi
        fail 'AGY_USE_CWD_SOURCE=1 but the current directory is not an agy checkout'
    fi

    if [ "$AGY_USE_CWD_SOURCE" != "0" ]; then
        fail 'AGY_USE_CWD_SOURCE must be 0 or 1'
    fi

    AGY_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agy-install.XXXXXX")" || fail 'failed to create temporary directory'
    trap 'rm -rf "$AGY_TMP_DIR"' EXIT INT TERM
    say "cloning $AGY_REPO_URL"
    git clone --quiet --depth 1 --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$AGY_TMP_DIR/repo" \
        || fail "failed to clone $AGY_REPO_URL"
    AGY_REPO_PATH="$AGY_TMP_DIR/repo"
}

verify_install() {
    if [ ! -x "$PREFIX/bin/agy" ] && [ ! -f "$PREFIX/bin/agy" ]; then
        fail "launcher missing after setup: $PREFIX/bin/agy"
    fi
    AGY_SKIP_AUTO_UPDATE=1 "$PREFIX/bin/agy" version >/dev/null || fail 'agy version failed after setup'
}

main() {
    need_termux
    say 'checking'
    install_dependencies
    check_glibc
    say 'fetching'
    prepare_repo
    say 'setting up'
    bash "$AGY_REPO_PATH/bin/install-runtime.sh" setup
    say 'verifying'
    verify_install
    say 'ok'
}

main "$@"
