# AGY Termux Compiled Launcher

## Core Model

1. `agy` is the only public user command.
2. The launcher mediates lifecycle and repair commands internally.
3. patched runtime direct execution is unsupported.
4. `agy-t` and `agy-termux` are not installed as public control commands.

`fd33 resolver` is a pair:

- runtime rewrite: `/etc/resolv.conf` -> `/proc/self/fd/33`
- launcher wiring: open `$PREFIX/etc/resolv.conf` on fd 33 before exec

Both parts must exist together.

Command execution policy:

- `agy` (bare): light preflight + update check, then runtime exec.
- `agy update|upgrade|self-update`: full lifecycle pipeline with lock.
- `agy repair`: offline local repair from the existing raw binary.
- headless/help/automation commands: cheap launch guard only, no auto-update.
- regular upstream commands: launcher mediation only, then patched runtime passthrough.

## LD Isolation

- Do not export `LD_LIBRARY_PATH` or `LD_PRELOAD` in shell startup files.
- Launcher unsets `LD_PRELOAD` and `LD_LIBRARY_PATH` before runtime exec.
- glibc paths are passed only with loader `--library-path`.

Global `LD_*` pollution is a linker pollution risk that can break Termux/Bionic
tools (`bash`, `git`, `python3`) and is not an auth problem.

## Routing Policy

Default is upstream passthrough.

Reserved lifecycle commands are intercepted:

- `agy update`
- `agy upgrade`
- `agy self-update`

These route to the Termux-safe update pipeline and do not call upstream self-update.

`agy repair` is also intercepted. It does not contact the network. It rebuilds the
patched runtime copy from the existing raw official binary, validates the result,
and records state.

`agy install` is a managed install/config path. Launcher/shell fallback can guide
users to the installer workflow instead of treating it as a normal runtime
passthrough command.

Management words such as `status`, `doctor`, `rollback`, `paths`, `debug`, and
`uninstall` are not public commands. Development diagnostics remain available from
the cloned repository through `bash bin/install-runtime.sh --status` or
`bash bin/install-runtime.sh --repair`.

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

- shell fallback is recovery path when compiled launcher is unavailable.
- launcher also auto-retries shell fallback if fd33 open or loader exec fails.
- token/auth/cache files are not install, update, or repair targets.
- diagnostic logs remain local unless the user explicitly shares them.
