#!/usr/bin/env bash
set -euo pipefail

AGY_REPO_URL="${AGY_REPO_URL:-https://github.com/humtr/agy.git}"
AGY_BRANCH="${AGY_BRANCH:-main}"
AGY_INSTALL_ROOT="${AGY_INSTALL_ROOT:-$HOME/prj/agy}"
AGY_INSTALL_DRY_RUN="${AGY_INSTALL_DRY_RUN:-0}"
AGY_KEEP_SOURCE="${AGY_KEEP_SOURCE:-0}"
AGY_REQUIRED_PACKAGES="${AGY_REQUIRED_PACKAGES:-git curl python tar patchelf coreutils ca-certificates proot}"
AGY_GLIBC_PACKAGES="${AGY_GLIBC_PACKAGES:-glibc-repo glibc glibc-runner}"
AGY_TEMP_REPO=""
AGY_REPO_PATH=""

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
    if ! run pkg install -y "${missing[@]}"; then
        fail "dependency install failed. Retry manually: pkg install -y ${missing[*]}"
    fi
}

check_glibc() {
    local loader="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
    local libc="$PREFIX/glibc/lib/libc.so.6"
    if [ -x "$loader" ] && [ -f "$libc" ]; then
        say 'glibc runtime prerequisite is present'
        return 0
    fi

    say "installing Termux glibc packages: $AGY_GLIBC_PACKAGES"
    if run pkg install -y $AGY_GLIBC_PACKAGES; then
        if [ -x "$loader" ] && [ -f "$libc" ]; then
            say 'glibc runtime prerequisite is present'
            return 0
        fi
    fi

    cat >&2 <<EOF
agy install: ERROR: Termux glibc runtime is missing.

Required:
  $loader
  $libc

The installer tried:

  pkg install -y $AGY_GLIBC_PACKAGES

If that failed, run:

  termux-change-repo
  pkg update
  pkg install -y $AGY_GLIBC_PACKAGES

Then rerun this installer.
EOF
    exit 1
}

prepare_repo() {
    if [ -f "./bin/install-runtime.sh" ] && [ -f "./lib/agy-termux-lib.sh" ]; then
        AGY_REPO_PATH=$(pwd)
        return 0
    fi

    if [ "$AGY_KEEP_SOURCE" != "1" ]; then
        AGY_TEMP_REPO=$(mktemp -d "${TMPDIR:-/tmp}/agy-install.XXXXXX") || fail 'failed to create temporary source directory'
        say "cloning temporary installer source"
        run git clone --depth 1 --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$AGY_TEMP_REPO" || fail "failed to clone $AGY_REPO_URL"
        if [ "$AGY_INSTALL_DRY_RUN" != "1" ]; then
            [ -f "$AGY_TEMP_REPO/bin/install-runtime.sh" ] || fail "missing installer after clone: $AGY_TEMP_REPO/bin/install-runtime.sh"
        fi
        AGY_REPO_PATH="$AGY_TEMP_REPO"
        return 0
    fi

    if [ -d "$AGY_INSTALL_ROOT/.git" ]; then
        say "updating repo at $AGY_INSTALL_ROOT"
        run git -C "$AGY_INSTALL_ROOT" fetch --prune origin || fail "failed to fetch $AGY_REPO_URL"
        run git -C "$AGY_INSTALL_ROOT" checkout "$AGY_BRANCH" || fail "failed to checkout $AGY_BRANCH"
        run git -C "$AGY_INSTALL_ROOT" pull --ff-only origin "$AGY_BRANCH" || fail "failed to fast-forward $AGY_INSTALL_ROOT"
    elif [ -e "$AGY_INSTALL_ROOT" ]; then
        cat >&2 <<EOF
agy install: ERROR: $AGY_INSTALL_ROOT already exists but is not an agy Git checkout.

Move it aside, then rerun this installer:

  mv "$AGY_INSTALL_ROOT" "$AGY_INSTALL_ROOT.backup-\$(date +%Y%m%d-%H%M%S)"

Or install without keeping source by leaving AGY_KEEP_SOURCE unset.
EOF
        exit 1
    else
        say "cloning repo to $AGY_INSTALL_ROOT"
        run mkdir -p "$(dirname "$AGY_INSTALL_ROOT")" || fail "failed to create $(dirname "$AGY_INSTALL_ROOT")"
        run git clone --branch "$AGY_BRANCH" "$AGY_REPO_URL" "$AGY_INSTALL_ROOT" || fail "failed to clone $AGY_REPO_URL"
    fi
    [ -f "$AGY_INSTALL_ROOT/bin/install-runtime.sh" ] || fail "missing installer after repo setup: $AGY_INSTALL_ROOT/bin/install-runtime.sh"
    AGY_REPO_PATH="$AGY_INSTALL_ROOT"
}

main() {
    need_termux
    install_dependencies
    check_glibc

    prepare_repo
    say "installing runtime from $AGY_REPO_PATH"
    run bash "$AGY_REPO_PATH/bin/install-runtime.sh" --install

    if [ "$AGY_INSTALL_DRY_RUN" = "1" ]; then
        say 'dry run complete'
        return 0
    fi

    if ! command -v agy >/dev/null 2>&1; then
        fail 'agy wrapper was not installed onto PATH. Ensure ~/bin is on PATH.'
    fi
    AGY_SKIP_AUTO_UPDATE=1 agy --version
    say 'install complete'
}

main "$@"
