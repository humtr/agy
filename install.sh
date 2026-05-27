#!/usr/bin/env bash
set -euo pipefail

AGY_REPO_URL="${AGY_REPO_URL:-https://github.com/humtr/agy.git}"
AGY_BRANCH="${AGY_BRANCH:-main}"
AGY_INSTALL_ROOT="${AGY_INSTALL_ROOT:-$HOME/prj/agy}"
AGY_INSTALL_DRY_RUN="${AGY_INSTALL_DRY_RUN:-0}"
AGY_KEEP_SOURCE="${AGY_KEEP_SOURCE:-0}"
AGY_REQUIRED_PACKAGES="${AGY_REQUIRED_PACKAGES:-git curl python tar patchelf coreutils ca-certificates proot}"
AGY_GLIBC_REPO_PACKAGE="${AGY_GLIBC_REPO_PACKAGE:-glibc-repo}"
AGY_GLIBC_PACKAGES="${AGY_GLIBC_PACKAGES:-glibc glibc-runner}"
AGY_TEMP_REPO=""
AGY_REPO_PATH=""
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

cleanup() {
    if [ -n "$AGY_TEMP_REPO" ]; then
        rm -rf "$AGY_TEMP_REPO"
    fi
}
trap cleanup EXIT

say() {
    printf 'agy install: %s\n' "$*" >&2
}

run() {
    if [ "$AGY_INSTALL_DRY_RUN" = "1" ]; then
        printf '+ %s\n' "$*" >&2
    else
        "$@" || return $?
    fi
}

pkg_update() {
    run pkg update -y
}

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

install_dependencies() {
    local missing=()
    local package
    for package in $AGY_REQUIRED_PACKAGES; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        say 'required Termux packages are present'
        return 0
    fi

    say "installing missing Termux packages: ${missing[*]}"
    if ! pkg_install "${missing[@]}"; then
        fail "dependency install failed. Retry manually: apt-get install -y ${missing[*]}"
    fi
}

check_glibc() {
    local loader="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
    local libc="$PREFIX/glibc/lib/libc.so.6"
    if [ -x "$loader" ] && [ -f "$libc" ]; then
        say 'glibc runtime prerequisite is present'
        return 0
    fi

    say "installing Termux glibc repository package: $AGY_GLIBC_REPO_PACKAGE"
    if ! pkg_install "$AGY_GLIBC_REPO_PACKAGE"; then
        fail "glibc repository install failed. Retry manually: apt-get install -y $AGY_GLIBC_REPO_PACKAGE"
    fi

    say 'refreshing package lists after enabling glibc repository'
    if ! pkg_update; then
        fail 'pkg update failed after enabling the glibc repository. Run termux-change-repo, then retry.'
    fi

    say "installing Termux glibc runtime packages: $AGY_GLIBC_PACKAGES"
    if pkg_install $AGY_GLIBC_PACKAGES; then
        if [ -x "$loader" ] && [ -f "$libc" ]; then
            say 'glibc runtime prerequisite is present'
            return 0
        fi
    fi
    fail "Termux glibc runtime is missing. expected: $loader and $libc"
}

prepare_repo() {
    if [ -f "./bin/install-runtime.sh" ] && [ -f "./lib/agy-termux-lib.sh" ]; then
        AGY_REPO_PATH=$(pwd)
        return 0
    fi

    if [ "$AGY_KEEP_SOURCE" != "1" ]; then
        AGY_TEMP_REPO=$(mktemp -d "${TMPDIR:-/tmp}/agy-install.XXXXXX") || fail 'failed to create temporary source directory'
        say "cloning temporary source"
        run git clone --depth 1 --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$AGY_TEMP_REPO" || fail "failed to clone $AGY_REPO_URL"
        AGY_REPO_PATH="$AGY_TEMP_REPO"
        return 0
    fi

    if [ -d "$AGY_INSTALL_ROOT/.git" ]; then
        say "updating repo at $AGY_INSTALL_ROOT"
        run git -C "$AGY_INSTALL_ROOT" fetch --prune origin || fail "failed to fetch $AGY_REPO_URL"
        run git -C "$AGY_INSTALL_ROOT" checkout "$AGY_BRANCH" || fail "failed to checkout $AGY_BRANCH"
        run git -C "$AGY_INSTALL_ROOT" pull --ff-only origin "$AGY_BRANCH" || fail "failed to fast-forward $AGY_INSTALL_ROOT"
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
    prepare_repo
    run bash "$AGY_REPO_PATH/bin/install-runtime.sh" --install
    if [ "$AGY_INSTALL_DRY_RUN" != "1" ]; then
        AGY_SKIP_AUTO_UPDATE=1 "$HOME/bin/agy" --version
    fi
}

main "$@"
