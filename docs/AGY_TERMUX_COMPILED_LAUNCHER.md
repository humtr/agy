# AGY Termux Compiled Launcher

## Core Model

1. `agy` is a mediated compiled launcher (`$HOME/bin/agy`).
2. `agy-termux` is an independent control plane (`$HOME/bin/agy-termux`).
3. patched runtime direct execution is unsupported.

`fd33 resolver` is a pair:

- runtime rewrite: `/etc/resolv.conf` -> `/proc/self/fd/33`
- launcher wiring: open `$PREFIX/etc/resolv.conf` on fd 33 before exec

Both parts must exist together.

Command execution policy:

- `agy` (bare): light preflight + update check, then runtime exec.
- `agy update|upgrade|self-update`: full lifecycle pipeline with lock.
- headless/help/automation commands: cheap launch guard only, no auto-update.
- regular upstream commands: launcher mediation only, then patched runtime passthrough.

## LD Isolation

- Do not export `LD_LIBRARY_PATH` or `LD_PRELOAD` in shell startup files.
- Launcher unsets `LD_PRELOAD` and `LD_LIBRARY_PATH` before runtime exec.
- glibc paths are passed only with loader `--library-path`.
- `agy-termux doctor` reports a warning when parent shell has `LD_*` set.

Global `LD_*` pollution is a linker pollution risk that can break Termux/Bionic
tools (`bash`, `git`, `python3`) and is not an auth problem.

## Routing Policy

Default is upstream passthrough.

Reserved lifecycle commands are intercepted:

- `agy update`
- `agy upgrade`
- `agy self-update`

These route to `agy-termux update` and do not call upstream self-update.

`agy install` is a managed install/config path. Launcher/shell fallback can
guide users to installer workflow instead of treating it as a normal runtime
passthrough command.

Management words (`status`, `doctor`, `repair`, `rollback`, `fallback`,
`install`, `uninstall`) are not hard-intercepted. They remain passthrough by
default. The launcher prints a hint and can optionally redirect when
`AGY_ENABLE_TERMUX_ALIAS=1`.

Legacy `agy termux` is not a primary control path.

## Auth Rules

- `agy auth ...` stays passthrough.
- `you are not signed in -> signing in... -> interior entry` is not failure by itself.
- Failure signals: fresh OAuth re-request, sign-in stall, explicit auth failure,
  marker timeout, request failure, crash.
- Do not print OAuth URL, authorization code, tokens, cookies, or email.

## Update Safety

Termux pipeline is responsible for update lifecycle:

1. lock
2. download/update raw binary
3. build patched candidate
4. verify patch counts and resolver rewrite counts
5. smoke test candidate
6. atomic replace + backup
7. record state

`agy update` must never bypass this pipeline.

## Fallback and Diagnostics

- proot is diagnostic fallback only (`agy-termux test-proot`).
- shell fallback is recovery path when compiled launcher is unavailable.
- launcher also auto-retries shell fallback if control dispatch, fd33 open, or
  loader exec fails.
- token/auth/cache files are not uninstall/cleanup targets.
