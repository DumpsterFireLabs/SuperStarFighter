# Super Star Fighter — maintainability and supportability review

Reviewed 2026-11-09 on `main` at `db37fd4`, release `0.1.0-beta.19`, protocol 52, packet format 18. The released build tagged `v0.1.0-beta.19` is protocol 50, so `main` is already incompatible with clients in testers' hands.

This document is a work backlog written to be handed to an implementing agent. Each item says what is wrong, where, what to do, and how to know it is done. Read "How to use this document" and "Ground rules" before starting any item.

## How to use this document

- Items are grouped by theme and carry a priority (P1 highest) and a rough size (S: under an hour, M: a few hours, L: a day or more).
- Items are independent unless a "Depends on" line says otherwise. Do them one at a time, one commit each.
- "Verified" means the claim was checked against the code during this review. "Inferred" means it follows from reading but was not executed; confirm before acting.
- Line numbers refer to the working tree at review time, which was `db37fd4` plus changes to seven files that have since been committed as `e3e4e73` (`README.md`, `docs/MANUAL.md`, `src/client/client_main.gd`, `src/client/input/input_profile_manager.gd`, `src/client/sandbox/lab_panel.gd`, `src/client/ui/settings_controller.gd`, `tests/unit/input_profile_tests.gd`). Line numbers therefore match `e3e4e73`.
- The recommended order is at the end.

## Scope and what was not reviewed

This review looked at structure: ownership boundaries, change cost, tooling, tests, CI, and documentation. It read the docs, the three prior reviews under `docs/archive/`, the CI workflows, the tool scripts, and the outlines plus selected bodies of the largest source files.

It did not look for gameplay bugs, balance problems, security holes, or performance regressions, and it did not run the integration, soak, impairment, or packaging gates. The prior reviews cover collision, fairness, replication ordering, and CPU budgets, and their fixes are in place.

Baseline at review time: see "Baseline" at the end.

## Ground rules for whoever implements this

These come from `docs/DEVELOPMENT.md` and from how the repository is set up. Breaking them fails CI or breaks compatibility.

1. **Behavior-preserving unless the item says otherwise.** Almost everything here is refactoring or tooling. No item should change gameplay, wire format, or RPC names, with one approved exception: A1 stage 3. For anything else, if a change would alter an RPC name, signature, or packet layout, stop: that needs a protocol bump in `release.json` and is out of scope.
2. **Run the unit suite after every item:** `.\tools\run-tests.ps1` (needs `.\tools\bootstrap.ps1` once). It must report `failed=0` and no unexpected `ERROR:` lines. For network-touching items also run `.\tools\verify-network.ps1` and `.\tools\verify-match-loop.ps1`. In a git worktree, the `.tools` folder must be linked in and `--import` run first or tests hang.
3. **Adding, removing, or renaming any file under `src/`, `scenes/`, `data/`, `resources/`, or `assets/` requires** `python tools/update-export-policy.py` and committing the resulting `export_presets.cfg`. CI rejects stale allowlists.
4. **New test files must be registered** in `src/test/test_runner.gd` (until item T1 lands). An unregistered file never runs.
5. **`docs/design/spec.md` is the contract for observable behavior.** These items should not need spec edits. If one does, the item has drifted out of scope.
6. **Do not rename `NetworkBridge` RPC methods or move them to another node** (A1 stage 3 is the one approved change to the RPC list). Godot RPC identity is the node path plus method name; both sides must match.
7. Typed GDScript throughout. Match the surrounding style in each file.

## What is already good — keep it

Do not "fix" these. They are the reason the codebase is in decent shape.

- Server authority, with the offline lab and client prediction running the same `AuthoritativeWorld` and `CombatantState.step_input` code.
- Layering is clean. Nothing under `src/shared` or `src/server` references `src/client`, `src/test`, or `tests/` (verified by grep on paths and on client `class_name`s).
- `StatMetadata` drives stat bounds, clamps, and display from one table. Adding a stat is one descriptor.
- Maps and cards are data resources with validation at load.
- `release.json` is the single release identity, with a checker.
- The error gate (exit code, completion marker, and no `ERROR:` lines) and its negative self-test.
- Transport and admission (`NetworkSessionOwner`) and replication (`NetworkReplicationScheduler`) are already split from the bridge.
- Server exports strip client and test code through explicit allowlists.

---

## A. Change amplification

These are places where one conceptual change needs edits in many files. They are the biggest maintainability cost in the project.

### A1. A lobby setting is hand-wired through about twelve places — P1, L

**Verified.** Tracing `random_powerups_permanent` end to end:

| Layer | Location |
| --- | --- |
| Field and default | `src/shared/models/match_config.gd:17` |
| Manual copy | `match_config.gd:98` (`duplicate_config`) |
| Validation | `match_config.gd` `validate()` (for ranged settings) |
| Authority and mutation | `src/shared/lobby/server_lobby.gd:335` `request_random_powerups_permanent` |
| Serialization to clients | `server_lobby.gd:579` in `serialize()` |
| Command wrapper | `src/shared/network/lobby_match_commands.gd:141` |
| Client send helper | `src/shared/network/network_bridge.gd:304` `send_random_powerups_permanent` |
| Server RPC handler | `network_bridge.gd:749` `request_random_powerups_permanent` |
| Operator/admin path | `network_bridge.gd:1261` inside the `operator_set_setting` match |
| Admin UI setting list | `src/client/ui/admin_panel.gd:9` |
| Lobby UI read and write | `src/client/ui/lobby_screen_controller.gd:637` and `:963` |
| Presets | `src/shared/lobby/match_presets.gd:54` |
| Match payload | `src/shared/match/authoritative_match_coordinator.gd:954` |
| Docs | `docs/MANUAL.md`, `docs/SERVER_README.txt` |

There are about fifteen such scalar settings. `network_bridge.gd:606-900` is roughly 300 lines of near-identical RPC handlers, each of which is: check role, get sender, `_accept_control_request`, forward to `commands`. `lobby_match_commands.gd` then has a matching function per setting that calls the lobby and either broadcasts or rejects. `operator_set_setting` (`network_bridge.gd:1220-1295`) repeats the type check and dispatch a third time.

**Why it matters.** Forgetting one layer produces a setting that works from the lobby but not from the admin console, or that silently resets when the config is copied. `duplicate_config()` is the sharpest edge: a new field that is not added there reverts to its default when the match starts, with no error.

**Action.** Do this in stages, each one shippable.

1. *Stage 1 (S, no wire change).* Make `MatchConfig.duplicate_config()` and `ServerLobby.serialize()`'s config portion derive from one field list, and add a unit test that sets every `MatchConfig` property to a non-default value, duplicates, and asserts equality by iterating `get_property_list()`. This closes the silent-revert hole immediately.
2. *Stage 2 (M, no wire change).* Introduce a setting descriptor table in `src/shared/lobby/` — one entry per scalar setting with id, type (bool/int/float), range, and the `ServerLobby` request callable. Rewrite `operator_set_setting` to look up the descriptor instead of the `match` block. Have `admin_panel.gd` read its setting list from the same table. Collapse the per-setting functions in `lobby_match_commands.gd` to one `apply_setting(sender_id, setting_id, value)` plus the handful with side effects (`player_limit`, `npcs_enabled`, which add and remove NPC entities).
3. *Stage 3 (M, protocol bump — approved by the owner on 2026-11-09 for the next beta, under the conditions below).* Replace the per-setting RPCs with one `request_lobby_setting(setting_id: StringName, value: Variant)` RPC validated against the descriptor table, and replace the matching `send_*` helpers on the client with one `send_lobby_setting`.

   *Why it is approved.* The released beta.19 (tag `v0.1.0-beta.19`) is protocol 50 and `main` is already at 52, so the next beta forces every tester to update anyway. Shipping stage 3 in that same beta costs testers nothing extra.

   *What it gains.* About 250 lines of near-identical handlers leave `NetworkBridge`. A new lobby setting then needs no new RPC, send helper, or handler, and so no protocol bump of its own. Sender, rate, type, and range checks happen in one place. There is no player-visible change. Most of the benefit of A1 comes from stage 2; stage 3 pays off in proportion to how many more lobby settings get added.

   *Conditions.*
   - Stage 2 is merged and passing first. Stage 3 is its own commit.
   - That commit bumps `protocol_version` in `release.json` by one and runs `python tools/update-release-metadata.py --write`. It is the only wire change in the commit.
   - The server rejects an unknown `setting_id`, a value of the wrong type, a non-finite float, an out-of-range value, and oversized strings or arrays, before touching the lobby. `Variant` from the network is untrusted. Add unit tests for each rejection.
   - Settings with non-scalar or multi-argument payloads (`team_assignment`, `player_color`, `player_appearance`, `npc_difficulty` per NPC, `map_pool`, `arena_effects`) may keep their own RPCs if folding them in would weaken validation. Collapse the scalar ones.
   - Before it ships, these pass: `run-tests.ps1`, `verify-network.ps1`, `verify-hardening.ps1`, `verify-match-loop.ps1`, `verify-npc-lobby.ps1`, and `src/test/lobby_flow_verifier.gd`. Update `src/test/bot_client_main.gd` and any verifier that calls the old `send_*` helpers.
   - It must land before the next beta is cut. If it is not ready by then, leave it out and hold it for the following beta; do not ship it later as a separate forced update.

**Done when.** After stage 2: adding a boolean lobby setting touches `MatchConfig`, the descriptor table, the `ServerLobby` request function, and the lobby UI — and nothing else on the server. A test fails if a `MatchConfig` field is missing from duplication or serialization.

### A2. `LobbyMatchCommands` reaches into the bridge's private methods — P2, M

**Verified.** `src/shared/network/lobby_match_commands.gd` holds a weak reference to the whole bridge and makes 66 calls to nine of its underscore-prefixed methods: `_broadcast_lobby_state` (23), `_send_request_rejected` (27), `_activate_added_npcs` (5), `_drain_match_coordinator` (4), `_remove_npc_entities` (3), and one each of `_broadcast_match_event`, `_log`, `_prepare_fresh_rematch`, `_start_match_coordinator`. It also reads `lobby`, `world`, `session`, and `match_coordinator` through bridge getters.

The 2026-10-22 review flagged this and it is still outstanding. The extraction moved code out of the bridge file without reducing coupling: the command service cannot be constructed or tested without a full bridge.

**Action.** Have command functions return a small typed outcome instead of calling back. Something like a `CommandOutcome` with `rejected_message: String`, `broadcast_lobby: bool`, `added_npcs`, `removed_npc_ids`, and `match_events`. The bridge applies the outcome in one place. Pass `lobby` (and the coordinator where needed) in explicitly. Then delete the weak reference.

**Depends on.** Best done together with A1 stage 2, since both rewrite the same functions.

**Done when.** `lobby_match_commands.gd` contains no `_bridge.` references and has unit tests that run with a `ServerLobby` and no `NetworkBridge`.

### A3. Match event names and state names are string literals scattered across files — P2, S

**Verified.** There are about twenty event types (`&"STATE_CHANGED"`, `&"DRAFT_OFFER"`, `&"PLAYER_ELIMINATED"`, ...) written as literals at each use; `&"STATE_CHANGED"` alone appears 16 times. Match state names are compared as strings (`"LOBBY"`, `"ACTIVE_HEAT"`, ...) in 17 files, 32 times in `client_main.gd`. A typo in either compiles and silently never matches.

**Action.** Add `src/shared/match/match_event_types.gd` with `const STATE_CHANGED := &"STATE_CHANGED"` and so on, and a matching constants holder for state names (or expose them from `MatchStateMachine`). Replace the literals. The wire values stay identical, so there is no protocol change.

**Done when.** `grep -rE '&"[A-Z_]{6,}"' src` finds event names only in the constants file (rejection reason codes can be a second pass), and no file compares `state_name` against a bare string literal.

### A4. The card catalog is a hand-maintained list of 137 paths — P3, S

**Verified.** `src/shared/cards/card_catalog.gd:4` lists every card path. There are 137 entries and 137 files today, but no test compares the list to the directory (no test references `data/cards` as a directory). A card file that is not listed is silently absent from the game.

**Action.** Add a unit test that lists `res://data/cards/*.tres` and asserts the set equals `DEFAULT_CARD_PATHS`. Keep the explicit list — order may matter for deterministic drafting, and directory listing behaves differently in exported builds. Do the same for `resources/maps/` against `MapRegistry.DEFINITIONS`.

**Done when.** Dropping a new `.tres` into `data/cards/` without registering it fails the suite with a message naming the file.

---

## B. Large files with several reasons to change

Line count is not the problem by itself. These files are listed because each mixes responsibilities that change for unrelated reasons, so unrelated edits collide and the regression surface for any one edit is wide.

### B1. `NetworkBridge` (1,783 lines) — P2, L

**Verified.** `src/shared/network/network_bridge.gd` is one class for both roles. It has 52 `@rpc` methods, 41 `if role != Role.SERVER` guards, and 52 client-role checks. Beyond RPC declaration it also owns:

- Server tick orchestration (`_physics_process`, line 369).
- Metrics collection and reporting (fields at lines 49-68, `_log_metrics` at 1503, `percentile_usec`, `_bounded_log_value`).
- Reconnect reservations (`_reconnect_tokens`, `_reconnect_reservations`, `_replaced_peers`, lines 73-79 and 1684-1763).
- The operator/admin command surface (lines 1126-1311).
- In-game admin challenge and proof flow (lines 504-604).
- Client ping (lines 922-960).

The RPC methods must stay on this node (ground rule 6). Everything else can move.

**Action.** Extract, in this order, each as its own commit with the bridge delegating:

1. `ServerTickMetrics` (RefCounted): the sample arrays, phase totals, window rotation, and the metrics dictionary. The bridge calls `metrics.record_tick(start, sim_done, coord_done, repl_done, active)` and `metrics.flush_if_due()`. Pure and easy to test. **S-M.**
2. `ReconnectReservations` (RefCounted): token issue, take, expiry, held-seat count, reserved-name sync. **M.** Run `src/test/reconnect_verifier.gd` afterwards.
3. `OperatorCommands` (RefCounted): `operator_status`, `operator_players`, `operator_kick`, `operator_restart_match`, block/unblock, `operator_set_setting`. Folds naturally into A1 stage 2. **M.**

After A1 stage 3 and these three, the bridge should be under about 900 lines and be recognisably "RPC surface plus composition".

**Done when.** Each extracted class has direct unit tests that do not construct a `NetworkBridge`, and the bridge holds no metrics arrays or reservation dictionaries of its own.

### B2. `ClientMain` (1,595 lines) — P2, M

**Verified.** `src/client/client_main.gd` already delegates settings, connection, draft, and standings to controllers. What remains mixed in:

- Splash sequence (lines 723-877), credits overlay (607-708), pause overlay (348-460), update notice and controller prompt dialogs (474-560) — each is self-contained UI construction.
- `_on_match_event` (line 1043): a 90-line `if/elif` chain over event names that mutates `match_state`, drives `network_world`, plays audio, and updates three controllers.
- HUD status text assembly (lines 1295-1437).

**Action.**

1. Move splash, credits, and pause overlay each into `src/client/ui/` following the existing controller pattern (`settings_controller.gd` is the model). These are mechanical. **S each.**
2. Turn `_on_match_event` into a dispatch table (`event_type -> Callable`) with one small handler per event. Move the pure state-reduction parts (for example the `PLAYER_ELIMINATED` alive-list update) into `ClientMatchState` as named commands so they can be unit-tested without a scene. **M.** Depends on A3 for the constants.

**Done when.** `client_main.gd` is under about 900 lines, and `ClientMatchState` has tests for each event's state effect.

### B3. `AuthoritativeWorld` and `ProjectileSimulation` share private state both ways — P3, M

**Verified.** `src/shared/combat/projectile_simulation.gd` is a set of static functions taking `world` and makes 41 accesses to `world._private` members. `authoritative_world.gd:522-584` is a block of twelve one-line forwarders back into `ProjectileSimulation`. The split is by file, not by interface: the simulation cannot run without the full world, and the world's "private" members are not private.

This is on the hot path. The performance acceptance margins are thin (see `docs/PERFORMANCE-ACCEPTANCE.md`), so treat this as low priority and do not restructure the stepping loop.

**Action.** Two cheap, safe steps only:

1. Check whether the twelve forwarders have callers outside `authoritative_world.gd` (tests may use them). Remove the ones that do not; point callers at `ProjectileSimulation` directly.
2. Rename the world members that `ProjectileSimulation` legitimately needs so they drop the underscore, or group them behind a small documented "simulation access" section. The aim is that an underscore means private again.

Run `.\tools\run-performance-benchmark.ps1 -Map core_arena` before and after and confirm no regression.

**Done when.** No file outside `authoritative_world.gd` reads `world._something`.

### B4. Other large files — note only

`lobby_screen_controller.gd` (1,044), `authoritative_match_coordinator.gd` (1,010), `network_session_owner.gd` (934), `server_lobby.gd` (838). These are cohesive enough today. The coordinator's reconnect handling (lines 218-415) and `ServerLobby`'s display-name sanitising (lines 590-680) are the obvious seams if either file needs to shrink later. No action now.

---

## C. Untyped boundaries

### C1. Dictionary payloads and `{"ok": ...}` results — P3, incremental

**Verified.** There are 174 `{"ok": ...}` dictionary literals in `src/` used as function results, and 264 `payload.get(...)` / `state.get(...)` reads under `src/client`. Callers must know the key names and re-cast every value. The project already has typed precedents: `MatchEvent`, `ObjectiveState`, `StatChange`, `ObjectiveStepResult`.

A wholesale conversion is not worth it. The dictionaries at the transport boundary are a deliberate choice and documented as such.

**Action.** Apply opportunistically, not as a project:

- When touching a `ServerLobby.request_*` function (A1, A2), return a small typed result (`ok`, `error`, `changed`, plus the NPC lists) instead of a dictionary.
- When touching `_on_match_event` (B2), decode each payload once into locals at the top of its handler rather than calling `payload.get` inline through the logic.

### C2. Collaborators typed as `Node` / `RefCounted` — P3, S

**Verified.** Several members are declared with a base type although only one concrete type is ever assigned: `input_profiles: Node` (`client_main.gd:37`, `client_view_context.gd:9`, `offline_sandbox.gd:62`), `powerups: RefCounted` (`authoritative_match_coordinator.gd:15`), `log_writer: RefCounted` (`server_runtime.gd:7`), `tutorial: RefCounted`, `lab: Node`, `remote_admin: Node`, `update_checker: Node`. 70 of 179 scripts under `src/` have no `class_name`, which is why these fall back to base types and why the code is full of `const XScript = preload(...)`.

**Action.** Give the scripts behind those members a `class_name` and tighten the declarations. This buys editor completion and parse-time checking of method names. One `has_method` check (`client_main.gd:566`) can go once `offline_sandbox` is typed. Adding a `class_name` is a file content change only; no export-policy update is needed.

---

## T. Tests

### T1. Test suites are registered by hand in a 260-line runner — P1, S-M

**Verified.** `src/test/test_runner.gd` preloads and calls every suite explicitly. Two suites (`connection_preferences_tests.gd`, `connection_screen_tests.gd`) are not in the runner and only run because `screen_controller_tests.gd:17-19` calls them — so the mechanism is already inconsistent. A new test file that nobody registers passes CI by never running. The runner also contains a leftover one-off branch, `--r22-only` (`test_runner.gd:34`), whose only other reference is an untracked script in `reports/`.

**Action.**

1. Add a guard test: list `res://tests/unit/*_tests.gd`, and fail if any file is neither invoked by the runner nor on an explicit "invoked by another suite" list. This is the cheap fix and should land first.
2. Add a `--test-filter=<substring>` user argument that runs only suites whose filename matches, and print per-suite assertion counts and elapsed milliseconds. Then delete the `--r22-only` branch — the filter replaces it.
3. Optional: replace the hand-written call list with a table of `{script, needs_tree, is_async}` entries iterated in order. Keep the order explicit; some suites may depend on it.

**Done when.** Adding `tests/unit/foo_tests.gd` without registering it fails the suite, and `-- --run-tests --test-filter=input_profile` runs one suite in a few seconds.

### T2. Suites are single static `run()` functions with no isolation — P3, incremental

**Verified.** Each suite is one `static func run(context)`; several exceed 900 lines (`network_protocol_tests.gd` is 1,754). A script error partway through aborts the rest of that suite, and the failure output gives a description string but no suite or section name. `TestContext` (`tests/support/test_context.gd`) prints one `PASS:` line per assertion, so a run produces a five-figure line count and failures must be found by grep.

**Action.**

- Add `context.begin_suite(name)` / `context.section(name)` so failures print `FAIL [suite › section]: ...`, and print a list of all failures again just before `TEST_SUMMARY`.
- Make per-assertion `PASS:` lines opt-in behind `--verbose-tests`. No script under `tools/` parses `PASS:` lines (verified by grep); the gates key on `TEST_SUMMARY`.
- Do not split the large suites for its own sake.

### T3. Tests leave temp files behind — P3, S

**Verified.** `reports/` holds leftover `accessibility-test-*.cfg` files, and `connection_preferences_tests.gd` writes `res://.tools/connection-preferences-<n>.cfg`. Writing under `res://` only works when running from source.

**Action.** Write test scratch files under `user://test-scratch/` and remove them at the end of each suite. Add a `TestContext.scratch_path(name)` helper so there is one way to do it.

### T4. Three places hold test code — P3, note

`tests/unit` (assertion suites), `src/test` (31 verifier and benchmark scripts launched by tool scripts, plus the runner and bot client), and `tests/integration` (two admin probes). The split between `src/test` and `tests/integration` is historical. Moving files means updating every tool script that names a path, so only do this if it is otherwise convenient; at minimum add a short `tests/README.md` saying which kind goes where and how each is launched.

---

## V. Verification tooling and CI

### V1. Two parallel tool stacks, and the engine pin and error gate are copied around — P1, M

**Verified.**

- The Godot version `4.7.2` is hard-coded in `tools/common.ps1:6-10`, `tools/bootstrap.ps1:11-12,117`, `tools/build.py:33-35,136`, `tools/ci-acceptance.py:9`, the default `--godot` path in six `verify-*.py` scripts and `benchmark-collision-queries.py`, and twice in `.github/workflows/packages.yml`. An engine upgrade means finding all of them.
- There are three bootstrap implementations: `bootstrap.ps1`, `build.py bootstrap`, and `ci-acceptance.py bootstrap()`. The last downloads to a different folder (`.tools/ci-godot`) and has no cache step in `acceptance.yml`, so every CI run on three operating systems downloads the engine.
- The "no `ERROR:` lines except the certificate-store one" rule is correctly centralised in `common.ps1` `Assert-SsfGodotResult` and `build.py` `validate`, but is also re-implemented inline in at least eight PowerShell scripts (`build-beta.ps1:109`, `build-server.ps1:33`, `verify-hardening.ps1:100`, `verify-match-loop.ps1:111`, `verify-network.ps1:202`, `verify-npc-lobby.ps1:99`, `verify-smoke.ps1:88`, `verify-soak.ps1:231`) and seven Python scripts (`ci-acceptance.py:40`, `verify-architecture-matrix.py:38`, `verify-dense-replication.py:59`, `verify-network-impairment.py:81`, `verify-packaged-interop.py:22`, `verify-wss-proxy.py:104`, `benchmark-collision-queries.py:41`). The copies already differ slightly (some use `lstrip`, some anchor at line start, one checks `SCRIPT ERROR` by substring).
- `verify-foundation.ps1` and `build.py foundation_gate` implement the same gate twice.

**Action.**

1. Put the engine version in one data file (extend `release.json` with an `engine` key, or add `tools/engine.json`). Read it from `common.ps1` (it already shells out to `release_metadata.py`) and from a new shared Python module. **S.**
2. Create `tools/ssf_tools.py` exporting `ROOT`, `godot_executable()`, `validate_godot_output()`, and `run_godot()`. Import it from `build.py`, `ci-acceptance.py`, and each `verify-*.py`. Delete the inline copies. Note the hyphenated script names cannot be imported, which is fine — they only need to import the shared module. **M.**
3. Replace the inline PowerShell gate copies with `Assert-SsfGodotResult`. **S-M.** Run each touched script once afterwards.
4. Make `ci-acceptance.py` reuse the shared bootstrap and add an `actions/cache` step to `acceptance.yml` keyed on the engine version, as `packages.yml` already does. **S.**

Do not try to delete either stack. PowerShell is the daily driver on Windows and Python is what runs on Linux and macOS CI. The goal is that shared facts live in one place.

**Done when.** `grep -rn "4\.7\.2" tools .github` hits one data file plus doc strings, and `grep -rn "root certificate" tools` hits two files (the PowerShell helper and the Python helper) plus the gate self-tests.

### V2. Most integration gates never run in CI — P2, M

**Verified.** `acceptance.yml` runs `tools/ci-acceptance.py`: import, startup, unit suite, forced-failure, dense replication, architecture matrix, reconnect, memory. The PowerShell integration gates — `verify-network`, `verify-match-loop`, `verify-npc-lobby`, `verify-hardening`, `verify-local-host`, `verify-admission-burst`, `verify-escort-drones`, `verify-presentation` — run only when a developer remembers to. `src/test/lobby_flow_verifier.gd` and `competitive_view_verifier.gd` are documented as manual commands.

**Action.** Add a Windows-only job to `acceptance.yml` that bootstraps and runs `verify-network.ps1`, `verify-match-loop.ps1`, `verify-npc-lobby.ps1`, `verify-hardening.ps1`, and the lobby-flow verifier. They are loopback-only and short. Leave soak, presentation capture, and impairment in the manual `extended` job. `verify-local-host.ps1` binds the LAN discovery port and must not run concurrently with other server fixtures; run it last or leave it manual.

**Done when.** A pull request that breaks the match loop or admission fails CI without anyone running a script locally.

### V3. The export allowlist is a manual step that fails late — P2, S

**Verified.** `tools/update-export-policy.py` regenerates the allowlists in `export_presets.cfg` (93 KB, mostly generated). Forgetting to run it after adding a file is caught only by CI or a package build. There are no git hooks and no `.editorconfig` in the repository.

**Action.** Add `tools/install-hooks.ps1` (and document it in `DEVELOPMENT.md` section 2) that installs a pre-commit hook running `python tools/update-export-policy.py --check` and `python tools/update-release-metadata.py`. Both take well under a second. Keep it opt-in; do not auto-install.

### V4. No static checks on GDScript — P3, S-M

**Verified.** `project.godot` has no `[debug]` GDScript warning settings, so warnings are at engine defaults and nothing treats them as errors. No formatter or linter is configured. Style is mostly consistent but drifts (111 single-line `if ...: return` forms beside the multi-line form, sometimes in the same block, e.g. `network_bridge.gd:667-688`).

**Action.** In `project.godot`, raise `debug/gdscript/warnings/untyped_declaration`, `unsafe_method_access`, and `unused_variable` and see how many hits the foundation parse sweep reports. If the count is manageable, fix them and set `untyped_declaration` to error — the project already claims typed GDScript as its baseline. If the count is large, record the number here and stop. **Inferred:** function parameters look fully typed (a grep for untyped first parameters found none), so the count may be small. Do not adopt an external formatter without the owner's agreement; it would rewrite every file.

---

## D. Documentation

### D1. `DEVELOPMENT.md` has turned into a changelog — P2, M

**Verified.** Sections 1-10 of `docs/DEVELOPMENT.md` are a structured guide. From section 11 on, and in everything after section 15, dated paragraphs have been appended describing individual changes. The result contains stale and contradictory statements:

- Line 126 says teardown "disconnects transport callbacks before closing ENet". The transport is WebSocket. (Flagged on 2026-10-22, still present.)
- Line 475 says "All ten shipped maps". There are twelve.
- Line 342 says "Compatibility version 34 and binary packet version 14 require matching clients and servers", line 469 says "Compatibility 30 is required", line 517 cites version 34 again. Current is protocol 52, packet 18.
- Lines 95-97 list `plan.md`, `spec.md`, and `milestones.md` at the repository root. They are under `docs/design/`.
- Section 11 opens with two long paragraphs about shield cues before the verification table it is named for.
- One-off validation tallies ("6,322 unit assertions", "69 rendered states") are embedded in prose.

An agent reading this file to learn the protocol version or map count gets the wrong answer.

**Action.**

1. Fix the four factual errors above. **S.**
2. Move every dated or "follow-up" paragraph after section 15, and the shield paragraphs at the top of section 11, into the relevant existing section as present-tense description of how the system works now — or delete it if `docs/archive/` already records it. Remove historical version numbers and assertion counts; refer to `release.json` instead.
3. Add a short "Where things are decided" table near the top: release identity → `release.json`; stat bounds → `StatMetadata`; maps → `MapRegistry`; cards → `CardCatalog`; lobby settings → the descriptor table from A1.
4. Add one rule to section 13: `DEVELOPMENT.md` describes the current state only; dated evidence goes in `docs/archive/`.

**Done when.** The file has no dates, no protocol numbers other than a pointer to `release.json`, and nothing after section 15 except appendices with a clear subject.

### D2. No root instructions file for coding agents — P2, S

**Verified.** There is no `CLAUDE.md` or `AGENTS.md`. The rules an agent most needs — regenerate the export allowlist, register new tests, how to run tests in a worktree, do not rename RPCs, bump the protocol for wire changes — are spread through a 540-line guide or not written down at all.

**Action.** Add a root `CLAUDE.md` of about forty lines: the test command, the "Ground rules" list from this document, the proportional-verification list from `DEVELOPMENT.md` section 11, and a pointer to `DEVELOPMENT.md` for the rest.

### D3. `docs/archive` — note only

162 files and 8.3 MB of dated evidence JSON are tracked. It has a `.gdignore`, so the editor skips it. It costs clone size only. No action unless the owner wants it moved out of the main tree.

---

## S. Supportability

### S1. Client diagnostics for bug reports — P2, M

**Verified.** The dedicated server writes structured JSON logs through a bounded worker with health windows. The client has an F3 overlay and prints one JSON line on lifecycle events (`client_main.gd:1576`), and nothing else. There is no client log of connection attempts, rejections, resyncs, prediction snaps, or settings-load failures beyond `push_warning`.

**Inferred, confirm first:** Godot's desktop default writes `user://logs/godot.log`; `project.godot` does not override file logging. Check that the exported Windows client actually produces that file.

**Action.**

1. Confirm the exported client writes a rotating log under `user://logs/`; if not, enable `debug/file_logging/*` in `project.godot`.
2. Log one startup line with game version, protocol, packet version, OS, renderer, and resolution. Log connect, admit, reject (with reason code), connection lost, and transport resync as single JSON lines in the style the server already uses. Never log passwords, tokens, or server addresses entered by the user.
3. Add an "Open log folder" button to the settings screen (`OS.shell_open` on the globalized `user://logs` path) and mention it in `docs/BETA_README.txt` under "Reporting a problem".

**Done when.** A tester can attach one file that shows build identity and the last connection attempt's outcome.

### S2. Settings file has no schema version — P3, S

**Verified.** `src/client/settings_store.gd` guards read-modify-write but the file carries no version key, and none of the preference owners (`connection_preferences.gd`, `accessibility_preferences.gd`, `input_profile_manager.gd`) reference one. Each loader tolerates invalid values individually. That works until a key is renamed or its meaning changes, at which point there is no way to tell old files from new.

**Action.** Write `meta/schema = 1` on every save through `SettingsStore.update`. Add a single `migrate(config)` hook that runs on load and is currently a no-op. This is cheap now and awkward to retrofit after a breaking change ships.

### S3. Hazard RNG is not seeded from the match seed — P3, S

**Verified, carried over from the 2026-10-22 review.** `src/shared/arena/arena_effect_state.gd:45` still calls `_flare_rng.randomize()`. A known match seed cannot reproduce Solar Crucible flare timing, which makes hazard bug reports unreproducible. Derive the hazard seed from match seed, round, and heat. No wire change.

### S4. Unknown map IDs fall back silently on the client — P3, S

**Verified, carried over from the 2026-10-22 review.** `src/client/presentation/arena_view.gd:54-58` still passes the ID through `ArenaLayout.normalized_map_id`, so a content mismatch shows plausible wrong geometry instead of an error. Reject unknown IDs where the match payload is received and disconnect with a clear message; keep the fallback for local authoring only.

---

## Recommended order

Quick wins first, because several are guards that make the larger refactors safer.

| Order | Item | Size | Why here |
| ---: | --- | --- | --- |
| 1 | T1 step 1 — unregistered-test guard | S | Protects every later item's tests |
| 2 | A1 stage 1 — `MatchConfig` copy/serialize test | S | Closes a silent-failure hole |
| 3 | A4 — catalog and map directory tests | S | Same kind of guard |
| 4 | D1 step 1 and D2 — fix doc errors, add `CLAUDE.md` | S | Stops agents reading wrong facts |
| 5 | A3 — event and state name constants | S | Mechanical; prerequisite for B2 |
| 6 | T1 step 2 — test filter and timings; drop `--r22-only` | S | Faster loop for everything after |
| 7 | V1 — single engine pin, shared gate helpers | M | Removes the most duplicated tooling |
| 8 | V3 — pre-commit hook script | S | |
| 9 | A1 stage 2 with A2 — setting descriptors, command outcomes | L | The main structural win |
| 10 | B1 — bridge extractions (metrics, reconnect, operator) | L | Easier after 9 |
| 11 | B2 — `ClientMain` overlays and event dispatch | M | |
| 12 | V2 — integration gates in CI | M | |
| 13 | S1, S2 — client log, settings schema | M | |
| 14 | D1 steps 2-4 — restructure `DEVELOPMENT.md` | M | After the code it describes has settled |
| 15 | T2, T3, C2, B3, V4, S3, S4 | S each | Opportunistic |
| 16 | A1 stage 3 — single lobby-setting RPC | M | Approved for the next beta; after 9 and 10, before the beta is cut, with its own protocol bump |

## Things considered and not recommended

- **Moving UI construction from code to `.tscn` scenes.** The scenes are six-to-nine-line stubs and all UI is built in GDScript. That is a consistent choice, it diffs and reviews well, and the presentation capture gate covers it. Converting would be a large rewrite for little gain.
- **Splitting `NetworkBridge` into separate client and server nodes.** RPC identity depends on node path and method name on both ends. The extractions in B1 get most of the benefit without touching the wire.
- **Replacing the custom test harness with GUT or gdUnit.** The existing harness is small, has no dependencies, and the gates are built around its output. T1 and T2 address its real gaps.
- **ECS, a transport change, or a language change.** Prior reviews reached the same conclusion; nothing here changes it.
- **Converting all dictionary payloads to typed classes.** See C1.

## Baseline

Unit suite run during this review on the working tree (including the owner's uncommitted changes), Windows, bootstrapped Godot 4.7.2:

- `TEST_SUMMARY passed=22255 failed=0`, exit code 0, no `ERROR:` or `SCRIPT ERROR:` lines.
- 83 seconds wall time, 22,319 lines of output.

Nothing else was executed. The integration, soak, impairment, presentation, and packaging gates were not run for this review.
