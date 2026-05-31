# AGY Compiled Launcher Guide

`tools/agy-launcher.c` builds the preferred `~/bin/agy` entrypoint for Termux.
It is a small Bionic executable that decides whether to enter the local managed
shell path or execute the patched Linux ARM64 runtime directly.

## Route policy

| Input | Route |
| :--- | :--- |
| bare `agy` | managed shell path for light preflight and update check |
| `agy update` | managed shell path for the Termux-safe binary update pipeline |
| `agy sync` | managed shell path for wrapper/runtime support refresh |
| `agy repair` | managed shell path for offline runtime rebuild |
| `agy doctor` | managed shell path for diagnostics |
| `agy info` | managed shell path for wrapper/upstream version info |
| `agy uninstall` | managed shell path for cleanup/removal |
| `agy version` | upstream passthrough translated to `--version` |
| leading-option commands such as `agy --print` | upstream passthrough |
| all other subcommands | upstream passthrough |

`upgrade` and `self-update` are not launcher-reserved commands in the current
single-surface model. Only `update` is the official binary update lifecycle
entrypoint.

## Runtime exec path

For passthrough commands the launcher:

1. opens `$PREFIX/etc/resolv.conf` on fd 33 and clears `FD_CLOEXEC`;
2. removes `LD_PRELOAD` and `LD_LIBRARY_PATH` from the child environment;
3. sets default `GODEBUG=netdns=go` and Termux CA variables;
4. executes `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` with `--library-path`;
5. passes `~/.local/lib/agy/native/runtime/agy` and the original CLI arguments.

If resolver setup or loader exec fails, the launcher attempts the installed shell
fallback at `~/.local/lib/agy/native/runtime/agy-shell-wrapper.sh`.

## Debugging

Set `AGY_LAUNCHER_DEBUG=1` to print launcher route decisions and resolved paths.
Use `agy doctor` for normal user-facing diagnostics before enabling launcher
trace output.
