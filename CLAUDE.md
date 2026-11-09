# Super Star Fighter — notes for coding agents

Godot 4.7.2 (pinned), typed GDScript, server-authoritative multiplayer over WebSocket. The offline lab and client prediction run the same `AuthoritativeWorld` code as the server. [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) is the full contributor guide; this file is the short list of rules that break CI or compatibility when missed.

## Running tests

- Once per checkout: `.\tools\bootstrap.ps1` (or `python3 tools/build.py bootstrap` without PowerShell).
- Unit suite: `.\tools\run-tests.ps1`. It must end with `TEST_SUMMARY passed=N failed=0`, exit 0, and print no `ERROR:` or `SCRIPT ERROR:` lines. The full log is under `.tools/verification-logs/`. `-Filter <text>` runs only suites whose file name contains the text; per-suite counts and timings print before the summary, and failures are repeated there.
- After adding or renaming a script with a `class_name`, run the engine once with `--headless --path . --import` before the tests; otherwise the stale class cache makes the run hang silently.
- In a git worktree, `.tools/` is not there: link it from the main checkout, then run the engine once with `--headless --path <worktree> --import`, or the test run hangs silently. Revert the line-ending churn that import leaves in `assets/**/*.import` before committing.

## Rules

1. **Wire compatibility.** Changing an RPC name or signature, or a packet layout, needs a `protocol_version` (or `packet_version`) bump in `release.json`, then `python tools/update-release-metadata.py --write`. Do not bump for anything else.
2. **Do not rename `NetworkBridge` RPC methods or move them to another node.** Godot identifies an RPC by node path plus method name, and both ends must match.
3. **Export allowlists.** Adding, removing, or renaming a file under `src/`, `scenes/`, `data/`, `resources/`, or `assets/` requires `python tools/update-export-policy.py` and committing the updated `export_presets.cfg`. CI rejects stale allowlists. Check with `--check`.
4. **New test suites** go in `tests/unit/<name>_tests.gd` and must be listed in `SUITES` in `src/test/test_runner.gd`. The runner fails the suite for any file that is not listed.
5. **New cards and maps** must be registered in `CardCatalog.DEFAULT_CARD_PATHS` and `MapRegistry.DEFINITIONS`. Tests fail for unregistered files.
6. **`docs/design/spec.md` is the contract for observable behavior.** If a change alters it, update the spec in the same change; never silently resolve a disagreement between code and spec.
7. **Layering.** Nothing under `src/shared` or `src/server` may reference `src/client`, `src/test`, or `tests/`. Server exports strip client code.
8. Typed GDScript throughout. Match the surrounding style of the file you are editing.
9. `docs/DEVELOPMENT.md` describes the current state only. Put dated evidence in `docs/archive/`, and take version numbers from `release.json` rather than copying them into prose.

## Verify in proportion to the change

All from the repository root. See `docs/DEVELOPMENT.md` section 11 for the full matrix.

| Change | Run |
| --- | --- |
| Docs only | Link/path review and `git diff --check` |
| Card values or resources | Unit suite; `verify-presentation.ps1` if visible text changes |
| Shared combat | Unit suite and `verify-match-loop.ps1`; `verify-network.ps1` if packets or authority changed |
| Combat, projectile, mine or NPC hot path | Also `run-performance-benchmark.ps1 -Map core_arena`, before and after |
| Lobby or NPC | Unit suite, `verify-npc-lobby.ps1`, `verify-match-loop.ps1` |
| Hosting or discovery | Unit suite, `verify-local-host.ps1`, `verify-network.ps1` |
| UI | Unit suite, `verify-presentation.ps1`, and inspection at 720p and ultrawide |
| Protocol codec | `verify-foundation.ps1`, `verify-network.ps1`, `verify-hardening.ps1`, `verify-match-loop.ps1`; consider a protocol bump |
| Before handoff | `verify-foundation.ps1` |

The open maintainability backlog is in [`docs/ARCHITECTURE-REVIEW-2026-11-09.md`](docs/ARCHITECTURE-REVIEW-2026-11-09.md).
