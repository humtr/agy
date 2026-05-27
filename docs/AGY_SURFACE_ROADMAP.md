# AGY Surface Roadmap (agy / agy-t / legacy agy-termux)

## Goal

- Keep `agy` looking and behaving like upstream CLI.
- Move Termux management features to a short dedicated command: `agy-t`.
- Reduce public reliance on `agy-termux` and `agy-termux-lib.sh`.

## Phase 0 (current)

- Keep fac8e95 command-surface split intent.
- Lifecycle intercept in launcher remains limited to:
  - `update`
  - `upgrade`
  - `self-update`
- `agy-termux` is legacy compatibility surface.
- New management features should not expand `agy` subcommand interception.

## Phase 1

- Introduce `agy-t` as canonical management entrypoint.
- Keep `agy-termux` as compatibility shim that prints deprecation notice and forwards.
- Candidate commands for `agy-t`:
  - `status`, `doctor`, `update`, `repair`, `rollback`
  - `install`, `uninstall`, `paths`
  - `route -- <agy args...>`, `debug bundle`

## Phase 2

- Split `agy-termux-lib.sh` monolith into control-plane modules/internal APIs.
- Reduce installed runtime dependence on externally sourced shell library.
- Separate:
  - state management
  - route policy
  - update pipeline
  - repair/doctor logic

## Phase 3

- Remove `agy-termux` from canonical docs (or keep legacy-only).
- Canonical public surface becomes:
  - `agy` (upstream-facing runtime)
  - `agy-t` (Termux management)

## Separate Security Track (S blockers)

Do not mix these with command-surface routing changes; handle in dedicated commits:

- `state.env` shell `source` model hardening
- lock unification for update/repair/rollback
- tar extraction path traversal defense
- `build-runtime.py` fail-open scan behavior
- diagnostic raw log security/retention policy
