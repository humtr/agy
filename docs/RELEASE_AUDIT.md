# AGY Termux Wrapper Release Audit

Base commit: `ccdd7250089d0c7ea3328a8c39c15e324eb51988`

This audit records the release-candidate boundaries for the AGY Termux wrapper
state after the staged refactor from 001 through 006. It is a source-controlled
checklist, not a generated release artifact.

## Public surface

The intended public surface is the managed Termux runtime wrapper:

- `$PREFIX/bin/agy` is the single public launcher.
- `~/.local/lib/agy/termux` is the managed runtime root.
- `~/.local/share/agy/termux` is the managed state root.
- `~/.agy-profiles/` is the optional profile-home root used by `agy profile`.

The old native/glibc-shim public surface is not preserved as a supported API.
Any remaining references to obsolete helper paths are limited to cleanup policy
and removal documentation.

## Install and support model

`agy setup` and `agy update` refresh managed support files from the repository
before ensuring or refreshing the raw/runtime binary pair. Wrapper metadata must
come from `config/wrapper-version.env`; the installer fails closed when that file
is missing instead of creating `unknown` metadata.

The raw upstream binary is never patched in place. Runtime compatibility rewrites
are applied to a managed runtime copy under the Termux runtime root.

## Cleanup policy

Setup/support cleanup is intentionally narrow. It removes only fixed obsolete
pre-release shim file/link paths and AGY-marked rc PATH blocks. It skips
directories and does not remove the current Termux runtime or state roots.

Full managed runtime removal is reserved for `agy remove`, which is interactive
at the wrapper entrypoint and does not remove user Antigravity/OAuth config
outside AGY-managed runtime paths.

## Test gate

Before publishing wrapper changes, run:

```bash
bash tests/run-all.sh
```

The run-all gate currently covers:

- shell syntax checks for installer, library, and shell tests;
- Python bytecode compilation for `tools/build-runtime.py`;
- doctor output formatting, Codex-style color palette, color policy, and installed runtime support isolation test coverage;
- wrapper metadata fail-closed behavior;
- obsolete cleanup boundaries;
- repository invariants for the Termux runtime surface.

## Release-candidate checklist

A release-candidate state must satisfy all of the following:

- `bash tests/run-all.sh` passes.
- `git diff --check` passes for pending changes before commit.
- Public docs describe the Termux runtime surface, not a native surface.
- Wrapper metadata has no `unknown` fallback.
- Cleanup policy does not delete current runtime/state roots during setup/support.
- Generated bundles, diagnostics, logs, and local runtime artifacts are not
  committed to the source repository.

## Non-goals for this audit

This audit does not change runtime update selection, registry semantics, profile
selection, launcher implementation, Android companion behavior, or the local
patch application protocol. Those belong to later scoped stages.
