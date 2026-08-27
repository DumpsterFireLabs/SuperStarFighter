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
| Game version | 0.1.0-beta.1 |
| Protocol version | 8 |
| Automated suite | 1,666 assertions |
| Project gate | 79 checks |

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
.\tools\start-server.ps1 -Port 7000 -MaxPlayers 8 -RoundsToWin 2
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
                                       ├─ damage/shields/overtime
                                       └─ survivor/scoring decisions
                                              ↓
Client reconciliation ←─20 Hz player snapshots
Projectile presentation ←─spawn batches + 5 Hz corrections
Remote interpolation ←─buffered authoritative snapshots
Reliable UI/state ←─lobby, draft, match, score, results events
```

The client may predict local movement and shots for responsiveness, but it never decides legal positions, projectile creation, hits, damage, RNG, cards, scores, or winners.

### Main layers

- `NetworkBridge` owns ENet lifecycle, RPC direction, admission, rate limiting, serialization cadence, and logs.
- `ServerLobby` owns participant records, leadership, readiness, player limits, NPC fill, and lobby permissions.
- `AuthoritativeMatchCoordinator` connects draft, match state, combat world, and reliable match events.
- `AuthoritativeWorld` owns deterministic per-tick combat state.
- `NetworkWorldView` turns authoritative state into predicted/interpolated client presentation.
- `ClientMain` owns screen flow and production UI, not gameplay authority.

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

## 5. Authority and Protocol Rules

When adding networked behavior:

1. Decide it on the server.
2. Validate sender, state, ownership, bounds, and rate before mutation.
3. Use reliable control events for durable transitions and unreliable ordered packets for replaceable input/snapshots.
4. Bound every packet count, string, numeric range, and collection.
5. Keep the server free of client-only resources.
6. Add encode/decode, malformed/truncated, and integration coverage.
7. Bump the compatibility protocol when a wire-format or semantic mismatch would make old/new builds unsafe together.

The three logical channels are:

| Channel | Delivery | Use |
| --- | --- | --- |
| Control | Reliable ordered | Handshake, lobby, draft, match events, results |
| Input | Unreliable ordered | Latest local movement/aim/action frame |
| Snapshot | Unreliable ordered | Player state and projectile batches/corrections |

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
- Optional `auto_repair` or `beam_weapon` special behavior.

Example:

```ini
[gd_resource type="Resource" script_class="CardDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/shared/cards/card_definition.gd" id="1_card"]

[resource]
script = ExtResource("1_card")
card_id = &"rangefinder"
display_name = "Rangefinder"
description = "Projectile lifetime ×1.25 and speed ×1.10, but fire rate ×0.95 per stack."
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
|  | `projectile_count` | `shield_block_cost` |
|  | `projectile_spread_degrees` | `shield_depletion_threshold` |
|  | `projectile_lifetime` | `auto_repair_delay` |
|  | `pierce_count` | `auto_repair_rate` |
|  | `ricochet_count` |  |

Use `integer_modifiers` only for `magazine_size`, `projectile_count`, `pierce_count`, and `ricochet_count`.

### Adding a card safely

1. Create the `.tres` resource under `data/cards/`.
2. Add its path to `CardCatalog.DEFAULT_CARD_PATHS`.
3. Write a description that exactly matches its per-stack behavior.
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
2. Add it to `CombatStats.get_stat_property_names()` so duplication and comparisons preserve it.
3. Add it to `StatSystem.FLOAT_STATS` or `INTEGER_STATS`.
4. Add a generous technical clamp in `StatSystem._apply_clamps()`.
5. Consume the derived value in authoritative gameplay.
6. Mirror it in local prediction where the same simulation runs client-side.
7. Transport any presentation-critical derived result that clients cannot reconstruct.
8. Add stat derivation and direct gameplay-effect tests.
9. Update the specification's clamp table and card catalog.

Treat clamps as encoding/physics guardrails rather than quiet balance caps. The game's build identity depends on multiplicative escalation remaining visible.

## 8. UI and Presentation Work

The production UI is created by `ClientMain` and supports sixteen selectable resolutions across windowed and exclusive-fullscreen modes, including 2880×1920; borderless fullscreen follows the desktop resolution. Godot uses a 1920×1080 virtual canvas with `canvas_items` stretch and `expand` aspect, so alternate aspect ratios expose more world without nonuniform distortion.

Any material UI change should be checked at minimum at:

- 1280×720 for the tightest supported layout.
- 1920×1080 for the design canvas.
- 2560×1080 and 3440×1440 for ultrawide behavior.
- 5120×1440 for 32:9 super-ultrawide behavior.

`verify-presentation.ps1` captures 30 production states at all six acceptance resolutions, including 2880×1920, every built-in round map, ordinary settings, exclusive-fullscreen settings, and the live/final card-hover presentations. Inspect the relevant PNGs under `.tools/presentation-verification/`; passing file creation alone does not prove good composition.

Keep combat center space free where possible. Durable match information belongs in the compact upper-left HUD. Temporary center overlays should have precise authoritative timing and short exits.

Online Escape/settings screens must block local input without pausing the tree or server.

## 9. Audio Content

Music and SFX are discovered by filename. No code edit is required for ordinary replacement assets.

- Menu: `assets/audio/music/main_menu.mp3`, `.wav`, or `.ogg`.
- Gameplay: any supported files under `assets/audio/music/gameplay/`, played in filename order.
- Victory: `assets/audio/music/win.mp3`, `.wav`, or `.ogg`.
- SFX: named files under `assets/audio/sfx/`.

The exact cue list and fallback behavior are documented in the [audio drop-in contract](../assets/audio/README.md).

Do not commit audio without confirming its origin and project license. Let Godot produce `.import` metadata; never hand-author it.

## 10. Logging and Diagnostics

The authority writes one bounded JSON object per line with UTC timestamp, level, event name, and event-specific fields. It records startup/shutdown, admission, departures, rejections, match transitions, match seed, overtime, and periodic simulation metrics.

During a match, ten-second metric windows include connected peers, participants, ships, projectiles, mean/p95/max simulation time, outbound bytes, memory, object/node counts, and orphan-node count.

Do not log every input frame, unbounded collections, or client IP addresses. New logs must pass through the bridge's bounded logging helper.

Client `F3` diagnostics expose local FPS, round-trip time, input acknowledgments, prediction error/snaps, snapshots, players, projectiles, and interpolation information.

## 11. Verification Matrix

All commands run from the repository root after bootstrap.

| Command | Purpose | Typical use |
| --- | --- | --- |
| `.\tools\run-tests.ps1` | 1,666 deterministic assertions | After any gameplay/model/UI logic edit |
| `.\tools\verify-foundation.ps1` | Import, parse all scripts, startup modes, tests, forced-failure path, 79 project checks | Before commit/handoff |
| `.\tools\verify-network.ps1` | Real ENet admission, packets, authority, rejection, spectator, shutdown | Protocol/network changes |
| `.\tools\verify-match-loop.ps1` | Two deterministic complete matches, card pick, timeout, reset, rematch | Match flow, draft, rematch changes |
| `.\tools\verify-npc-lobby.ps1` | Solo human, NPC fill/config, NPC draft/combat | Lobby/NPC changes |
| `.\tools\verify-local-host.ps1` | In-process host, loopback admission, LAN discovery, clean shutdown | Hosting/discovery changes |
| `.\tools\verify-presentation.ps1` | 180 production captures at six resolutions | UI, map, text, theme, timing changes |
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

Integration outputs live only under `.tools/*-verification/` and are ignored by Git.

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

The source-playable vertical slice and hardening milestone are complete. The Beta 1 Windows client preset, repeatable package script, embedded-PCK executable, exported-client launch smoke, friend README, and Godot notice are implemented. Dedicated-server export, clean-machine install validation, release-mode soak validation, code signing, and final release-candidate artifact checks remain.

Until those pieces land, treat the repository bootstrap/start scripts as the supported distribution path for playtests.
