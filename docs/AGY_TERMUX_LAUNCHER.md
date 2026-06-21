# AGY Termux Launcher Guide

`tools/agy-launcher.c` builds the preferred `$PREFIX/bin/agy` entrypoint for
Termux. It is a small Bionic executable that decides whether to enter the local
managed shell path or execute the patched Linux ARM64 runtime directly.

## Route policy

| Input | Route |
| :--- | :--- |
| bare `agy` | managed shell path for light preflight and safe wrapper/binary refresh |
| `agy help` | managed shell path for upstream help plus wrapper help summary |
| `agy use` | managed shell path for cached/buildable/remote tuple selection and execution |
| `agy profile` | managed shell path for numbered profile listing and profile entry |
| `agy profile NAME` | managed shell path for profile entry |
| `agy setup` | managed shell path for launcher/support refresh and `agy :` / `wrapper :` version rows |
| `agy update` | managed shell path for wrapper refresh plus the Termux-safe binary update pipeline and `agy :` / `wrapper :` version rows |
| `agy doctor` | managed shell path for diagnostics |
| `agy remove` | managed shell path for cleanup/removal |
| `agy version` | managed shell path for `agy :` and `wrapper :` version rows |
| leading-option commands such as `agy --print` | upstream passthrough |
| all other subcommands | upstream passthrough |

`upgrade` and `self-update` are not launcher-reserved commands. Only `update` is
the official binary update lifecycle entrypoint.

## Runtime exec path

For passthrough commands the launcher:

1. opens `$PREFIX/etc/resolv.conf` on fd 33 and clears `FD_CLOEXEC`;
2. removes `LD_PRELOAD` and `LD_LIBRARY_PATH` from the child environment;
3. sets default `GODEBUG=netdns=go` and Termux CA variables;
4. executes `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` with `--library-path`;
5. injects the internal upstream updater kill-switch base URL;
6. passes `~/.local/lib/agy/termux/runtime/agy` and the original CLI arguments.

If resolver setup or loader exec fails, the launcher attempts the installed
managed shell at `~/.local/lib/agy/termux/runtime/managed.sh`.

The managed shell sources only the installed runtime support copy at
`~/.local/lib/agy/termux/runtime/lib.sh`. Development checkouts are not trusted
at runtime unless their contents have been installed through setup/support.

## Debugging

Set `AGY_LAUNCHER_DEBUG=1` to print launcher route decisions and resolved paths.
Use `agy doctor` for normal user-facing diagnostics before enabling launcher
trace output.
