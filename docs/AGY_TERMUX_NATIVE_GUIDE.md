# Antigravity CLI (`agy`) Native Termux Guide

This project is a Termux-specific native wrapper and binary-patch workflow for
running the official Linux ARM64 Antigravity CLI (`agy`) on Android/Termux.

The current environment already completed `agy auth login`. Do not rerun auth
login as part of wrapper repair.

## Final Architecture

The maintained layout is:

```text
~/.local/bin/agy
  Raw official agy binary. Preserve it and never patch it in place.

~/.local/bin/agy.va39
  Patched runtime copy generated from the raw binary.

~/.local/bin/agy-va39
  Thin glibc/env execution wrapper for the patched runtime.

~/bin/agy
  User-facing wrapper. Every normal invocation goes through preflight,
  execution, diagnostic capture, and postflight raw-change detection.

~/.local/share/agy-termux/state.env
  Hash/state file recording which raw binary produced the patched runtime.

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
2. Transactional repatch if raw/patched/state/wrapper validation fails.
3. Patched runtime execution only after validation.
4. Postflight raw-hash detection.

Preflight checks:

- raw `~/.local/bin/agy` exists
- patched `~/.local/bin/agy.va39` exists and is executable
- `~/.local/bin/agy-va39` wrapper references the patched runtime
- glibc loader exists
- Termux CA bundle exists
- `state.env` matches current raw and patched hashes
- patched runtime passes `--version`

Repair builds a candidate patched binary in the state directory, applies the
VA39 and `faccessat2` compatibility patches to that copy, sets the glibc loader
with `patchelf`, validates the candidate, backs up the previous patched binary,
then atomically moves the candidate into place.

## Updating Agy

If the official updater replaces `~/.local/bin/agy`, the next wrapper invocation
detects the raw hash mismatch and rebuilds `agy.va39` before normal execution.

Known limitation: if the patched process internally installs a new raw binary
and immediately `execve`s the absolute raw path `~/.local/bin/agy` inside the
same process, wrapper preflight may be bypassed for that immediate restart.
Postflight raw-change detection marks `NEEDS_REPATCH=1`, so the next invocation
repairs before running.

No safe official environment variable, config option, or flag for disabling
Antigravity auto-update was confirmed from local binary inspection. This wrapper
therefore uses detection and repair rather than unsafe `execve` hooks.

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

## `tcmalloc_fix.so` Policy

`tcmalloc_fix.so` is treated as experimental and gated, not a default structural
fix.

Evidence from local inspection:

- The shim exports only `mmap`.
- It nulls requested `mmap` address hints above `0x7fffffffff`.
- It does not verify returned `mmap` addresses.
- It does not intercept `mmap64`, `mremap`, or allocator-specific internals.
- The previous segfault report used incorrect arithmetic: `0x2e80000000`,
  `0x622fe3cdd0`, and `0x7ce81be000` are all below `0x7fffffffff`.

Default production behavior does not set `LD_PRELOAD`. To test the shim for a
single `agy` invocation only:

```bash
AGY_ENABLE_TCMALLOC_SHIM=1 agy --version
```

Do not export that variable globally. `LD_PRELOAD` must stay scoped to the glibc
agy runtime and must not leak into normal Termux/Bionic tools.

## Setup And Repair

Status:

```bash
bash setup_agy_termux.sh --status
```

Install wrappers:

```bash
bash setup_agy_termux.sh --install-wrappers
```

Rebuild patched runtime:

```bash
bash setup_agy_termux.sh --repair
```

Controlled official raw install/update:

```bash
bash setup_agy_termux.sh --install-raw
```

The raw install action intentionally uses the official Antigravity installer.
It may replace `~/.local/bin/agy`; the script rebuilds the patched runtime after
that action. It does not run auth login.

## What This Does Not Promise

This project does not guarantee compatibility across all Android devices or all
future Antigravity builds. It does not make segfaults impossible. It does not
prove perfect redaction. It does not claim full self-update/restart coverage
unless the updater stays inside the wrapper-managed invocation boundary.
