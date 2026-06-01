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
| `agy help` | Show native help first, then wrapper help below it. |
| `agy profile` | List available profiles or enter one by name. |
| `agy profile NAME` | Enter the named profile and run the bare CLI in that profile home. |
| `agy setup` | Refresh managed launcher/support files from `main`, ensure raw/runtime are ready, and print `agy :` / `wrapper :` version rows. |
| `agy update` | Update the official upstream `agy` binary only, then print `agy :` / `wrapper :` version rows. |
| `agy doctor` | Check PATH, launcher, raw/runtime, loader, resolver, CA, and state. |
| `agy version` | Print `agy :` and `wrapper :` version rows. |
| `agy remove` | Remove the managed launcher, runtime, raw copy, state, and obsolete shims. |

## Files

```text
~/.local/lib/agy/native/raw/agy
~/.local/lib/agy/native/runtime/agy
~/.local/lib/agy/native/runtime/managed.sh
~/.local/lib/agy/native/runtime/lib.sh
~/.local/lib/agy/native/runtime/build-runtime.py
~/.local/lib/agy/native/runtime/wrapper-version.env
~/.local/share/agy/native/state.json
~/.agy-profiles/
$PREFIX/bin/agy
```

## Rules

- The raw official binary is never patched in place.
- The managed launcher lives at `$PREFIX/bin/agy`; no extra PATH shim is created.
- No repo-pinned verified version file is shipped. The last successful bare
  `agy` runtime tuple is recorded locally after a normal exit.
- `AGY_PROFILE_HOME` can redirect the runtime auth/session home for
  `agy profile NAME`; profile directories live under `~/.agy-profiles/` by
  default.
- `agy update` is the only upstream binary update path.
- `agy setup` is the recovery path for launcher/support refresh and runtime
  re-ensuring.

## Troubleshooting

1. Run `agy doctor`.
2. If launcher/support files are stale or missing, run `agy setup`.
3. If you want a separate auth/session home, create a directory under
   `~/.agy-profiles/` and use `agy profile NAME`.
4. If the upstream binary itself needs updating, run `agy update`.
5. If removing, use `agy remove`.

## Guides

- [Native runtime guide](docs/AGY_TERMUX_NATIVE_GUIDE.md)
- [Compiled launcher guide](docs/AGY_TERMUX_COMPILED_LAUNCHER.md)
