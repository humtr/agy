# AGY Native Termux Runtime Guide

This repository installs a Termux-native mediation layer for the official Linux
ARM64 Antigravity CLI (`agy`). The public surface is intentionally one command:
`agy`.

## Public command model

| Command | Behavior |
| :--- | :--- |
| `agy` | Normal Antigravity CLI entrypoint. Bare execution uses light preflight and the normal update check. |
| `agy update` | Termux-safe official binary update pipeline. |
| `agy sync` | Refresh wrapper/runtime support files from this repository's `main` branch. |
| `agy repair` | Offline rebuild of the patched runtime from the existing raw binary. |
| `agy doctor` | Local diagnostics for PATH, wrappers, runtime, resolver, CA, and state drift. |
| `agy version` | Print the upstream runtime binary version. |
| `agy info` | Print upstream runtime version plus installed wrapper metadata. |
| `agy uninstall --yes` | Remove managed wrappers, runtime/raw files, state/source cache, and shims. |

Do not add a second public control command. Legacy `agy-t` and `agy-termux`
shims are removed during wrapper installation.

## Filesystem layout

```text
~/.local/lib/agy/native/raw/agy
  Raw official Linux ARM64 agy binary. Never patch this file in place.

~/.local/lib/agy/native/runtime/agy
  Patched runtime copy produced from raw/agy.

~/.local/lib/agy/native/runtime/run
  Shell exec wrapper used by fallback paths.

~/.local/lib/agy/native/runtime/lib.sh
~/.local/lib/agy/native/runtime/build-runtime.py
~/.local/lib/agy/native/runtime/wrapper-version.env
  Installed runtime support files.

~/bin/agy
  Public entrypoint. Prefer a compiled Bionic launcher; use shell fallback when
  clang is unavailable during installation.

~/.local/bin/agy
$PREFIX/bin/agy
  Small shims that exec ~/bin/agy.

~/.local/share/agy/native/state.json
  Runtime state file recording raw/runtime hashes and update metadata.

~/.local/share/agy/native/doctor/
  Local diagnostic cases created after non-auth runtime failures.
```

## Runtime build model

`tools/build-runtime.py` copies the raw binary, applies required compatibility
rewrites, validates that required rewrite patterns were found, and writes the
patched runtime copy. The current required rewrites are:

- VA39/tcmalloc address-window compatibility rewrites.
- `faccessat2` syscall compatibility rewrite.
- `/etc/resolv.conf` → `/proc/self/fd/33` resolver path rewrite.

The builder fails closed when the expected runtime section is missing unless a
human explicitly uses the diagnostic `--allow-broad-scan` flag.

## Execution model

The launcher/runtime path avoids global linker pollution:

1. Open `$PREFIX/etc/resolv.conf` as fd 33.
2. Unset `LD_PRELOAD` and `LD_LIBRARY_PATH`.
3. Set `GODEBUG=netdns=go` unless the user already set it.
4. Set Termux CA certificate environment defaults.
5. Execute the patched runtime through `ld-linux-aarch64.so.1 --library-path`.

This keeps child Bionic tools from inheriting glibc library paths while still
allowing the Linux ARM64 runtime to resolve DNS and TLS correctly.

## Update, sync, repair, doctor, uninstall

### `agy update`

`agy update` is the only public official-binary update entrypoint. It checks the
upstream manifest, verifies checksums, builds a patched candidate, smoke-tests it
with `--version`, and atomically promotes raw/runtime files while holding the
native state lock.

The repository does not pin or ship a separate "verified agy version" file.
Version safety comes from validating the live upstream manifest and candidate
binary before promotion, while `state.json` records the last locally verified
installed version.

### `agy uninstall`

`agy uninstall --yes` removes this repository's managed Termux runtime surface:
`~/bin/agy`, local/prefix shims, legacy control shims, `~/.local/lib/agy/native`,
`~/.local/share/agy/native`, the glibc shim directory, and PATH blocks that were
created by the installer. It does not remove user Antigravity/OAuth config outside
those managed runtime paths.

### `agy sync`

`agy sync` updates only this repository's wrapper/runtime support. It re-runs the
bootstrap installer in sync mode and installs wrappers/support files without
forcing an official agy binary update.

### `agy repair`

`agy repair` is offline. It rebuilds `runtime/agy` from the current `raw/agy`,
validates the candidate, updates `state.json`, and leaves OAuth/user config
untouched.

### `agy doctor`

`agy doctor` is the first troubleshooting command. It checks:

- current `agy` PATH resolution;
- launcher and shim presence;
- runtime support files and wrapper metadata;
- raw and patched binaries;
- glibc loader/library directory;
- CA bundle and resolver source;
- fd 33 resolver readiness;
- resolver rewrite counts in the patched runtime;
- patched runtime interpreter when `patchelf` is available;
- patched runtime `--version` startup;
- state/runtime hash drift.

It exits non-zero when required checks fail and prints warning counts for
recoverable drift or optional missing metadata.

## Auth policy

The wrapper never runs `agy auth login` automatically. OAuth must remain
user-driven:

```bash
agy auth login
```

Do not paste OAuth callback URLs, codes, cookies, or tokens into diagnostic logs.
Generated diagnostic cases are local files and are not sent to external tools by
this wrapper.
