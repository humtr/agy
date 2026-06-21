# agy Termux runtime

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
| `agy` | Normal CLI entrypoint. Bare execution performs light preflight and may refresh wrapper support plus the upstream binary when needed. |
| `agy help` | Show upstream help first, then wrapper help below it. |
| `agy use` | List cached, buildable, and remote tuples, then run the selected combination. |
| `agy profile` | List numbered profiles or enter one by name. |
| `agy profile NAME` | Enter the named profile and run the bare CLI in that profile home. |
| `agy setup` | Refresh managed launcher/support files from `main`, ensure raw/runtime are ready, and print `agy :` / `wrapper :` version rows. |
| `agy update` | Refresh wrapper support, update the official upstream `agy` binary, patch safely, and print `agy :` / `wrapper :` version rows. |
| `agy doctor` | Check PATH, launcher, raw/runtime, loader, resolver, CA, and state. |
| `agy version` | Print `agy :` and `wrapper :` version rows. |
| `agy remove` | Remove the managed launcher, runtime, raw copy, state, and obsolete shims. |

## Files

```text
~/.local/lib/agy/termux/raw/agy
~/.local/lib/agy/termux/runtime/agy
~/.local/lib/agy/termux/runtime/managed.sh
~/.local/lib/agy/termux/runtime/lib.sh
~/.local/lib/agy/termux/runtime/build-runtime.py
~/.local/lib/agy/termux/runtime/wrapper-version.env
~/.local/share/agy/termux/registry.json
~/.local/share/agy/termux/state.json
~/.local/share/agy/termux/store/
~/.agy-profiles/
$PREFIX/bin/agy
```

## Rules

- The raw official binary is never patched in place.
- The managed launcher lives at `$PREFIX/bin/agy`; no extra PATH shim is created.
- No repo-pinned verified version file is shipped. The last successful bare
  `agy` runtime tuple is recorded locally after a normal exit.
- Cached raw binaries, wrapper snapshots, and successful runtime tuples live in
  `~/.local/share/agy/termux/store/` and are described by `registry.json`.
- `AGY_PROFILE_HOME` can redirect the runtime auth/session home for
  `agy profile NAME`; profile directories live under `~/.agy-profiles/` by
  default.
- `agy update` is the explicit full refresh path: wrapper support first, then upstream binary download, patch, smoke test, and promotion.
- Bare `agy` may use the same safe refresh path quietly before launching.
- `agy setup` is the recovery path for launcher/support refresh and runtime
  re-ensuring.
- setup/support cleanup only removes fixed obsolete pre-release shim file/link
  paths and AGY-marked rc PATH blocks. It does not remove the current
  `~/.local/lib/agy/termux` runtime root or `~/.local/share/agy/termux` state
  root; full managed runtime removal is reserved for `agy remove`.

## Troubleshooting

1. Run `agy doctor`.
2. If launcher/support files are stale or missing, run `agy setup`.
3. If you want a separate auth/session home, create a directory under
   `~/.agy-profiles/` and use `agy profile NAME`.
4. If wrapper or upstream binary refresh needs to be forced, run `agy update`.
5. If removing, use `agy remove`.

## Guides

- [Termux runtime guide](docs/AGY_TERMUX_GUIDE.md)
- [Termux launcher guide](docs/AGY_TERMUX_LAUNCHER.md)
