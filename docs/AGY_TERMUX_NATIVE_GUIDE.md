# Antigravity CLI (`agy`) Native Termux Guide

This project is a Termux-specific launcher and runtime-build workflow for
running the official Linux ARM64 Antigravity CLI (`agy`) on Android/Termux.

The public user surface is intentionally limited to `agy`. Do not introduce a
separate public maintenance command unless `agy` itself cannot reach the local
shell fallback.

The current environment already completed `agy auth login`. Do not rerun auth
login as part of wrapper repair.

## Final Architecture

The maintained layout is:

```text
~/.local/lib/agy/native/raw/agy
  Raw official agy binary. Preserve it and never patch it in place.

~/.local/lib/agy/native/runtime/agy
  Patched runtime copy generated from the raw binary.

~/bin/agy
  Compiled launcher (Termux/Bionic executable) or shell fallback. This is the
  public runtime entrypoint and mediates command routing.

~/.local/bin/agy
$PREFIX/bin/agy
  Small shims that exec ~/bin/agy.

~/.local/lib/agy/native/runtime/lib.sh
~/.local/lib/agy/native/runtime/build-runtime.py
~/.local/lib/agy/native/runtime/verified-agy-version.env
  Installed support files used by the launcher, update broker, and local repair.

~/.local/share/agy/native/state.json
  Hash/state file recording which raw binary produced the runtime copy.

~/.local/share/agy/native/doctor/
  Local diagnostic case directory for non-auth troubleshooting.
```

The normal command is:

```bash
agy ...
```

There is no public `agy-t` or `agy-termux` control command.

## Reliability Model

Execution policy is command-surface aware:

1. cheap launch guard: runtime/loader/resolver readability checks
2. light preflight: cheap guard + drift warning (non-destructive)
3. full preflight: lifecycle validation/repair checks

Command policy:

- bare `agy`: light preflight + update check
- `agy update|upgrade|self-update`: full preflight + full update pipeline
- `agy repair`: offline local repair from the existing raw binary
- `agy --print`, `-p`, `--prompt`, `--print-timeout`: cheap guard only
- `agy --help`, `-h`, `help`: fast path, no update output mixing
- `agy plugin|plugins|changelog` and automation-style flags: cheap guard only
- `agy install`: managed install/config path

Normal runtime commands stay on compiled-launcher mediation and passthrough to
patched runtime without heavy per-run lifecycle work.

## Updating And Repairing Agy

`agy update` (and aliases `upgrade`, `self-update`) is the only full lifecycle
update entrypoint. It performs manifest check, checksum verification, candidate
build, validation, lock-held atomic promotion, and state update.

`agy repair` is the local offline repair entrypoint. It does not contact the
network. It rebuilds the patched runtime copy from the existing raw official
binary, validates the candidate with `--version`, and records state.

If the raw official binary or Termux glibc prerequisites are missing, rerun the
bootstrap installer:

```bash
curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

Normal commands do not run full hash verification/smoke/repair loops on every
invocation. Postflight strengthening is reserved for actual promotion/update
events.

Resolver handling is strict native fd mode. The compiled launcher opens
`$PREFIX/etc/resolv.conf` on fd 33 for the patched runtime.

The runtime uses `GODEBUG=netdns=go`, Termux CA certificates, and invokes the
glibc loader with `--library-path` instead of exporting `LD_LIBRARY_PATH`.
This keeps child Bionic tools from inheriting glibc paths while still giving the
agy runtime the libraries it needs.

The runtime builder rewrites the agy binary's `/etc/resolv.conf` references to
`/proc/self/fd/33`. The launcher then opens fd 33 from
`$PREFIX/etc/resolv.conf` before executing agy. This avoids the Android
`/etc -> /system/etc` resolver gap without bind mounts, global
`LD_LIBRARY_PATH`, or shared-storage resolver files.

Never export `LD_LIBRARY_PATH` or `LD_PRELOAD` in shell profile files for this
workflow. Launcher/runtime paths are isolated per child execution by unsetting
`LD_*` and using loader `--library-path` only.

To verify the canonical resolver path without changing auth state:

```bash
AGY_SKIP_AUTO_UPDATE=1 agy --version
```

OAuth must be user-driven:

```bash
agy auth login
```

The user must complete the browser/OAuth flow. Do not paste OAuth callback URLs,
codes, states, cookies, or tokens into diagnostics. After login completes, verify
a harmless prompt.

`you are not signed in -> signing in... -> interior entry` is not a failure
signal by itself. Treat auth failure only when fresh browser OAuth is required,
sign-in stalls indefinitely, explicit auth failure appears, requests time out,
or runtime/model calls fail.

## Diagnostic Cases

Normal `agy` failures create a diagnostic case unless the exit code is `0` or
`130`.

Case layout:

```text
~/.local/share/agy/native/doctor/YYYYMMDD-HHMMSS/
  raw.log
  safe.log
  env.log
  repair_prompt.txt
```

The wrapper does not auto-call Gemini, Codex, or any other LLM. Redaction is
best-effort. It targets bearer headers, cookies, OAuth token/query fields,
callback URLs containing code/token/state, and known fake test markers. It is not
a proof that arbitrary logs are secret-free.

## Compatibility Decisions

See `docs/COMPATIBILITY_DECISIONS.md` for the maintained compatibility record.
The required runtime decisions are the static VA39 patch, the `faccessat2`
compatibility patch, strict native fd33 resolver path, and loader-scoped glibc
library paths.

`agy` is a mediated launcher. Lifecycle commands like `update`, `upgrade`, and
`self-update` are intercepted and routed to the Termux pipeline instead of the
upstream runtime self-update path.

Other subcommands default to upstream passthrough. Unknown subcommands are not
blocked by launcher allowlists.

Direct execution of `~/.local/lib/agy/native/runtime/agy` is unsupported. The
patched runtime expects fd 33 resolver wiring from the launcher.

`tcmalloc_fix.so` is not part of the active runtime or active source tree. The
wrapper does not set `LD_PRELOAD` for it. If future crash evidence justifies
re-testing that idea, recover the old shim from Git history and use a separate
diagnostic branch.

## Setup

`main` branch is the canonical runtime source and includes the one-line bootstrap
script at `install.sh`.

Fresh install after cloning the repository:

```bash
export DEBIAN_FRONTEND=noninteractive
pkg update -y
apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold git curl python tar patchelf coreutils ca-certificates glibc-repo
pkg update -y
apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold glibc glibc-runner
git clone --branch main https://github.com/humtr/agy.git ~/prj/agy
cd ~/prj/agy
bash bin/install-runtime.sh --install
```

One-line bootstrap (same `main` source, same installer engine):

```bash
pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

This installs `~/bin/agy`, `$PREFIX/bin/agy`, and
`~/.local/lib/agy/native/runtime/run`, downloads the current raw Linux ARM64
`agy` tarball through the wrapper-managed broker, verifies its `sha512`, and
builds `~/.local/lib/agy/native/runtime/agy`.

The generated wrappers source the installed support library at
`~/.local/lib/agy/native/runtime/lib.sh`, not the cloned repository. The
repository is the install/update source; the installed files are the runtime
source. Preflight does not compare against the repository on every invocation.

`$PREFIX/bin/agy` is a small managed shim that execs `~/bin/agy`. `$PREFIX/bin`
is always on Termux PATH, so `agy` should resolve even if a shell does not read
`~/.profile`, `.bashrc`, or `.zshrc`.

Development status and repair commands remain available from a cloned repository:

```bash
bash bin/install-runtime.sh --status
bash bin/install-runtime.sh --repair
```

## What This Does Not Promise

This project does not guarantee compatibility across all Android devices or all
future Antigravity builds. It does not make segfaults impossible. It does not
prove perfect redaction. It does not claim full self-update/restart coverage
unless the updater stays inside the wrapper-managed invocation boundary.
