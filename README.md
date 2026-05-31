# agy native Termux runtime

This repository installs the official Linux ARM64 Antigravity CLI (`agy`) for
Termux through a single public command at `$PREFIX/bin/agy`.

## Install

Run the bootstrap installer from Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

Re-running the same command is safe. It refreshes the managed launcher and
runtime support from the current `main` branch and ensures the local runtime is
usable.

## Public commands

| Command | Role |
| :--- | :--- |
| `agy` | Normal CLI entrypoint. Bare execution performs light preflight and may refresh the upstream binary when needed. |
| `agy setup` | Refresh managed launcher/support files from `main` and ensure raw/runtime are ready. |
| `agy update` | Update the official upstream `agy` binary only. |
| `agy doctor` | Check PATH, launcher, raw/runtime, loader, resolver, CA, and state. |
| `agy info` | Print compact upstream and wrapper version info. |
| `agy version` | Print the upstream `agy --version` output only. |
| `agy remove --yes` | Remove the managed launcher, runtime, raw copy, state, and legacy shims. |

## Files

```text
~/.local/lib/agy/native/raw/agy
~/.local/lib/agy/native/runtime/agy
~/.local/lib/agy/native/runtime/managed.sh
~/.local/lib/agy/native/runtime/lib.sh
~/.local/lib/agy/native/runtime/build-runtime.py
~/.local/lib/agy/native/runtime/wrapper-version.env
~/.local/share/agy/native/state.json
$PREFIX/bin/agy
```

## Rules

- The raw official binary is never patched in place.
- The managed launcher lives at `$PREFIX/bin/agy`; no extra PATH shim is created.
- No repo-pinned verified version file is shipped. Verified version state is
  recorded locally after successful runs.
- `agy update` is the only upstream binary update path.
- `agy setup` is the recovery path for launcher/support refresh and runtime
  re-ensuring.

## Troubleshooting

1. Run `agy doctor`.
2. If launcher/support files are stale or missing, run `agy setup`.
3. If the upstream binary itself needs updating, run `agy update`.
4. If removing, use `agy remove --yes`.

## Guides

- [Native runtime guide](docs/AGY_TERMUX_NATIVE_GUIDE.md)
- [Compiled launcher guide](docs/AGY_TERMUX_COMPILED_LAUNCHER.md)
