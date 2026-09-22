# Super Star Fighter — Development Guide

This guide is for contributors working on the Godot source project. For gameplay and hosting, use the [Player and Host Manual](./MANUAL.md). For exact observable requirements, use the [authoritative specification](../spec.md).

## Contents

1. [Project Baseline](#1-project-baseline)
2. [Setup](#2-setup)
3. [Repository Map](#3-repository-map)
4. [Runtime Architecture](#4-runtime-architecture)
5. [Authority and Protocol Rules](#5-authority-and-protocol-rules)
6. [Card Authoring](#6-card-authoring)
7. [Adding or Changing Combat Stats](#7-adding-or-changing-combat-stats)
8. [UI and Presentation Work](#8-ui-and-presentation-work)
9. [Audio Content](#9-audio-content)
10. [Logging and Diagnostics](#10-logging-and-diagnostics)
11. [Verification Matrix](#11-verification-matrix)
12. [Testing Conventions](#12-testing-conventions)
13. [Documentation and Spec Discipline](#13-documentation-and-spec-discipline)
14. [Git and Generated Files](#14-git-and-generated-files)
15. [Release Status](#15-release-status)

## 1. Project Baseline

| Area | Baseline |
| --- | --- |
| Engine | Godot 4.7.2 Standard, non-.NET |
| Language | Typed GDScript |
| Primary platform | Windows x64 |
| Renderer | OpenGL compatibility |
| Physics | 60 Hz |
| Network transport | ENet over UDP |
| Maximum participants | 32 |
| Game version | 0.1.0-beta.12 |
| Protocol version | 41 (binary packets 17) |
| Automated suite | Actual assertion count reported by `run-tests.ps1`; [dated evidence](./REVIEW-2026-09-03.md) |
| Project gate | Actual check count reported by `verify-foundation.ps1`; [dated evidence](./REVIEW-2026-09-03.md) |

The repository intentionally pins the engine. Avoid developing against a different Godot version unless the engine migration is itself the task and includes import, parser, behavior, documentation, and validation updates.

## 2. Setup

From PowerShell in the repository root:

```powershell
.\tools\bootstrap.ps1
```

The script downloads the official Godot 4.7.2 Windows archive, export templates, and checksum manifest. It verifies SHA-512 hashes and the executable's Authenticode signature, then prepares a self-contained editor under `.tools/godot/`.

Nothing is installed system-wide. Generated engine files, imports, logs, reports, and builds are ignored by Git.

Useful launch commands:

```powershell
.\tools\run-editor.ps1
.\tools\start-client.ps1
.\tools\start-server.ps1 -Port 7000 -AdminPort 7001 -MaxPlayers 8 -RoundsToWin 2
```

## 3. Repository Map

```text
assets/
  audio/                    Authored music/SFX drop-in locations
data/cards/                 One CardDefinition .tres resource per card
docs/                       Player and contributor documentation
scenes/
  bootstrap/                Shared startup scene
  client/                   Production client scene
  server/                   Headless authority scene
  test/                     Bot/test runner scenes
src/
  client/
    network/                Client world view, prediction, reconciliation
    presentation/           Audio and visual feedback
    sandbox/                Offline combat laboratory
  server/                   Dedicated-server entry controller
  shared/
    arena/                  Layout and authoritative collision
    cards/                  Definitions, catalog, and stat derivation
    combat/                 Shared authoritative combat model
    draft/                  Offers, locking, timeout selection
    lobby/                  Admission, readiness, NPC roster authority
    match/                  State machine, score, full coordinator
    models/                 Typed gameplay state
    network/                Protocol codecs, bridge, limits, discovery
  test/                     Scripted clients and presentation capture
tests/
  support/                  Test context/assertion helpers
  unit/                     Fast deterministic test groups
tools/                      Bootstrap, launch, integration, load tools
README.md                   Repository front door
plan.md                     Product direction
spec.md                     Authoritative implementation contract
milestones.md               Delivery and acceptance record
project.godot               Engine and input configuration
```

## 4. Runtime Architecture

The central design constraint is server truth.

```text
Keyboard/mouse or remappable controller/joystick profile
                         ↓
Client input frame ──30 Hz UDP──→ AuthoritativeWorld at 60 Hz
    ↓                                  │
Local prediction                       ├─ movement/collision
                                       ├─ weapons/projectiles
                                       ├─ damage/shields/shield rams/overtime
                                       └─ mode objectives/team scoring
                                              ↓
Client reconciliation ←─20 Hz player snapshots
Projectile presentation ←─spawn batches + 5 Hz corrections
Remote interpolation ←─buffered authoritative snapshots
Reliable UI/state ←─lobby, draft, powerups, match, score, results events
Objective presentation ←─4 Hz replaceable snapshots + reliable transitions
```

The client may predict local movement and shots for responsiveness, but it never decides legal positions, projectile creation, hits, damage, RNG, cards, scores, or winners.

### Main layers

- `NetworkBridge` retains every RPC name/annotation, sender-role validation, gameplay coordination, and measured outer server callback. `NetworkSessionOwner` owns transport/admission, authentication throttles, source bans, callbacks and teardown; it receives only a Godot transport host and a detached status callback. Signals request RPC sends and report lifecycle events. `NetworkReplicationScheduler` receives the current lobby/world explicitly and emits generated packets through typed signals, so it can run without a bridge or scene tree and cannot retain a prior match's world. Admission and replication internals have no writable bridge aliases. Public session observations expose detached lobby data. Teardown disconnects transport callbacks before closing ENet and clears replication through the bridge's lifecycle handler.
- `ServerLobby` owns participant records, leadership, readiness, player limits, NPC fill, game-mode/team assignment, timed-powerup configuration, player colours, and lobby permissions.
- `AuthoritativeMatchCoordinator` connects draft, match state, combat world and powerups, and remains the sole heat-transition owner. `HillModeHandler` and `FlagModeHandler` own typed objective state and stepping, returning typed outcomes and transition snapshots. `MatchEvent` queues serialize through the existing dictionary boundary; intermediate drop/pickup snapshots cannot be overwritten by later same-tick transitions.
- Every heat has a server-owned deadline 60 seconds after overtime begins. Unresolved Hill heats use the sole control-time leader (ties draw); other unresolved modes draw. Flag safe circles retain every base. `RespawnPlacement` scores clear positions inside the current safe circle against nearby enemies, incoming projectile paths, and mines, with a cached spatial threat index and at most two attempts per tick. Blocked respawns retry after half a second. Pickups are capped at eight, expire after 60 seconds, and leave the world through reliable removal events when they expire or fall outside overtime.
- Player replication shares a public body without cloaked combatants; only a cloaked owner's packet includes their hidden record and private correction trailer. Client disappearance clears ship, interpolation, and feedback history. Hill occupancy and flag pickup/carrying reveal cloak. Homing missiles and magnetic mines retain their existing interactions, so their public trajectories may provide clues.
- Static stars, grid, cover, and map labels draw through `ArenaStaticLayer`; animated objective/overtime redraws stay in `ArenaView`. Map changes invalidate static canvas commands. Objective ownership and navigation use the authoritative objective payload and local pilot/team identity.
- Draft offers and manual acquisition remain unlimited. NPC and timeout choices prefer offered cards with at least one effective stat benefit or newly enabled mechanic, falling back to the full offer when none qualify. The UI flags picks with no effective benefit. This does not rebalance overflow or remove drawbacks.
- `AuthoritativeWorld` owns deterministic per-tick combat state, including team-aware damage exclusion.
- `OfflineSandbox` runs the same `AuthoritativeWorld` as online play. `LabPanel` provides searchable cards, stack editing, five build presets, target count/health/distance and shield/fire/strafe settings, encounter reset, and measurement reset. Editing pauses the local range. Damage and DPS come from resolved hull damage; overkill and shield blocks are excluded, while missed shots and reload time remain in the active measurement window. Targets stay down until reset.
- `CombatFeedbackBuffer` coalesces authoritative hits, outgoing blocked shots, defender blocks, and the latest death recap into one bounded accumulator per recipient. The bridge drains it at 20 Hz over reliable private control events. Confirmations contain no target identity or position; recaps identify the source, killer and relevant mechanic, with life generation for stale-message rejection. Mine detonation visuals use separate actual-detonation events, never inferred projectile removals.
- `NetworkWorldView` coordinates lifecycle, match state and snapshot ordering. Persistent `NetworkLocalPrediction`, `NetworkReplicatedVisuals`, and `NetworkHudCamera` owners hold sampled input/replay, replicated drawing/interpolation, and HUD/camera/spectating state respectively. Compatibility accessors are explicit; hot paths call owners directly. Shared `ArenaView`, `CombatShipView`, and `ProjectileLayer` live in `client/presentation` and are used online and in the lab.
- `ClientMain` coordinates navigation, gameplay visibility/input blocking, and match presentation. `ui/settings_controller.gd` owns settings controls, accessibility/video preferences, binding capture and its timeout; `ui/connection_controller.gd` owns connection forms, LAN discovery, the embedded hosted runtime, lobby controls and appearance/password persistence. Both controllers are attached during root initialization so their lifetime follows the client. Explicit root accessors retain the existing capture/test interface without duplicating screen state. The shared `screen_navigation.gd` helper handles scoped joypad tab selection for both screens.
- `combat_tutorial.gd` drives seven action-based exercises inside the shared offline world: movement, confirmed hull damage, a completed manual reload, a real shield block, a real Perfect Guard, selecting/activating Afterburner, and a draft choice with effective stat changes. Training uses slow, low-damage practice fire but preserves real shield geometry and Perfect Guard timing. Retry/restart remain available; skipping, returning to the lab after completion, or leaving the range restores the saved lab build and target settings.

### Competitive hot paths

- `CombatSpatialIndex` bounds ship-overlap, ship-hit, and NPC projectile-threat candidate searches by arena cells instead of scanning every entity for every query. Its ship-sweep index expands occupied cells once per living ship for ordinary projectile/missile radii. A short sweep inside one cell borrows that cell's candidate array without allocating; multi-cell sweeps merge candidates in stable order. Larger radii use the general padded query. Callers must not mutate borrowed arrays, and every candidate still passes the unchanged narrow-phase collision test.
- `ProjectileRegistry` keeps indexed global/owner order, O(1) live counts, tombstoned removal, and allocation-free ordered views for simulation and rendering loops. The existing 64-per-owner/1,024-global budgets include reserved mine allowances of 16 per owner and 512 globally. Ordinary fire evicts moving ordnance rather than deployed mines; excess mine deployment retires the oldest mine at the applicable allowance. Owner/global eviction counters make budget pressure observable.
- Arena layouts and radius-expanded projectile geometry are immutable shared caches. A world may retain a cache entry but must never mutate or clear it.
- Projectile messages are divided into messages no larger than 1,200 bytes. Four rotating partial corrections keep positions fresh; the fifth correction is a complete, chunk-assembled recovery snapshot.
- Client projectile replication merges those independent channels using wrap-aware tick/message versions per entity. Complete recovery prunes only entities without newer observations; retained removal history is bounded, and forgetting old history also advances the packet rejection floor. New draft/countdown boundaries reject prior-heat ordnance. Registry ID zero is reserved for removed slots; authoritative IDs are positive and predicted IDs negative. Ownership changes must use `ProjectileRegistry.transfer_owner()` so counts and queues remain consistent.
- Client build updates commit a detached build dictionary before refreshing ships and prediction. Respawn and cloak reappearance derive from that same saved build. Objective updates reject older ticks across periodic and reliable streams; within one tick, periodic final state supersedes intermediate transitions and a full match-state event supersedes both.
- Player snapshot bodies, roster views, team assignments, standings data, and common UI rows are reused until their source revision changes. NPC objective readers receive detached typed snapshots.
- Each player snapshot reuses the common body and appends a 63-byte recipient correction trailer (1,193 bytes at 32 players), including the owner's active ordnance, active mines, budget eviction count and elapsed input age in physics ticks. Replay excludes time already simulated by authority under a stalled acknowledgement; those input identities remain buffered until acknowledged. `CombatantState.step_input` is shared by authority and replay; local weapon, shield, and ability clocks restore from this trailer before replay. A 25-byte input packet carries a selected ability slot and a stable press identity distinct from its frame sequence. One owned ability is attempted per press; retransmissions retain both slot and identity. `SpecialAbilitySelection` cycles owned abilities, with remappable Q/E or controller D-pad left/right defaults. Human input expires after 0.5 seconds without a fresh frame.
- `ProjectileCorrectionAssembler` and `StandingsModel` keep packet reconstruction and result ordering out of the bridge and screen controller respectively.

### Match state

```text
LOBBY
  → DRAFT
  → COUNTDOWN
  → ACTIVE_HEAT
  → HEAT_RESULT
       ├─ next heat → COUNTDOWN
       ├─ next round → ROUND_RESULT → DRAFT
       └─ final win → MATCH_RESULT → leader exit → LOBBY
```

State deadlines use server ticks. UI countdowns derive from server time and must not create independent gameplay timers.

`GameModeRules` is the shared mode registry. Death Match remains the default. Team Death Match supports two through eight configured teams; Team Capture the Flag remains fixed to two. `ServerLobby` balances Auto seats around authoritative explicit assignments, enforces host/self/NPC permissions, and requires every team to be populated. The coordinator copies those assignments into the combat world and places each team in a distinct spawn sector at match start. King of the Hill awards cumulative uncontested control time toward a 20-second heat target, pauses scoring while the hill is empty or contested, rotates the hill each round, and enables temporary powerups by default. Both flag modes use a neutral center flag plus authoritative carrier/drop/reset state and require a return to the carrier's pilot or team base. All objective modes queue server-owned five-second respawns, published as deadlines so clients display the same countdown. NPC objective steering consumes only coordinator-owned snapshots and still yields to overtime safety.

## 5. Authority and Protocol Rules

When adding networked behavior:

1. Decide it on the server.
2. Validate sender, state, ownership, bounds, and rate before mutation.
3. Use reliable control events for durable transitions and unreliable ordered packets for replaceable input/snapshots.
4. Bound every packet count, string, numeric range, and collection.
5. Keep the server free of client-only resources.
6. Add encode/decode, malformed/truncated, and integration coverage.
7. Bump the compatibility protocol when a wire-format or semantic mismatch would make old/new builds unsafe together.

The six logical channels are:

| Channel | Delivery | Use |
| --- | --- | --- |
| Control | Reliable ordered | Handshake, lobby, draft, match events, results, private coalesced combat feedback at 20 Hz |
| Input | Unreliable ordered | Latest local movement/aim/action frame |
| Player snapshot | Unreliable ordered | Player transforms, resources, and local input acknowledgements |
| Projectile delta | Unreliable ordered | Projectile spawn/removal batches and actual mine detonations in chunks of at most eight |
| Projectile correction | Unreliable ordered | Rotating partial and periodic complete projectile recovery snapshots |
| Objective | Unreliable ordered | Replaceable hill/flag state at 4 Hz; durable objective transitions remain on Control |

LAN discovery is a separate bounded UDP query/response service on port `7359`. It advertises session metadata only and conveys no gameplay authority.

## 6. Card Authoring

Cards are data resources in `data/cards/`. `CardDefinition` supports:

- Stable `card_id`.
- Display name and complete per-stack description.
- Ship, Shield, or Weapon category.
- One of seven rarity tiers.
- Additive float modifiers.
- Multiplicative modifiers.
- Integer modifiers.
- Optional `auto_repair`, `beam_weapon`, `afterburner`, `mine_layer`, `rebound_shield`, or `cloak` special behavior.

Example:

```ini
[gd_resource type="Resource" script_class="CardDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/shared/cards/card_definition.gd" id="1_card"]

[resource]
script = ExtResource("1_card")
card_id = &"rangefinder"
display_name = "Rangefinder"
description = "Per stack: +25% projectile lifetime; +10% speed; -5% fire rate."
category = 2
rarity = 1
multiplicative_modifiers = {"projectile_lifetime": 1.25, "projectile_speed": 1.1, "fire_rate": 0.95}
```

Category values are `0` Ship, `1` Shield, and `2` Weapon. Rarity values are `0` Common through `6` Unobtanium.

### Supported numeric stats

| Ship | Weapon | Shield / repair |
| --- | --- | --- |
| `max_health` | `projectile_damage` | `shield_capacity` |
| `max_speed` | `fire_rate` | `shield_regeneration` |
| `acceleration` | `magazine_size` | `shield_continuous_drain` |
| `drag` | `reload_duration` | `shield_regeneration_delay` |
| `shield_acceleration_factor` | `projectile_speed` | `shield_arc_degrees` |
| `breakaway_cooldown` | `projectile_count` | `kinetic_vent_impulse` |
|  |  | `shield_block_cost` |
|  | `projectile_spread_degrees` | `shield_depletion_threshold` |
|  |  | `shield_ram_damage` |
|  |  | `shield_ram_min_speed` |
|  |  | `shield_ram_cooldown` |
|  | `projectile_lifetime` | `auto_repair_delay` |
|  | `pierce_count` | `auto_repair_rate` |
|  | `ricochet_count` |  |

Use `integer_modifiers` only for `magazine_size`, `projectile_count`, `pierce_count`, and `ricochet_count`.

### Adding a card safely

1. Create the `.tres` resource under `data/cards/`.
2. Add its path to `CardCatalog.DEFAULT_CARD_PATHS`.
3. Write a concise description that exactly matches its behavior. Start stackable effects with `Per stack:`, express multipliers as signed percentages, separate effects with semicolons, and state unlocks or requirements first.
4. Update the catalog in `spec.md`.
5. Add targeted derived-stat assertions where the card introduces a new interaction.
6. Run `run-tests.ps1`.
7. Run presentation verification if title or description length could affect the five-card layout.

Catalog validation rejects:

- Missing or duplicate IDs.
- Invalid metadata, rarity, modifier entries, or unsupported stats/specials.
- Exact mechanical duplicates.
- Same-stat, same-direction cards that merely change magnitudes.

That last rule is deliberately stricter than identity checking. A new card should create a different decision or synergy, not serve as an obvious higher-tier numerical replacement.

### Stacking semantics

Derived stats are recomputed from the complete build. Flat additions sum; multipliers compound; integer modifiers add; then broad technical clamps apply. There is no maximum stack count, and acquisition order must not affect the result.

Do not reintroduce a card cap in UI, resources, draft eligibility, or build state.

## 7. Adding or Changing Combat Stats

A new card-modifiable stat usually requires coordinated changes:

1. Define its base value in `CombatStats` or `GameConstants`.
2. Add one descriptor in `StatMetadata.DEFINITIONS`: full/compact names, unit, lower/upper guardrails, integer flag, and higher/lower/contextual polarity. Specify a dependent upper-bound property when needed.
3. Numeric property lists, integer/float groups, duplication, limit application and presentation are derived from that metadata. Do not add another naming or clamp table.
4. For a new special behavior, add its enabled-property mapping to `StatMetadata.SPECIAL_FLAGS`.
5. Consume the derived value in authoritative gameplay.
6. Mirror it in local prediction where the same simulation runs client-side.
7. Transport any presentation-critical derived result that clients cannot reconstruct.
8. Add stat derivation and direct gameplay-effect tests.
9. Update the specification's clamp table and card catalog.

Treat clamps as encoding/physics guardrails rather than quiet balance caps. The game's build identity depends on multiplicative escalation remaining visible.

## 8. UI and Presentation Work

The production UI is created by `ClientMain` with dedicated settings, connection/lobby, draft and standings controllers, and supports sixteen selectable resolutions across windowed and exclusive-fullscreen modes, including 2880×1920; borderless fullscreen follows the desktop resolution. Godot uses a 1920×1080 virtual canvas with `canvas_items` stretch and `expand` aspect, so alternate aspect ratios expose more world without nonuniform distortion.

Any material UI change should be checked at minimum at:

- 1280×720 for the tightest supported layout.
- 1920×1080 for the design canvas.
- 2560×1080 and 3440×1440 for ultrawide behavior.
- 5120×1440 for 32:9 super-ultrawide behavior.

`verify-presentation.ps1` captures production states at all six acceptance resolutions, including 2880×1920, offline combat, every built-in round map, lobby match options, the roster-opened colour wheel, ordinary settings, exclusive-fullscreen settings, arena powerups, and graphical draft/live/final card-hover presentations. The sequence also captures the guided introduction, mechanic identities, and a 32-player/1,024-projectile mixed-effects fixture at ordinary and maximum accessibility settings. Inspect the relevant PNGs under `.tools/presentation-verification/`; passing file creation alone does not prove good composition. `SSF_CROWD_RENDER_RESULT` reports `draw_submit_p95_usec` around forced render submission after warmup, plus active/drawn projectile and effect counts. This diagnostic excludes the rest of the frame and does not wait for GPU completion; it is not end-to-end FPS or a GPU performance acceptance result.

`CardIdentity` derives mechanic families and build-role labels from special behaviors and beneficial modifiers, rather than card names or rarity. `CardMechanicIcon` draws a shared geometric symbol in draft cards and inspection previews. Draft headlines show up to three effective full-build changes, prioritizing unlocks and retaining a visible drawback when present; limit markers and omitted-change counts direct players to the complete preview. Keep rarity color distinct from mechanic identity and preserve the exact full-build comparison.

Crowded combat caps transient effects at 96, with a 48-effect decorative admission limit and local damage/elimination cues taking priority over lower-priority bursts. Offscreen effects are rejected with a blast-aware margin. At 160 active projectiles, rendering removes redundant glow passes while preserving each in-view projectile, its weapon form and allegiance cues; culling does not remove authoritative ordnance. Static map grid/cover outlines remain subdued behind threats and objectives. These presentation budgets never change combat outcomes.

Keep combat center space free where possible. Durable match information belongs in the compact upper-left HUD, pinned to the viewport edge even when the other online HUD elements use the centered safe area. Hit feedback uses a 360-unit-wide, content-height translucent box; keep text opaque and allow longer death recaps to wrap. Temporary center overlays should have precise authoritative timing and short exits. The persistent Accessibility settings tab offers combat HUD scaling from 100% to 150%, reduced shake, reduced flashes, and a centered 16:9 HUD safe area, enabled by default on wider displays. These preferences apply to online combat and the offline range; effect reduction must preserve readable hit, shield, and blast cues. Verify keyboard/controller focus traversal and the largest scale at 720p and ultrawide.

Online Escape/settings screens must block local input without pausing the tree or server.

## 9. Audio Content

Music and SFX are discovered by filename. No code edit is required for ordinary replacement assets.

- Menu: `assets/audio/music/main_menu.ogg`, `.wav`, or `.mp3`.
- Gameplay: any supported files under `assets/audio/music/gameplay/`, played in filename order.
- Victory: `assets/audio/music/win.mp3`, `.wav`, or `.ogg`.
- SFX: named files under `assets/audio/sfx/`.

The exact cue list and fallback behavior are documented in the [audio drop-in contract](../assets/audio/README.md).

Do not commit audio without confirming its origin and project license. Let Godot produce `.import` metadata; never hand-author it.

## 10. Logging and Diagnostics

The authority writes one bounded JSON object per line with UTC timestamp, level, event name, and event-specific fields. It records startup/shutdown, admission, departures, rejections, match transitions, match seed, overtime, and periodic simulation metrics.

During a match, ten-second metric windows include connected peers, participants, ships, projectiles, mean/p95/p99/max server callback time, active-combat p95/p99 samples, phase means, projectile budget evictions, outbound bytes, memory, object/node counts, and orphan-node count. The legacy `*_simulation_usec` names now measure the bridge callback through pending admission, NPC/world simulation, match coordination, encoding, and RPC enqueue. Engine multiplayer polling outside the callback, OS transmission, rendering, and the periodic metrics log itself are excluded; do not present these values as end-to-end frame or network latency. Separate phase means identify world/NPC, coordination, and replication costs.

Do not log every input frame, unbounded collections, or client IP addresses. New logs must pass through the bridge's bounded logging helper.

Client `F3` diagnostics expose local FPS, round-trip time and variance, ENet loss/throttle, snapshot arrival jitter and gaps, interpolation extrapolation rate, prediction error/snaps, pending replay inputs, expired predicted shots, and the latest input acknowledgment.

## 11. Verification Matrix

Shield block and break cues come from bounded authoritative impact and depletion counts in the reliable `COMBAT_FEEDBACK` payload. Holding a shield or crossing its regeneration unlock threshold produces neither cue. Counts coalesce at the existing 20 Hz feedback cadence; public shield cues follow snapshot cloak visibility, while hit/guard totals remain recipient-private. Clients suppress duplicate, previous-heat, and more-than-one-second-old cues; newly visible or revived ships discard earlier cues. Offline practice drains the same shield events. Compatibility version 34 and binary packet version 14 require matching clients and servers. Player snapshots remain below the 1,200-byte budget at 1,191 bytes for 32 players.

Shield press and release samples send immediately through a reliable input RPC, sharing the normal admission, sequence and rate checks. A transition replaces the ordinary send when both fall on one sample, keeping traffic at no more than one input packet per physics sample. Late reliable samples cannot overwrite newer input. Shield input carries the most recent press identity for up to 15 sampled ticks (250 ms), including on subsequent released frames. A fresh identity re-arms through the ordinary release/activation rules and gives a recovered short tap one authoritative simulation tick; repeated packets cannot renew Perfect Guard or extend a released tap. Several coalesced taps recover the latest press, without queuing old actions for later playback. The recipient correction includes the consumed identity so replay cannot re-open a used window. Depletion locks, impact costs, arc coverage and regeneration remain unchanged. Local shield/guard-window rendering follows shared prediction immediately; block confirmation stays authoritative. The 250 ms guard deadline clears floating-point residue rather than granting an extra simulation tick.

`shield_timing_tests.gd` exercises production sampling, codecs, authority and replay across seeded delay, jitter, dropped initial packets, duplication, reordering and expiry schedules, plus same-tick multishot and exact guard deadlines. The real ENet impairment fixture additionally delivers two short taps into three-shot volleys and records delivery latency and energy cost. `python tools/verify-network-impairment.py --shield-only --seeds 3` isolates shield acceptance from the general ability-delivery phases and marks the scope in its evidence. Final convergence now includes shield energy, lock, activation, guard window and consumed press identity. Failed/expired attempts remain visible in the retry count. These checks do not implement lag compensation or promise delivery through a blackout longer than the retention interval; competitive balance and human reaction tests remain separate.


All commands run from the repository root after bootstrap.

| Command | Purpose | Typical use |
| --- | --- | --- |
| `.\tools\run-tests.ps1` | Complete deterministic suite; reports actual assertion count and rejects unexpected engine and script errors | After any gameplay/model/UI logic edit |
| `.\tools\verify-foundation.ps1` | Import, parse all scripts, startup modes, tests, forced-failure path, and project checks | Before commit/handoff |
| `.\tools\verify-network.ps1` | Real ENet admission, packets, authority, rejection, spectator, shutdown | Protocol/network changes |
| `.\tools\verify-match-loop.ps1` | Two deterministic complete matches, card pick, timeout, reset, rematch | Match flow, draft, rematch changes |
| `.\tools\verify-npc-lobby.ps1` | Solo human, NPC fill/config, NPC draft/combat | Lobby/NPC changes |
| `.\tools\run-performance-benchmark.ps1 -Map core_arena` | Selectable-map 32-Insane-NPC/1,024-projectile churn and 512-mine/512-projectile spatial-query cases, percentile timings and collision profiles | Combat, projectile, mine, NPC, or networking hot-path changes |
| `.\tools\verify-local-host.ps1` | In-process host, loopback admission, LAN discovery, clean shutdown | Hosting/discovery changes |
| `.\tools\verify-presentation.ps1` | Production captures at six resolutions, including training, card identities, the lab, accessibility settings and crowded combat | UI, map, text, theme, timing changes |
| `.\tools\build-beta.ps1` | Full foundation gate, Windows x64 export, rendered startup and packaged-audio inventory smoke, and friend ZIP | Beta/release packaging |
| `.\tools\verify-hardening.ps1` | Malformed/excessive peers isolated while healthy clients continue | Validation/rate-limit changes |
| `.\tools\verify-smoke.ps1` | Configurable 2–32 real-client short run | Capacity/performance smoke |
| `.\tools\verify-soak.ps1` | Long load, disconnect, late spectator, overtime, metrics summary | Performance/release acceptance |
| `.\tools\verify-milestone6.ps1` | Full foundation through configurable soak | Release-candidate gate |

Examples:

```powershell
.\tools\verify-network.ps1 -Port 18000
.\tools\verify-smoke.ps1 -ClientCount 8 -DurationSeconds 30 -Port 18010
.\tools\verify-soak.ps1 -ClientCount 32 -DurationSeconds 600 -Port 18020
.\tools\verify-milestone6.ps1 -ClientCount 32 -SoakDurationSeconds 600 -BasePort 18100
```

Integration logs live under `.tools/*-verification/` or `.tools/verification-logs/` and are ignored by Git. Tests, foundation checks, and gameplay studies share an error gate and use unique absolute engine log paths. The gate requires the expected exit code and completion marker and rejects `ERROR:` and `SCRIPT ERROR:` lines. Its default exception is the exact Windows root-certificate-store diagnostic; foundation import checks retain their explicit directory-diagnostic allowances. `verify-test-gate.ps1`, also run by foundation verification, confirms that a real engine error fails the gate even with a passing summary and zero exit code. Gameplay study JSON is written to the requested `-OutputPath`.

### Choosing proportional verification

- Documentation-only change: link/path review plus `git diff --check`.
- Card value/resource change: tests; add presentation verification for visible copy changes.
- Shared combat change: tests plus match loop; add network verification if packets/authority changed.
- Lobby/NPC change: tests plus NPC lobby and match loop.
- Hosting/discovery change: tests plus local-host and network verification.
- UI change: tests plus presentation captures and visual inspection at 720p and ultrawide.
- Protocol codec change: foundation, network, hardening, and match loop; consider protocol bump.
- Release candidate: complete Milestone 6 gate at 32 clients and ten minutes.

## 12. Testing Conventions

Tests use `TestContext` assertions and run headlessly through the project's test startup mode. Behavior assertions should state the contract they protect, not mirror implementation names without meaning.

Good regression coverage normally includes:

- Boundary values and one value just outside each boundary.
- State before, at, and after a deadline tick.
- Repeated/duplicate/out-of-order network inputs.
- Reset followed by a second use of the same session object.
- Serialization round trips and malformed/truncated data.
- One-stack and repeated-stack card values.
- Direct gameplay consumption of newly derived stats.
- Smallest supported UI size.

The foundation script deliberately runs a forced-failure test and expects its nonzero exit. Seeing that one intentional failure in the verbose gate output is normal when the script itself ultimately reports success.

The performance benchmark is an overload regression gate: it combines all 32 participants at Insane decision quality with the global ceiling of 1,024 active projectiles, then separately holds 512 armed mines alongside 512 moving projectiles to guard the mixed spatial-query path. The main case fails above 20 ms p95, 24 ms p99, or 30 ms maximum; the mixed-mine case fails above 12 ms p95 or 20 ms maximum on the development machine. Use `-Map` with a catalog map ID to inspect collision-heavy layouts. Opt-in `AuthoritativeWorld.last_projectile_profile_usec` separates mine setup, guidance, obstacle/ship/mine sweeps, hit resolution, and damage resolution; `sweep_count` and `ship_candidates` in that dictionary are counts, not microseconds. These world benchmarks do not replace the real-client soak: it requires active-combat samples and enforces p95 below 16,667 microseconds for both active-combat and all-callback windows, including coordination and replication.

Dedicated-server metrics also report the count and percentage of ticks exceeding the 60 Hz simulation budget. Treat sustained overruns as a release blocker even when mean latency remains low. Match randomness is generated cryptographically in production and is not sent to clients; `--test-match-seed` remains available only for deterministic server test runs.

Keep common-case work proportional to active features: human-only matches do not rebuild the NPC projectile-threat index, empty mine registries do not receive mine scans, empty powerup collections do not sort participant IDs, waiting lobbies do not emit combat snapshots/corrections, and ship separation ends after the first overlap-free pass. The overload benchmark intentionally enables NPCs and fills the global projectile budget so those fast paths cannot conceal a worst-case regression.

## 13. Documentation and Spec Discipline

`spec.md` is the source of truth for observable behavior. When a change is intentional:

1. Update code and data.
2. Update or add tests.
3. Update `spec.md`.
4. Update this manual or README if players/contributors are affected.
5. Record milestone evidence when completing a named milestone or substantial post-milestone increment.

Do not silently resolve a disagreement between code and the specification. Either fix the implementation or explicitly change the contract.

## 14. Git and Generated Files

Do not commit:

- `.godot/` import/cache state.
- `.tools/` engine downloads, logs, captures, and load summaries.
- `builds/`, `logs/`, or `reports/` output.
- Editor metadata or local export credentials.

Do commit intentional source, scene, resource, documentation, and project configuration changes. Preserve unrelated working-tree changes and user-provided audio assets unless they are explicitly in scope.

Before committing:

```powershell
git diff --check
git status --short
```

Use a commit message that describes the player/developer outcome rather than a vague implementation activity.

## 15. Release Status

The source-playable vertical slice and hardening milestone are complete. Beta 10 has Windows x64, Linux x64, Linux ARM64/Raspberry Pi, and universal macOS client presets with repeatable package scripts; Windows receives a rendered launch smoke check, Linux receives architecture-specific ELF/package verification, and macOS receives `.app`, metadata, embedded-version, and universal Mach-O verification when cross-built on Windows. Only the Windows x64 Beta 10 package has been built so far; Beta 9 remains the latest Linux and macOS package set. Beta 1 through Beta 9 remain archived in their own output folders. A stripped Windows dedicated-server artifact and short packaged-server 32-client soak are now verified. Clean-machine install validation, native platform acceptance, longer representative-hardware performance testing, signing/notarization and final release-candidate checks remain.

Every tester-facing rebuild must increment the displayed game/build version and package/executable identity before export. Never replace a shared artifact under the same version label; each beta is retained in its own versioned output folder.

The review-validation client and dedicated-server artifacts are local verification builds, not a new tester-facing beta release. Bootstrap/start scripts remain available for source playtests.


## Gameplay observations and repeatable studies

`tools/measure-gameplay.ps1 -Section pacing -Seeds 2` simulates three complete heats for each supported mode at 2, 8, and 32 pilots. `-Section balance -Seeds 10` records target-aware draft availability, derived-stat saturation, mirrored archetype bouts, and controlled next-heat bye/pickup comparisons. `-Section fairness -Seeds 3` runs paired temporary/permanent pickup matches. `-OutputPath reports/name.json` selects the output; directories are created automatically. These are exploratory measurements, not pass/fail balance targets. See [the dated study](./GAMEPLAY-STUDY-2026-09-03.md) for methods, results, and limits.

`MatchObservations` keeps at most 128 completed heat rows per coordinator. It records actual first combat contact (shield blocks count; overtime does not), post-respawn eliminated time, actual draft time, turnaround, starting/ending builds, draft byes, and both temporary and permanent pickup cohorts. Missing contact or a next-round transition remains null. Production servers emit `heat_observation` summaries and `heat_player_observation` cohort rows at heat results; these study rows are not additional client RPCs. Existing logger bounds retain at most 16 card types per logged build and set `build_log_truncated` if larger; the 128-row in-memory history and JSON study outputs retain complete builds. Objective contributions are a separate public, cumulative match payload and reset with a fresh coordinator.

Run the real preset/rematch RPC acceptance with Godot `--headless --path . --script res://src/test/lobby_flow_verifier.gd`. It verifies host and guest authority, atomic presets, replicated fresh results, and build/score resets over localhost ENet. Compatibility 30 is required because the RPC surface changed (presets/rematches in 29, competitive view in 30); binary input and snapshot formats remain version 12.

The same lobby-flow fixture now verifies guest rejection, host replication, midmatch locking, and rematch retention for competitive view. Run `--headless --path . --script res://src/test/competitive_view_verifier.gd` for six-resolution resize, camera-world extent, aim-center, and expanded-layout restoration checks. The production presentation gate also records `competitive_combat` at all six resolutions.

## Map resources and typed comparison contracts

All ten shipped maps are explicit `MapDefinition` resources under `resources/maps/`, preloaded in ordered `MapRegistry.DEFINITIONS`. Identity, geometry, all 32 full-precision spawn anchors, palette, material family and central decoration radius live in those resources. `ArenaLayout` retains the compatibility/query facade. Registry validation rejects malformed geometry, unknown material families, invalid/missing or duplicate identity, and unsafe/overlapping spawns before publishing cached read-only cover/circle/palette views. Spawn callers receive their own array for shuffle/selection. `MapRegistry.definition()` returns an editable deep copy, including nested movement-field Resources; runtime identity queries read cached scalar values directly. Movement fields publish as shared `ArenaMovementField` values with read-only properties backed by a frozen value dictionary. Authority, replay and rendering reuse those values without per-tick Resource copies; authoring edits cannot alter a running field. To add a map, author its resource, register it once, and pass geometry, egress/navigation, all-mode objective and capture checks. Dynamic hazards remain separate future work.

`StatSystem.compare_pick_typed` returns `StatChange` values directly to card preview, lab and tutorial logic; `CardIdentity.summarize_typed` consumes them. The old dictionary comparison/summary APIs are compatibility adapters. `CardDetailsText.modifier_rows` supplies one nominal effect formatter to accessible tooltips and graphical hovers; `StatMetadata` also formats effective values and lab stats. Counts, seconds, degrees, rates, multipliers and fractional percentages have explicit units.

Typed contracts deliberately focus on mutable objectives, transitions, queued event envelopes and effective stat comparisons. NPC steering consumes detached `ObjectiveState` snapshots with integer-keyed capture zones. Dictionary serialization occurs at the transport boundary. The coordinator prepares heat spawns, resets objectives, and warms navigation before publishing countdown state, so the first payload contains the current heat's bases and map. Draft and result events retain their existing ordering. Objective contract tests exercise all three objective modes across multiple heats and a round map change, as well as snapshot mutation isolation. General match payload contents, score/build dictionaries, observation rows and existing transport decoders remain explicit compatibility boundaries. These objective changes preserve the existing RPC schemas and packet layouts.

Regression fixtures in `tests/fixtures/map_layout_baseline.json` and `stat_derivation_baseline.json` were captured from `bca4185` before this extraction. They preserve every shipped map coordinate/palette and full-precision hashes for all 136 cards at 1/3/20 stacks. They detect unintended geometry or gameplay drift; update them only alongside a deliberate reviewed rules/content change.

## Impaired delivery and shipping verification

```powershell
python tools/verify-network-impairment.py --seeds 3
python tools/update-export-policy.py --check
python tools/verify-attribution.py
./tools/build-server.ps1
./tools/verify-soak.ps1 -ClientCount 32 -DurationSeconds 90 -ServerExecutable builds/server/SuperStarFighter-Server.exe
```

The impairment harness needs Python 3.11+ and the bootstrapped engine. It binds only loopback UDP, starts a hidden Godot child and changes no firewall or operating-system network rules. Baseline, latency/jitter, loss, reorder/duplication, blackout and combined profiles affect real ENet traffic in both directions, including control traffic. A `tail_loss` profile drops traffic during settlement to exercise retry of the final neutral input. The fixture resends one stable neutral sequence at the normal input cadence until it is acknowledged, then separately checks replay drainage and durable resource equality. Coverage is established before cloak inhibits weapons. Logs include pending count and sequence bounds, server/snapshot acknowledgments, cooldown/shield state, neutral retry count, movement correction p95/p99/max and snap count.

Every invocation writes a unique folder under `.tools/network-impairment/`, with per-seed logs, fault counters, and an incrementally written summary that retains failures. `--profile`, `--seed`, `--seeds` and `--port` select a bounded run; proxy randomness is seeded, but OS scheduling can still change datagram grouping. Full match transitions and population load have separate gates. Run the LAN discovery/local-host gate after other server fixtures have stopped because they share the discovery port. That gate now verifies teardown and reconnect on the same client.

Ability presses retain their original identity/slot until the server's private correction acknowledges consumption, or at most 1.25 seconds. An input acknowledgement alone does not prove the press arrived. Server identity deduplication prevents repeated spending. Countdown, death/revival, blocked controls and disconnect cancel pending delivery. There is no new RPC, packet field or reliable backlog.

`tools/update-export-policy.py` generates selected-resource lists for all presets. Run it after adding/removing runtime files. Shared roots include server/shared scripts, bootstrap/server scenes, cards and maps; clients additionally include client/gameplay scenes, client scripts and assets. Tests, tools, reports and unknown roots are excluded before compilation. Filtering only in an export callback is insufficient because a compiler plugin may already have emitted bytecode.

`tools/audit-package.py` checks the actual PCK directory, per-entry MD5, allowed resource/remap targets and required content. It supports embedded Windows/Linux packs and a macOS ZIP containing one PCK. Build scripts validate allowlist freshness and attribution inventory, audit packs, and include both engine notice files. Native cross-platform acceptance remains separate. `build-server.ps1` also runs foundation and starts the executable outside the source directory without `--path` or `--server`. The export feature selects dedicated-server mode; stripped test/bot modes are unavailable in shipping builds.

The Windows server uses the official engine template with about 532 KB of game resources; renderer code is not compiled out of the engine binary. `verify-soak.ps1 -ServerExecutable` uses the packaged authority with source-based load clients and records that distinction. Release templates report zero for Godot's debug static-memory monitor; treat this as unavailable, not a zero-memory claim. Representative OS memory measurement remains R25. See [the attribution inventory](./ATTRIBUTION.md) for asset-origin records and unresolved owner confirmations.


Ability presses use the same reliable `action_input` RPC as shield transitions (compatibility version 34). Each sampled edge sends immediately, including between ordinary 30 Hz sends. Simultaneous shield/ability edges share one packet. Ordinary input retains the selected ability and press identity until authority acknowledges consumption or the 1.25-second retry deadline. Identity deduplication prevents double spending; newer input supersedes late reliable samples. The retry deadline bounds redundant sampling, not reliable transport latency during an outage. See [network delivery follow-up](NETWORK-DELIVERY-FOLLOWUP-2026-09-04.md) for acceptance evidence.

Connection preferences now own appearance serialization, endpoint normalization and pending password persistence in `connection_preferences.gd`. The settings path is injectable; tests use isolated files. Admission commits a pending preference, while cancellation/reset discards it. Writes preserve unrelated settings sections and refuse to overwrite a file that could not be read. The connection controller owns modal dismissal and connection-screen reset; the root coordinates gameplay navigation through `dismiss_modal()`, `reset_connection()` and `is_hosting()`. Fifty connection field aliases and fifteen forwarding methods were removed from the root; capture and integration tools access the actual controller. Draft/settings compatibility surfaces remain separate follow-up opportunities.

Shared-address admission keeps two active authentication challenges per source and queues additional peers in arrival order. The queue shares the original ten-second handshake deadline and the existing ENet capacity; it does not reset failure or connection-attempt throttles. Queued peers cannot authenticate before their challenge. The authoritative server disables unused peer-to-peer relay announcements and sends lobby/gameplay broadcasts only to admitted, connected transports. Normal play retains a single broadcast serialization; admission/disconnect windows use filtered recipients.

Run `tools/verify-admission-burst.ps1` for three real-ENet 32-client bursts, match start, late spectator reconnection and mass disconnect cleanup. `-ChallengeDelayMs 0..300` controls a delay before challenge transmission, not full internet latency simulation. Every cycle must admit all 32 peers; unexpected engine errors fail the wrapper even if the fixture emits its success marker. See [admission fix evidence](ADMISSION-FIX-2026-09-04.md).

Connection refactor validation: 6,322 unit assertions; local hosting, LAN discovery, teardown and reconnect; 69 rendered 1280×720 presentation states, with host and full-lobby screens visually inspected; editor import and shipping allowlists. Preference tests cover reload, invalid stored appearance, successful versus cancelled admission, forgetting passwords, endpoint isolation and preservation of unrelated settings.

The gameplay study accepts `-Section shield` for paired base/multishot, shield/multishot and shield-mirror bouts across three maps, plus controlled frontal/arc/rear volleys. Schema 2 adds per-side shield activity, lock time, block/depletion counts and authoritative heat timeout classification. `tools/summarize-gameplay-followup.py` validates coverage and summarizes retained shield/pacing JSON. See the [gameplay follow-up](GAMEPLAY-FOLLOWUP-2026-09-04.md) for 54 bouts, 48 controlled cases and 135 pacing heats, and the [LAN playtest sheet](LAN-PLAYTEST-2026-09-04.md) for the human validation still required. These exploratory bot results do not change production balance values.


Architecture follow-up (17 September 2026): `ClientMain` and `NetworkWorldView` share a `ClientMatchState`; update through its commands rather than mutating a published dictionary. Published observations are recursively read-only and copied on network changes, not per render frame. Presentation owners consume `ClientViewContext` and explicit collaborators/signals. The old convenience properties and forwarding methods live in the test-only `NetworkWorldFixture`. Client projectile storage uses `ProjectileRegistry.presentation_store()` to preserve server membership independently of authority budgets; prediction expiry and complete recovery retire visuals.

Both hosting entry points compose `ServerRuntime`, including the bounded asynchronous log writer and draining shutdown. `SillyCombatObserver` is optional and owns only enabled cue policy/history; normal damage attribution and shield/hit feedback do not depend on it. Overtime logging reads the coordinator's compact observation rather than reconstructing a full match payload.

`src/client/settings_store.gd` owns the shared settings path and guarded read/modify/save operation. Preferences must preserve unrelated sections and return/report persistence failures through that boundary.

`release.json` is the canonical release identity. For the next release, edit that manifest and run `python tools/update-release-metadata.py --write`, then `python tools/update-export-policy.py`. Build scripts read the manifest through `tools/common.ps1` / `tools/release_metadata.py`; the shipping and foundation gates reject stale generated metadata. Run `python tools/test_release_metadata.py` to exercise release propagation without building packages. Updating metadata does not publish or overwrite a packaged release.
