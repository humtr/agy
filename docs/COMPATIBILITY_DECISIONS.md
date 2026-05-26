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

Status: native-first with `proot` fallback.

Evidence:

- glibc DNS resolved `oauth2.googleapis.com` without `proot`.
- glibc DNS resolved the official updater host without `proot`.
- TLS verification with the Termux CA bundle passed for OAuth and updater hosts.
- User-driven `AGY_RESOLVER_MODE=native agy auth login` completed.
- `AGY_RESOLVER_MODE=native agy --print 'Reply with exactly:
  AGY_TERMUX_NATIVE_OK'` returned `AGY_TERMUX_NATIVE_OK`.
- `strace -f -e execve` for the native prompt path showed no `proot` execution.

Policy:

- Default to `AGY_RESOLVER_MODE=auto`.
- Use native glibc resolver when the probe succeeds.
- Keep `AGY_RESOLVER_MODE=proot` as an explicit fallback for device-specific
  resolver regressions.

## Decision 4: `tcmalloc_fix.so` mmap Shim

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
