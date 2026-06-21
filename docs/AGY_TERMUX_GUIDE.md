# AGY Termux Runtime Guide

This repository installs the official Linux ARM64 Antigravity CLI (`agy`) as a
Termux-managed runtime with a single public launcher at `$PREFIX/bin/agy`.

## Public command model

| Command | Behavior |
| :--- | :--- |
| `agy` | Normal CLI entrypoint. Bare execution performs light preflight and may refresh wrapper support plus the upstream binary when needed. |
| `agy help` | Show upstream help first, then wrapper help below it. |
| `agy use` | List cached, buildable, and remote tuples, then run the selected combination. |
| `agy profile` | List numbered profiles or enter one by name. |
| `agy profile NAME` | Enter the named profile and run the bare CLI in that profile home. |
| `agy setup` | Refresh managed launcher/support files from `main`, ensure raw/runtime are ready, and print `agy :` / `wrapper :` version rows. |
| `agy update` | Refresh wrapper support, run the Termux-safe official binary update pipeline, then print `agy :` / `wrapper :` version rows. |
| `agy doctor` | Local diagnostics for PATH, launcher, runtime, resolver, CA, and state. |
| `agy version` | Print `agy :` and `wrapper :` version rows. |
| `agy remove` | Remove the managed launcher, runtime/raw files, state, and obsolete shims. |

Do not add a second public lifecycle command. `agy profile` is a selector
entrypoint, not a management command. Obsolete helper paths are removed during
setup and remove cleanup.

## Obsolete cleanup policy

AGY's current public surface is the managed Termux runtime rooted at
`~/.local/lib/agy/termux`, the state root at `~/.local/share/agy/termux`, and
the single launcher at `$PREFIX/bin/agy`. setup/support cleanup is limited to
fixed pre-release helper shim file/link paths and rc PATH blocks marked by older
AGY installers. It skips directories and does not remove the current runtime or
state roots. Full managed runtime removal is reserved for `agy remove`.

## Filesystem layout

```text
~/.local/lib/agy/termux/raw/agy
  Raw official Linux ARM64 agy binary. Never patch this file in place.

~/.local/lib/agy/termux/runtime/agy
  Patched runtime copy produced from raw/agy.

~/.local/lib/agy/termux/runtime/managed.sh
  Managed shell entrypoint used by launcher fallback paths.

~/.local/lib/agy/termux/runtime/lib.sh
~/.local/lib/agy/termux/runtime/build-runtime.py
~/.local/lib/agy/termux/runtime/wrapper-version.env
  Installed runtime support files.

The managed shell prefers the source checkout's `lib/agy-termux-lib.sh` when the
checkout used by setup/support is still present. The copied runtime `lib.sh`
remains a fallback for cases where the checkout was removed. This makes repo
patches take effect in wrapper routes without a separate manual support refresh.

~/.agy-profiles/
  Optional profile home roots used by `agy profile NAME`.

$PREFIX/bin/agy
  Public entrypoint. Prefer a compiled Bionic launcher; use shell fallback when
  clang is unavailable during installation.

~/.local/share/agy/termux/state.json
  Runtime state file recording raw/runtime hashes and the last successful bare
  `agy` runtime tuple.

~/.local/share/agy/termux/registry.json
  Registry of raw binary snapshots, wrapper snapshots, and successful runtime
  tuple caches.

~/.local/share/agy/termux/store/
  Cache root for raw binaries, wrapper snapshots, and successful runtime tuples.

~/.local/share/agy/termux/doctor/
  Local diagnostic cases created after non-auth runtime failures.
```

## Runtime build model

`tools/build-runtime.py` copies the raw binary, applies required compatibility
rewrites, validates that required rewrite patterns were found, and writes the
patched runtime copy. The current required rewrites are:

- VA39/tcmalloc address-window compatibility rewrites.
- `faccessat2` syscall compatibility rewrite.
- `/etc/resolv.conf` -> `/proc/self/fd/33` resolver path rewrite.

The builder fails closed when the expected runtime section is missing unless a
human explicitly uses the diagnostic `--allow-broad-scan` flag.

## Execution model

The launcher/runtime path avoids global linker pollution:

1. Open `$PREFIX/etc/resolv.conf` as fd 33.
2. Unset `LD_PRELOAD` and `LD_LIBRARY_PATH`.
3. Set `GODEBUG=netdns=go` unless the user already set it.
4. Set Termux CA certificate environment defaults.
5. Execute `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` with `--library-path`.

This keeps child Bionic tools from inheriting glibc library paths while still
allowing the Linux ARM64 runtime to resolve DNS and TLS correctly.

## Setup, update, doctor, remove

### `agy setup`

`agy setup` refreshes the managed launcher and runtime support from the live
repo, then ensures raw/runtime are ready. If the raw binary is missing, the
installer fetches the current upstream binary and builds the patched runtime.

### `agy update`

`agy update` is the explicit full refresh entrypoint. It refreshes wrapper
support first, then checks the upstream manifest, verifies checksums, builds a
patched candidate with the selected wrapper snapshot, smoke-tests it with
`--version`, and promotes raw/runtime files only after validation while holding
the Termux state lock.

### `agy use`

`agy use` lists numbered candidates: cached runtime tuples, buildable cached
raw/wrapper combinations, and remote raw candidates paired with the latest
wrapper. Choosing a cached runtime reuses it. Choosing a buildable tuple creates
a patched runtime from the selected stored raw and wrapper. Choosing a remote
candidate downloads and verifies the raw binary first, then builds and runs the
selected tuple.

When bare `agy` resumes a previously selected tuple in an interactive terminal,
`Enter` or `Y` keeps the previous tuple, `N` jumps to the latest path, `Esc`
cancels the current `agy` execution, and any other input forwards to the tuple
selector.

Inside `agy use`, pressing `Esc` cancels the selection and exits without
starting a runtime. Any typed number, tuple id, or listed remote version is treated as the tuple
selector input.

### `agy remove`

`agy remove` removes this repository's managed Termux runtime surface:
`$PREFIX/bin/agy`, `~/.local/lib/agy/termux`, `~/.local/share/agy/termux`,
obsolete shim paths, and PATH blocks that were created by older installers. It does
not remove user Antigravity/OAuth config outside those managed runtime paths.

### `agy doctor`

`agy doctor` is the first troubleshooting command. It checks:

- current `agy` PATH resolution;
- launcher presence;
- runtime support files and wrapper metadata;
- raw and patched binaries;
- glibc loader/library directory;
- CA bundle and resolver source;
- fd 33 resolver readiness;
- patched runtime interpreter when `patchelf` is available;
- patched runtime `--version` startup;
- upstream update kill-switch status;
- state/runtime hash drift.

It exits non-zero when required checks fail and prints warning counts for
recoverable drift or optional missing metadata.

## Test and invariant checks

Before publishing wrapper changes, run:

```bash
bash tests/run-all.sh
```

The run-all script executes shell syntax checks, focused behavior tests for
doctor formatting, metadata fail-closed behavior, obsolete cleanup boundaries,
and repository invariants that keep the public Termux runtime surface aligned.

## Auth policy

The wrapper never runs `agy auth login` automatically. OAuth must remain
user-driven:

```bash
agy auth login
```

## Profiles

`agy profile` is a numbered profile selector and entrypoint, not a management command.
It lists profile names from `~/.agy-profiles/` and can enter a named profile by
setting `AGY_PROFILE_HOME` for the bare runtime. It does not create, rename, or
delete profile directories.

Do not paste OAuth callback URLs, codes, cookies, or tokens into diagnostic logs.
Generated diagnostic cases are local files and are not sent to external tools by
this wrapper.
