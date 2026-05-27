# AGY Termux Compatibility Decisions

Last reviewed: 2026-05-26

## Purpose

This document records compatibility decisions that are intentionally retained in
the project. It separates evidence from interpretation so future changes do not
reintroduce unsupported crash explanations or runtime hooks.

## Decision 1: VA39 Static Patch

Status: required.

Evidence:

- The current runtime is generated from the raw official `agy` binary by
  `tools/build-runtime.py`.
- The runtime builder refuses output if no rewrites are applied or if expected
  VA39 rewrite patterns are missing.
- The patched runtime passed `--version`, user-driven OAuth login, update check,
  and a real `--print` prompt in native resolver mode.

Policy:

- Keep the static VA39 binary patch as the primary compatibility mechanism.
- Never patch the raw official `~/.local/bin/agy` in place.
- Generate only a patched copy under `~/.local/lib/agy-termux/agy`.

## Decision 2: `faccessat2` Compatibility Patch

Status: required.

Evidence:

- Android/Termux compatibility can fail on glibc-oriented syscall paths.
- The runtime builder rewrites the known `faccessat2` wrapper pattern unless
  explicitly skipped for manual experiments.

Policy:

- Keep the `faccessat2` compatibility rewrite enabled by default.
- Treat `--skip-syscall-compat` as a runtime-builder diagnostic option, not the
  normal runtime path.

## Decision 3: Resolver Strategy

Status: native fd-backed resolver path by default.

Evidence:

- The agy runtime is executed by `ld-linux-aarch64.so.1 --library-path ...`
  instead of exporting `LD_LIBRARY_PATH`.
- `LD_LIBRARY_PATH` is removed from the environment before agy starts, so child
  Bionic tools do not inherit glibc paths.
- `GODEBUG=netdns=go` avoids glibc NSS resolver behavior inside the Go runtime.
- Rewriting the runtime copy's `/etc/resolv.conf` references to
  `/proc/self/fd/33` and opening fd 33 from `$PREFIX/etc/resolv.conf` is
  required for deterministic native resolver behavior on this device.

Policy:

- Use strict native fd-backed resolver path only for `agy`.
- Keep proot resolver bind for diagnostic-only fallback via control plane tests.

## Decision 4: Mediated Launcher Routing

Status: required.

Evidence:

- Upstream self-update can replace runtime artifacts outside Termux migration
  guarantees.
- Termux compatibility requires raw->patched candidate validation, resolver
  rewrite verification, and atomic replacement.
- Compiled launcher routing can reserve lifecycle commands while preserving
  passthrough for ordinary upstream commands.

Policy:

- `agy` is a mediated compiled launcher, not pure passthrough.
- Intercept only `update`, `upgrade`, `self-update` and route to
  `agy-termux update`.
- Keep unknown subcommands as upstream passthrough.
- Keep `--version`, `--help`, `-h`, and `--print` as passthrough.
- Do not hard-intercept management words by default; optionally alias with
  `AGY_ENABLE_TERMUX_ALIAS=1`.

## Decision 5: `tcmalloc_fix.so` mmap Shim

Status: removed from runtime and active source.

Evidence:

- Current normal execution, native DNS/TLS, OAuth login, update check, and real
  prompt execution passed without the shim.
- The shim source exports only a replacement `mmap`.
- It nulls requested `mmap` hints above `0x7fffffffff`.
- It does not verify returned `mmap` addresses.
- It does not intercept `mmap64`, `mremap`, or allocator-specific internals.
- No `execve`, `system`, `python`, `patch`, or `patchelf` hook symbols were
  found in prior local inspection.

Corrected arithmetic:

```text
0x2e80000000  = 199715979264
0x622fe3cdd0  = 421710253520
0x7ce81be000  = 536470085632
0x7fffffffff  = 549755813887
```

All three cited addresses are below `0x7fffffffff`.

Policy:

- Do not load `tcmalloc_fix.so` from the wrapper.
- Do not document it as a proven structural fix.
- If future crashes motivate re-testing, recover the old shim source from Git
  history and do that work in a separate diagnostic branch with explicit logging
  and without global `LD_PRELOAD`.
