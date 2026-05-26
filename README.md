# AGY Termux Native Wrapper

Termux-native installer and wrapper for running the official Linux ARM64
Antigravity CLI (`agy`) on Android.

The wrapper keeps the official raw binary separate from the generated runtime
copy, checks updates before normal runs, rebuilds the runtime copy when needed,
and preserves auth state. Authentication is manual and is never run by the
installer.

## Install

Run this in a fresh Termux environment after storage/network setup:

```sh
pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

The installer:

- installs ordinary Termux dependencies with `pkg`
- verifies that a Termux glibc runtime is already present
- clones or updates this repo at `~/prj/agy`
- installs `~/bin/agy`
- downloads the official Linux ARM64 `agy` binary through the wrapper broker
- builds and validates the runtime copy
- runs `agy --version`

The installer does not bootstrap glibc automatically. If glibc is missing, it
prints the required paths and a suggested Termux package command, then exits.

## Verified Fallback Version

Default installs use the current official Linux ARM64 updater manifest. For an
explicit install or `agy update`, if the current manifest path fails, the wrapper
can retry the official versioned manifest recorded in:

```text
config/verified-agy-version.env
```

This fallback applies only to the official `agy` binary version. Wrapper code
does not auto-rollback. Wrapper releases are managed by Git commits and tags,
and broken wrapper code should be fixed or reverted in Git before publishing.

When a newer official `agy` version is confirmed to work on Termux, update
`AGY_VERIFIED_FALLBACK_VERSION` in that file and commit the change.

## Normal Use

```sh
agy
agy --version
agy update
agy termux
```

`agy termux` is the management and diagnostic menu.

## Fresh Phone Verification

After installing on another Android phone, run:

```sh
agy --version
printf '8\n' | agy termux
AGY_RESOLVER_MODE=native agy auth login
AGY_RESOLVER_MODE=native AGY_SKIP_AUTO_UPDATE=1 agy --print 'Reply with exactly: AGY_TERMUX_NATIVE_OK'
```

The `auth login` step is user-driven. Do not paste OAuth callback URLs, codes,
cookies, or tokens into diagnostics or chat.

If native resolver mode fails but the runtime otherwise installed correctly,
try:

```sh
AGY_RESOLVER_MODE=proot AGY_SKIP_AUTO_UPDATE=1 agy --version
```

## Manual Repo Install

```sh
pkg install -y git curl python tar patchelf coreutils ca-certificates proot
git clone https://github.com/humtr/agy.git ~/prj/agy
cd ~/prj/agy
bash bin/install-runtime.sh --install
```

## Architecture

- `~/.local/bin/agy`: raw official binary
- `~/.local/lib/agy-termux/agy`: generated runtime copy
- `~/.local/lib/agy-termux/run`: execution wrapper
- `~/.local/lib/agy-termux/lib.sh`: installed support library
- `~/bin/agy`: user entrypoint
- `~/.local/share/agy-termux/state.env`: hash/state file
- `~/.local/share/agy-termux/doctor`: diagnostic cases

See `docs/AGY_TERMUX_NATIVE_GUIDE.md` for the detailed runtime model.
