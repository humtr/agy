# Antigravity CLI (`agy`) Native Termux Guide

This project is a Termux-specific native wrapper and runtime-build workflow for
running the official Linux ARM64 Antigravity CLI (`agy`) on Android/Termux.

The current environment already completed `agy auth login`. Do not rerun auth
login as part of wrapper repair.

## Final Architecture

The maintained layout is:

```text
~/.local/bin/agy
  Raw official agy binary. Preserve it and never patch it in place.

~/.local/lib/agy-termux/agy
  Patched runtime copy generated from the raw binary.

~/.local/lib/agy-termux/run
  Thin glibc/env execution wrapper for the patched runtime.

~/.local/lib/agy-termux/lib.sh
~/.local/lib/agy-termux/build-runtime.py
  Installed runtime support files used by preflight, update, repair, and
  diagnostics. Normal `agy` execution does not source files from the cloned
  project directory.

~/bin/agy
  User-facing wrapper. Every normal invocation goes through preflight,
  execution, diagnostic capture, and postflight raw-change detection.

~/.local/share/agy-termux/state.env
  Hash/state file recording which raw binary produced the runtime copy.

~/.local/share/agy-termux/doctor/
  Diagnostic case directory for non-auth troubleshooting.
```

The normal command is:

```bash
agy ...
```

The only management command is:

```bash
agy termux
```

If you need to pass the literal argument `termux` to the underlying CLI:

```bash
AGY_PASSTHROUGH_TERMUX=1 agy termux
```

## Reliability Model

The main reliability mechanism is:

1. Preflight consistency check.
2. Wrapper-controlled `agy update` check before normal commands.
3. Transactional repatch if raw/patched/state/wrapper validation fails or the
   updater changes the raw binary.
4. Runtime-copy execution only after validation.
5. Postflight raw-hash detection.

Preflight checks:

- raw `~/.local/bin/agy` exists
- patched `~/.local/lib/agy-termux/agy` exists and is executable
- `~/.local/lib/agy-termux/run` wrapper references the runtime copy
- glibc loader exists
- Termux CA bundle exists
- `state.env` matches current raw and patched hashes
- runtime copy passes `--version`

Repair builds a candidate patched binary in the state directory, applies the
VA39 and `faccessat2` compatibility patches to that copy, sets the glibc loader
with `patchelf`, validates the candidate, backs up the previous patched binary,
then atomically moves the candidate into place.

## Updating Agy

If the official updater replaces `~/.local/bin/agy`, the next wrapper invocation
detects the raw hash mismatch and rebuilds the runtime copy before normal execution.
For normal commands, the wrapper checks the official Linux ARM64 manifest first.
If the manifest version is newer than the current runtime copy, the wrapper
downloads the manifest tarball, verifies its `sha512`, replaces only the raw
`~/.local/bin/agy`, and immediately rebuilds the runtime copy before continuing.

Manual `agy update` is still allowed. If that command changes the raw binary,
the wrapper performs the same manifest/tarball update broker instead of running
the patched binary's built-in updater. This is intentional: running the built-in
updater from the runtime copy can update the currently executed runtime path rather
than the preserved raw path.

Known limitation: if the patched process internally installs a new raw binary
and immediately `execve`s the absolute raw path `~/.local/bin/agy` inside the
same process, wrapper preflight may be bypassed for that immediate restart.
Postflight raw-change detection marks `NEEDS_REPATCH=1`, so the next invocation
repairs before running.

No safe official environment variable, config option, or flag for disabling
Antigravity auto-update was confirmed from local binary inspection. This wrapper
therefore uses update-before-run, verified tarball replacement, detection, and
repair rather than unsafe `execve` hooks.

Resolver handling is controlled by `AGY_RESOLVER_MODE`:

- `auto` is the default. The wrapper probes the glibc resolver first and runs
  without `proot` if native DNS works.
- `native` forces the glibc runtime path without `proot`.
- `proot` forces the older `$PREFIX/etc/resolv.conf` bind over `/etc/resolv.conf`.

The native path uses `GODEBUG=netdns=cgo`, Termux CA certificates, and
`$PREFIX/glibc/etc/{resolv.conf,nsswitch.conf,hosts}`. On the current verified
device, native DNS, TLS, user-driven OAuth login, update check, and a real
`--print` prompt all pass without `proot`. The `proot` mode remains available as
an explicit fallback.

To test the native path without changing auth state:

```bash
AGY_RESOLVER_MODE=native AGY_SKIP_AUTO_UPDATE=1 agy --version
```

Full prootless acceptance was validated with a user-driven OAuth test:

```bash
AGY_RESOLVER_MODE=native agy auth login
```

The user must complete the browser/OAuth flow. Do not paste OAuth callback URLs,
codes, states, cookies, or tokens into diagnostics. After login completes, verify
a harmless prompt in native mode. If native login or prompt execution regresses
on another device while `proot` mode works, force `AGY_RESOLVER_MODE=proot`.

## Diagnostic Cases

Normal `agy` failures create a diagnostic case unless the exit code is `0` or
`130`.

Case layout:

```text
~/.local/share/agy-termux/doctor/YYYYMMDD-HHMMSS/
  raw.log
  safe.log
  env.log
  repair_prompt.txt
```

The wrapper does not auto-call Gemini or Codex. Use `agy termux` and choose the
menu action if you want to send the last redacted prompt. If redaction looks
uncertain, inspect the prompt path manually and do not send it.

Redaction is best-effort. It targets bearer headers, cookies, OAuth token/query
fields, callback URLs containing code/token/state, and known fake test markers.
It is not a proof that arbitrary logs are secret-free.

## Compatibility Decisions

See `docs/COMPATIBILITY_DECISIONS.md` for the maintained compatibility record.
The required runtime decisions are the static VA39 patch, the `faccessat2`
compatibility patch, and native-first resolver handling with explicit `proot`
fallback.

`tcmalloc_fix.so` is not part of the active runtime or active source tree. The
wrapper does not set `LD_PRELOAD` for it. If future crash evidence justifies
re-testing that idea, recover the old shim from Git history and use a separate
diagnostic branch.

## Setup And Repair

Fresh install after cloning the repository:

```bash
cd ~/prj/agy
bash bin/install-runtime.sh --install
```

This installs `~/bin/agy` and `~/.local/lib/agy-termux/run`, downloads the current raw
Linux ARM64 `agy` tarball through the wrapper-managed broker, verifies its
`sha512`, and builds `~/.local/lib/agy-termux/agy`.
The generated wrappers source the installed support library at
`~/.local/lib/agy-termux/lib.sh`, not the cloned repository. The repository is
the install/update source; the installed files are the runtime source. Preflight
does not compare against the repository on every invocation.

Status:

```bash
bash bin/install-runtime.sh --status
```

Install wrappers:

```bash
bash bin/install-runtime.sh --install-wrappers
```

This only installs wrappers and does not download or repair binaries.

Rebuild runtime copy:

```bash
bash bin/install-runtime.sh --repair
```

Update raw agy through the wrapper-managed broker:

```bash
agy update
```

The update broker reads the official manifest, verifies the tarball `sha512`,
replaces only the raw `~/.local/bin/agy`, then rebuilds the runtime copy. It does not
run auth login.

## What This Does Not Promise

This project does not guarantee compatibility across all Android devices or all
future Antigravity builds. It does not make segfaults impossible. It does not
prove perfect redaction. It does not claim full self-update/restart coverage
unless the updater stays inside the wrapper-managed invocation boundary.
