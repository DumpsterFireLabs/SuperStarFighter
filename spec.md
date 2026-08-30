# Super Star Fighter — Vertical Slice Specification

**Status:** Approved implementation baseline  
**Engine:** Godot 4.7.2 Standard, GDScript  
**Primary platform:** Windows x64 client and Windows x64 headless server  
**Related documents:** [Product plan](./plan.md) · [Implementation milestones](./milestones.md) · [Player/host manual](./docs/MANUAL.md) · [Development guide](./docs/DEVELOPMENT.md)

This document is the authoritative contract for the vertical slice. It defines observable behavior, starting balance, technical interfaces, failure handling, and acceptance criteria. If it conflicts with `plan.md`, this document takes precedence. Intentional changes must update this specification and any affected milestone acceptance criteria together.

## 1. Product Definition

### 1.1 Goal

Deliver a complete, replayable multiplayer vertical slice in which at least one human connects directly to an authoritative server and 2–32 total human/NPC participants draft persistent build-modifying cards and fight through heats and rounds until one participant wins the match.

The slice succeeds when it proves all of the following:

- Mouse-aimed movement, shooting, and directional shielding feel responsive.
- The heat, round, match, and card-draft loop is understandable without developer guidance.
- The server remains authoritative and stable with 32 connected test clients.
- The game can be exported, started, joined, played to completion, and replayed on Windows.
- Gameplay and card values are data-driven enough to tune without changing the network protocol.

### 1.2 Intended Audience

The vertical slice targets PC players who enjoy short, chaotic, skill-based multiplayer sessions with run-specific build combinations. It is designed first for invited playtests and direct-IP sessions rather than public matchmaking.

### 1.3 Design Pillars

1. **Readable chaos:** Up to 32 players may be active, but local threats, shields, projectiles, and deaths must remain visually legible.
2. **Skill plus adaptation:** Aim, movement, timing, and positioning determine combat; cards alter tactics without replacing mechanical play.
3. **Fast recovery:** Elimination leads immediately to spectating and then the next heat, not a disconnected menu flow.
4. **Server truth:** Clients predict presentation but never decide movement limits, card rolls, hits, damage, scoring, or winners.

### 1.4 Out of Scope

The vertical slice does not include public matchmaking, a public internet server directory, accounts, progression between matches, chat, reconnect restoration, cosmetic unlocks, monetization, downloadable content, manual map selection/voting, advanced map-specific hazards, anti-DDoS infrastructure, or console/mobile/web exports. It does include bounded local-subnet discovery, automatic built-in map rotation, configurable team assignment, and selectable objective modes.

## 2. Terminology

- **Participant:** A human player or server-owned NPC admitted before a match starts and eligible to spawn in its heats.
- **NPC:** A server-owned participant that consumes a configured match seat but does not consume an ENet client connection.
- **NPC difficulty:** One authoritative per-NPC control profile selected by the lobby leader before launch; difficulty changes behavior quality but grants no hidden ship or weapon statistics.
- **Spectator:** A connected client that cannot affect the current heat or match.
- **Heat:** One last-ship-standing combat instance. Players respawn between heats.
- **Round:** A sequence of heats that ends when one player has won two heats.
- **Match:** A sequence of rounds that ends when one player reaches the configured round-win target.
- **Draft:** The simultaneous card-selection phase before each round, including round one.
- **Build:** The complete set of card stacks currently owned by a player.
- **Lobby leader:** The connected participant allowed to change lobby settings, eject other waiting humans, and start a match.

For more than two players, a round is not limited to three heats. Heats continue until one player accumulates two heat wins; different players may each hold one heat win simultaneously.

## 3. Runtime, Configuration, and Project Layout

### 3.1 Runtime Requirements

- Use the non-.NET Godot 4.7.2 Standard build and typed GDScript.
- Run gameplay physics at 60 ticks per second.
- Support persistent Windowed (default), desktop-native Borderless Fullscreen, and selected-resolution Exclusive Fullscreen modes with a minimum usable resolution of 1280×720 and a 1920×1080 virtual canvas. Settings provide sixteen 16:9, 16:10, 3:2, 21:9, and 32:9 choices from 1280×720 through 5120×2160, including 2880×1920 and 5120×1440 super-ultrawide, without changing authoritative gameplay. Use `canvas_items` with expand aspect so alternate aspect ratios expose additional world space without nonuniformly stretching ships, arena geometry, or UI.
- Default to keyboard and mouse: WASD, mouse aim, left mouse fire, right mouse shield, number keys 1–5 for card choice, left-click UI interaction, hold Tab for the scoreboard, and Escape for the pilot menu. Provide a persistent, explicitly selectable controller/joystick profile with analog movement, independent analog aim, fire, shield, scoreboard, pilot-menu, diagnostic, spectator, and complete UI-navigation actions. Every action in both profiles is individually rebindable; controller stick deadzone is configurable; each profile has an independent restore-defaults action.
- Multiplayer never pauses the server simulation. The pilot-menu overlay only captures local input.

### 3.2 Command-Line Contract

The same project supplies client, server, tests, and protocol test-client entry paths.

| Option | Applies to | Default | Behavior |
| --- | --- | --- | --- |
| `--server` | Server | Off | Starts authoritative headless server mode. |
| `--port=<1024-65535>` | Server/client | `7000` | Selects the ENet UDP port. |
| `--server-name=<name>` | Server | `Super Star Fighter Server` | Sets the bounded display name advertised to LAN browsers. |
| `--max-players=<2-32>` | Server | `32` | Limits admitted clients. |
| `--rounds-to-win=<1-5>` | Server | `3` | Sets the lobby's initial round target; the lobby leader may change it. |
| `--auto-start` | Tests only | Off | Starts when at least two test clients are ready. |
| `--bot-client=<name>` | Tests only | Off | Starts a headless scripted protocol client, not a gameplay AI feature. |
| `--run-tests` | Tests only | Off | Runs automated tests and exits nonzero on failure. |

Invalid numeric arguments produce a clear error, print accepted bounds, and exit with code 2. A server bind failure exits with code 3. Normal shutdown exits with code 0.

### 3.3 Repository Shape

Use the following top-level structure:

```text
project.godot
assets/              # UI assets plus authored or generated audio
data/cards/          # CardDefinition resources
scenes/              # Client, shared gameplay, arena, and UI scenes
src/client/          # Input, prediction, rendering, and UI controllers
src/server/          # Session, authority, validation, and server lifecycle
src/shared/          # Typed models, stat math, protocol constants, and simulation helpers
tests/               # Unit and integration test entrypoints
tools/               # PowerShell test, launch, soak, and export scripts
builds/              # Ignored generated exports
```

Client-only visuals must not be referenced by server-only startup code. Shared arena collision and gameplay resources must remain available in dedicated-server exports.

## 4. Session and Match Flow

### 4.1 State Machine

The server owns a single explicit state machine.

| State | Duration | Entry behavior | Exit condition |
| --- | ---: | --- | --- |
| `LOBBY` | Indefinite | Clear match-only state; admit humans and configure optional NPC fill. | Leader starts with 2–32 ready participants, or one ready human plus NPC fill. |
| `DRAFT` | 30 s max | Generate private offers for every participant. | Everyone selects or the timer expires. |
| `COUNTDOWN` | 3 s | Spawn/reset ships with controls locked. | Timer reaches zero. |
| `ACTIVE_HEAT` | Variable | Enable controls, combat, and the selected objective. | The selected mode's elimination or objective win condition resolves. |
| `HEAT_RESULT` | 2 s | Freeze combat and show heat result. | Continue current round or resolve it. |
| `ROUND_RESULT` | 2 s | Award a non-final round win and clear all heat wins. | Start the next draft. |
| `MATCH_RESULT` | Indefinite | Show winner and final builds/scores. | Lobby leader selects Play 5 More Rounds or Exit to Lobby. |

State transitions are reliable server events containing the new state, server tick, optional end time, and state-specific score data. Clients derive countdown displays from the server time, not local timers. A decisive final heat transitions directly from `HEAT_RESULT` to `MATCH_RESULT`, skipping the redundant two-second `ROUND_RESULT` intermission. `MATCH_RESULT` has no deadline and cannot advance from elapsed time. From final results, the lobby leader may add exactly five rounds and resume through `ROUND_RESULT`; scores and every permanent card stack remain intact, and the decisive-round winner receives the normal next-draft bye. The match returns to results after the fifth added round, with the total-round leader winning and that final round's winner breaking a tied total. This extension may be selected again after a later match result.

### 4.2 Lobby Rules

- The first admitted client is lobby leader. On leader disconnect, leadership transfers to the admitted client with the earliest join sequence.
- The leader may select Death Match, Team Death Match, King of the Hill, Capture the Flag, or Team Capture the Flag; configure Team Death Match for 2–8 teams without exceeding the participant limit; set `rounds_to_win` from 1 through 5; set the total participant limit from 2 through the server's configured capacity (never above 32); and enable the optional Random Spawn Powerups rule. Lobby settings cannot change during a match. Death Match is the default, Team Death Match defaults to two teams, and the powerup rule defaults to off except when entering King of the Hill, which enables temporary powerups by default.
- Each participant row in a waiting team-mode lobby exposes `Auto` plus every available team. The leader may change any participant; each human may change their own team; any connected human may change an NPC team; and a non-leader may not change another human. Auto seats are assigned deterministically to the least-populated team around explicit choices. Every configured team must have at least one participant before launch. Team Capture the Flag remains fixed to Cyan and Magenta because its maps provide two team bases. Assignments serialize to every client and lock for the active match. Teammates cannot damage one another with projectiles, beams, or shield rams, though physical separation still prevents overlap.
- Every human may click their own lobby-roster colour swatch to open an HSV wheel, then explicitly apply a custom RGB colour or select Random. Other players' and NPCs' swatches are visible but not locally editable. The preference persists locally, is validated and serialized by the server, and may change only while the match is inactive. Random uses the server's high-contrast palette.
- Every connected human, including the leader, enters the lobby not ready and must explicitly ready up before Start Match can succeed. Changing any lobby setting or returning from a completed match clears every human's ready state; NPCs are always ready. Readiness is authoritative and serialized in lobby state.
- The leader may eject another connected human only while the match is inactive. The leader cannot eject themselves or server-owned NPCs. An ejected client receives the `EJECTED` reason and returns to the connection screen.
- The leader may enable or disable NPC fill. Enabling it immediately creates one waiting NPC for every vacant configured seat so each can be configured before launch. Increasing the seat limit while NPC fill is enabled creates additional waiting NPCs; disabling it removes all waiting NPCs. Start Match requires two humans when NPC fill is disabled; when enabled, one human may start with the configured NPC roster. The button reads `Start Match` for ready multiplayer lobbies, `Start Match with NPCs` for a ready solo leader with NPC fill, and otherwise explains the missing requirement.
- Every waiting NPC has an independent leader-only difficulty dropdown with `Passive`, `Easy`, `Neutral`, `Skilled`, and `Insane`; `Neutral` is the default. A second leader-only bulk dropdown applies one difficulty to every current NPC and becomes the default for newly filled NPC seats. Difficulty changes are authoritative lobby settings, clear human readiness, serialize with the lobby/NPC, and are locked after match start.
- NPCs never become lobby leader. While the match is inactive, a joining human replaces one waiting NPC when all configured seats are occupied. Disabling NPC fill removes all waiting NPCs; lowering the participant limit removes enough waiting NPCs to meet the new limit and cannot reduce the limit below the connected human count.
- Display names are trimmed, must contain 1–16 printable non-control Unicode characters, and are made unique for display by appending `#2`, `#3`, and so on.
- A client joining during `DRAFT` or any later match state becomes a spectator until the server returns to `LOBBY`.
- Final standings remain open until the lobby leader sends the authoritative return-to-lobby request. Other players see that they are waiting for the leader.
- When a match returns to the lobby, connected spectators become normal participants and all builds and scores are cleared.

### 4.3 Draft Rules

- Every participant drafts before round one and before each later round. No draft occurs between heats in the same round.
- Before round one, the server creates an offer token and samples five distinct eligible card IDs for every participant using the match PRNG. Before later rounds, the previous round winner receives a locked draft bye and no card; in team modes, every member of the round-winning team receives that bye. Every other participant receives an offer. Human offers are private and rendered for selection; each eligible NPC immediately locks a server-selected card from its own offer.
- Every card remains eligible regardless of its current stack count. Card stacks have no maximum and repeated copies always apply their full additive, integer, multiplicative, or special effects.
- Selecting a card requires the current offer token and one card ID from that offer. Invalid, stale, duplicate, or out-of-state selections are rejected without changing the build.
- Choices lock immediately, but all chosen cards apply simultaneously when the draft ends. Other clients see only ready/not-ready status during the draft.
- If the timer expires, the server randomly selects one of that player's offered cards. If every player locks a choice early, the draft ends immediately.
- Every eligible drafter receives five distinct card IDs per offer. A card cannot repeat within one offer, but may appear again in every later round and may stack without limit.
- After the draft, all players may inspect every participant's selected card and aggregate build through the scoreboard.
- The server seeds the match PRNG once at match start and records the seed in server logs. Tests may inject a fixed seed; production clients never choose it.

### 4.4 Heat, Round, and Match Resolution

- Each heat starts every participant alive at full derived health, full shield energy, full magazine, and no active reload or repair timer.
- The selected lobby mode defines the heat winner:
  - **Death Match:** the final surviving pilot wins the heat.
  - **Team Death Match:** the final team among the configured two through eight teams with at least one living pilot wins the heat; team heat and round scores are mirrored on every teammate.
  - **King of the Hill:** a single uncontested living pilot scores time while inside the authoritative hill and wins the heat after accumulating 20 seconds. Leaving or contesting the hill pauses progress without erasing earned time. The hill moves to a distinct legal location after each round. Its overtime ring is centered on the current hill and retains a 350 px minimum diameter around the 250 px control point. Random temporary arena powerups default on for this mode.
  - **Capture the Flag:** the first pilot to collect the neutral center flag and carry it back to that pilot's marked launch base wins the heat.
  - **Team Capture the Flag:** the first team to collect the neutral center flag and carry it to that team's base wins the heat.
- King of the Hill and both Capture the Flag variants respawn eliminated pilots authoritatively after a five-second countdown. Objective-mode deaths do not resolve or tie a heat.
- A flag follows its living carrier, drops at the carrier's death position, may be recovered by another eligible pilot, and resets to center after eight seconds untouched. Hill, flag, pilot-base, and team-base positions are deterministic clear points derived from the active map and spawn assignments. The server owns pickup, occupancy, progress, drops, capture, and scoring. Controller changes, pickups, drops, and resets are reliable transitions; replaceable progress/position state is sent separately as an unreliable ordered snapshot.
- Random Spawn Powerups defaults off except in King of the Hill, where temporary drops default on. When enabled, the server starts a fresh leader-configured 5–90 second timer at heat unlock (20 seconds by default), then spawns one Rare-or-better card at each interval at a legal position clear of obstacles and living ships. Uncollected cards persist until collected or the heat ends; a nearby living human or NPC collects one authoritatively and receives the recomputed build immediately. Drops expire after the current heat by default; a separate default-off permanence toggle retains them until match end. Tier selection uses the configured rarity weights conditioned on Rare or above. Active pickups and effective builds are included in late-join state.
- Spawn assignments are chosen by the server each heat. Free-for-all modes shuffle the map anchors; team modes group teammates into distinct angular sectors while preserving a unique legal anchor per participant. Controls remain locked during the countdown. Every heat presents a centered `READY` alert during the lock. At exactly 0.10 seconds remaining it changes to `BEGIN`, remains through the first 0.10 seconds of authoritative control, and fades to transparent across that post-roll.
- A player at zero health is eliminated immediately and becomes a spectator for the remainder of the heat.
- In Death Match, when exactly one participant remains alive after a complete authoritative damage tick, end the heat immediately and award that player one heat win. In Team Death Match, resolve when only one living team remains. Objective modes remain active for a lone survivor so that pilot must complete the objective.
- When zero participants remain because multiple deaths resolve during the same server tick, award no heat win and replay the heat after `HEAT_RESULT`.
- The first player—or team in a team mode—to reach two heat wins gains one round win. All heat-win counters then reset to zero.
- The first player—or team in a team mode—to reach `rounds_to_win` wins the initial match. During a five-round results extension, that score trigger is suspended until all five added rounds finish.
- A participant disconnecting during `ACTIVE_HEAT` is eliminated before survivor resolution. Disconnecting during another match state removes the participant from subsequent spawns.
- If only one participant remains in the match after removals, that participant wins by forfeit. If none remain, return immediately to an empty lobby. NPC participants remain present without network peers.

### 4.5 NPC Difficulty Profiles

NPC difficulty modifies decision quality only. All tiers use the same derived card build, health, shields, movement limits, weapon rules, collision, and damage as a human participant. Decisions remain deterministic from server tick and NPC identity.

| Difficulty | Reaction | Aim error | Awareness | Movement pressure | Fire behavior | Shield / leading |
| --- | ---: | ---: | ---: | --- | --- | --- |
| Passive | 36 ticks / 600 ms | Up to 24° | 900 px | Gentle 0.18 pursuit and strafe | Never fires | Never shields; no leading |
| Easy | 20 ticks / 333 ms | Up to 14° | 1300 px | 0.42 pursuit, 0.32 strafe; light closing pressure | 900 px range; 32% burst duty | 5% shield duty; 25% travel-time leading; light dodge |
| Neutral | 10 ticks / 167 ms | Up to 7° | 1900 px | 0.65 pursuit, 0.50 strafe; moderate closing pressure | 1450 px range; 58% burst duty | 10% shield duty; 50% travel-time leading; moderate dodge |
| Skilled | 5 ticks / 83 ms | Up to 2.5° | 2600 px | 0.85 pursuit, 0.68 strafe; committed pressure/flanks | 2400 px range; 86% burst duty | Reactive shield; 78% travel-time leading; strong dodge |
| Insane | 1 tick / 17 ms | Up to 0.15° | 4000 px | Full pursuit, 0.85 strafe; relentless pressure/flanks | 4000 px range; 99% burst duty | Early reactive shield; full travel-time leading; strongest dodge |

Each tier also maintains a progressively tighter preferred engagement band. NPCs select the nearest living non-ally within their awareness range, periodically orbit/strafe, retreat when too close, and cannot fire while shielding. They ignore allied projectiles as threats and steer toward the current hill, flag, or carrier destination when an objective needs attention. Higher tiers keep closing pressure inside the ordinary engagement band, lead from actual projectile travel time, predict the closest approach of incoming enemy rounds, steer out of threatened lanes, and raise a reactive shield earlier as difficulty increases. NPC fire requires an unobstructed projectile line to the target. When an obstacle blocks a two-NPC engagement, higher tiers commit to flanking more readily; persistent occlusion is tracked per NPC, target, and obstacle. After three seconds without a sustained clear lane, a holder commits to the opposite flank; sightline interruptions shorter than one second preserve the blocked-loop timer, while at least one clear second resets it. During the overtime warning or active shrink, every NPC—including Passive—steers toward an achievable point inside the safe radius. Boundary escape takes priority over pursuit, with the strongest priority once the NPC is taking boundary damage.

## 5. Arena, Camera, and Spawning

- Every built-in map uses a 3200×1800 logical arena with an impermeable outer boundary.
- The roster contains Core Arena, Riftline, Prism Array, Twin Suns, Dead Freight, Longwave Array, Broken Orbit, Switchyard, Solar Tide, and Relay Zero. Each has distinct server-authoritative rectangle/circle obstacle geometry and a visible palette.
- The server derives a shuffled no-repeat map deck from the match seed without consuming draft or spawn randomness. Entering round one selects the first map; entering each later round advances once. All countdowns, active heats, ties, heat results, and the round result retain that round's map.
- The authoritative state payload includes `map_id` and `map_name`. Clients rebuild arena presentation/collision before countdown; late spectators receive the same current map.
- Every map exposes 32 validated spawn anchors. Spawn assignment is shuffled independently for every heat even though map selection remains fixed within the round.
- Free-for-all modes shuffle the anchor pool, then assign each next participant to the available anchor with the greatest clearance from every already-assigned spawn. This preserves seeded variation while preventing smaller lobbies from clustering in one portion of the map. Team modes first sort each team's assignments toward opposite sides of the arena, then place teammates without reusing anchors.
- Provide exactly 32 spawn anchors distributed around two symmetric rings. Anchors must not overlap obstacles and must keep at least 160 pixels between neighboring ships.
- Spawn anchors are assigned without replacement. Players receive no post-countdown invulnerability because all players gain control on the same server tick.
- Ships collide with walls, obstacles, and other ships using slide response. Pair separation transfers any wall- or cover-blocked correction to the movable ship, removes inward velocity, applies an outward impulse, and searches deterministic nearby legal positions if ordinary correction cannot untangle a pair or cluster. Client prediction also excludes the local visual from remote ship circles between snapshots. Base collisions deal no damage; a card-derived shield-ram stat may turn a qualifying shield-up impact into damage.
- Each client uses a smoothing follow camera centered on its controlled or spectated ship. The camera snaps to the local ship on every heat countdown, remains centered even near arena edges, and uses a fixed gameplay zoom at supported aspect ratios.
- Show edge indicators for off-screen ships within 900 pixels and for the nearest incoming off-screen projectile. Indicators must use shape plus color so color alone does not carry meaning.
- A spectator may cycle living ships with the active profile's previous/next-target actions, defaulting to A/D on keyboard and the shoulder buttons on controller. If no player is alive during a tie result, the camera returns to arena center.

## 6. Combat Specification

### 6.1 Base Ship and Movement

| Property | Base value |
| --- | ---: |
| Collision radius | 20 px |
| Maximum health | 100 |
| Maximum speed | 480 px/s |
| Acceleration | 900 px/s² |
| Drag | 700 px/s² |

- Normalize combined local movement input so diagonal or analog input is never faster.
- Default to persistent **Relative** movement aligned with the screen, so up remains world-up regardless of aim; the client converts it into the canonical ship-local network input before transmission. The persistent **Newtonian** option instead moves in ship-local space: keyboard `W`/`S` or the controller's forward/back axis moves along the current aim direction, while keyboard `A`/`D` or the lateral axis strafes perpendicular to aim.
- With movement input, move velocity toward `input_direction × maximum_speed` at `acceleration × delta`.
- Without movement input, move velocity toward zero at `drag × delta`.
- Aim is independent of movement. Keyboard/mouse uses the cursor-derived angle; controller/joystick uses the configured aim axes and retains the last valid angle while the stick is inside its deadzone.
- The client sends an aim angle, never an absolute world-space cursor coordinate. The server rejects non-finite angles and normalizes valid angles to `[0, TAU)`.

### 6.2 Base Weapon and Projectiles

| Property | Base value |
| --- | ---: |
| Damage | 25 |
| Fire rate | 4 shots/s |
| Magazine | 8 shots |
| Reload duration | 1.5 s |
| Projectile speed | 900 px/s |
| Projectile radius | 5 px |
| Projectile lifetime | 2.5 s |
| Projectile count | 1 |
| Pierce count | 0 |
| Ricochet count | 0 |

- Holding the active profile's fire action—left mouse or right trigger by default—fires automatically whenever the cooldown, ammunition, shield, and projectile limits permit.
- Reload begins automatically when the magazine reaches zero. The remappable manual-reload action (`R` or X / Square by default) starts the same authoritative reload when the magazine is partially used.
- Firing is disabled while reloading or shielding. Releasing the shield does not reset the fire cooldown.
- Projectiles ignore their owner, do not collide with other projectiles, and damage every other participant because the mode is free-for-all.
- A normal projectile is destroyed on its first ship, shield, wall, or obstacle collision. Piercing allows additional unshielded ship hits; ricochet allows wall/obstacle bounces. Every projectile and beam uses continuous swept arena collision between its prior and next positions so fast or near-tangent volley members cannot tunnel through boundaries, rectangular cover, or circular obstacles. After a bounce or piercing hit, unused travel continues within the same physics tick so the resulting path can still damage a ship before the next tick. A shield always consumes the projectile regardless of remaining pierces or bounces.
- A projectile cannot damage the same ship more than once. Its server record tracks already-hit peer IDs.
- Enforce 64 active projectiles per owner and 1024 globally. When a new projectile would exceed a limit, despawn the oldest projectile owned by that shooter first; if the global limit remains exceeded, despawn the globally oldest projectile.

### 6.3 Directional Shield

| Property | Base value |
| --- | ---: |
| Arc | 120° centered on aim |
| Capacity | 100 energy |
| Continuous drain | 20 energy/s |
| Block cost | 25 energy/projectile |
| Regeneration | 30 energy/s |
| Regeneration delay | 1.25 s |
| Depleted reactivation threshold | 25 energy |

- Holding the active profile's shield action—right mouse or left trigger by default—activates the shield if it is not depletion-locked and has positive energy.
- Shielding reduces acceleration by 25%, disables firing, and leaves maximum speed and drag unchanged.
- A projectile is blockable when the vector from ship center to the projectile impact point falls inside half the current shield arc around the ship's aim direction.
- A successful block destroys the projectile and subtracts the block cost. The current projectile is still blocked if the cost takes energy to zero; the shield then deactivates and locks until energy regenerates to the threshold.
- A ship with positive shield-ram damage may damage another ship whenever its shield is active and relative impact speed meets the derived minimum. Damage scales from ×0.5 through ×2.0 around the 480 px/s reference speed. A successful ram spends the normal block cost and is limited by the derived per-attacker/per-target cooldown; ordinary collisions remain harmless.
- Energy regeneration begins only after no shield activation or block has occurred for the full regeneration delay.
- Projectiles striking outside the shield arc continue to the hull. Overtime boundary damage bypasses the shield.

### 6.4 Damage, Repair, and Death

- The server applies damage once per physics tick in stable projectile-ID order.
- Health is clamped to `[0, derived_max_health]`. Zero health eliminates the player.
- Taking projectile or overtime damage resets the Auto-Repair grace timer. Repair never revives a dead player and never exceeds maximum health.
- Death removes the ship's collision and input authority immediately, despawns all projectiles owned by that player after 0.5 seconds, emits a reliable death event, and switches that client to spectating.

### 6.5 Overtime

- At the leader-configured 30–120 second point of `ACTIVE_HEAT` (45 seconds by default), activate a centered circular safe boundary large enough to enclose the arena.
- Shrink its radius linearly to 120 pixels over 45 seconds.
- Ships outside the current safe radius take 30 health/second, accumulated continuously and applied by the server each physics tick.
- After the boundary reaches minimum radius, increase boundary damage by 10 health/second every 10 seconds, up to 100 health/second.
- The HUD announces overtime five seconds before activation and displays the boundary timer and current damage rate.

## 7. Card and Stat System

### 7.1 Evaluation Rules

`CardDefinition` is a data resource with a stable ID, category, rarity, title, description, additive modifiers, multiplicative modifiers, integer modifiers, and optional special behavior ID. It contains no maximum-stack field.

Derived stats are recomputed from base values whenever the build changes:

1. Sum all flat additions by stat.
2. Multiply all multiplicative factors by stat; stacking therefore compounds but does not depend on acquisition order.
3. Apply integer special additions such as projectile, pierce, and ricochet counts.
4. Apply the clamps below.

Cards are not required to include a downside. Pure upgrades, tradeoffs, and transformative effects may all coexist in the catalog. Positive modifiers from different cards deliberately multiply one another, so a long match can produce extreme builds. The clamps are technical guardrails for network encoding, physics stability, and entity budgets—not intended balance ceilings.

| Stat | Minimum | Maximum |
| --- | ---: | ---: |
| Maximum health | 10 | 600 |
| Maximum speed | 100 | 2400 px/s |
| Acceleration | 100 | 6000 px/s² |
| Drag | 100 | 6000 px/s² |
| Projectile damage | 1 | 600 |
| Fire rate | 0.25 | 20 shots/s |
| Magazine | 1 | 128 |
| Reload duration | 0.1 s | 8 s |
| Projectile speed | 200 | 4000 px/s |
| Projectile lifetime | 0.1 s | 12 s |
| Projectile knockback | 0 | 1800 px/s |
| Afterburner impulse | 50 | 1800 px/s |
| Afterburner duration | 0.1 s | 3 s |
| Afterburner cooldown | 0.5 s | 20 s |
| Afterburner speed factor | 1 | 4 |
| Afterburner acceleration factor | 1 | 6 |
| Shield capacity | 5 | 600 |
| Shield regeneration | 1 | 400 energy/s |
| Shield drain | 0.25 | 400 energy/s |
| Shield regeneration delay | 0.05 s | 8 s |
| Shield arc | 30° | 360° |
| Shield block cost | 1 | 200 energy |
| Shield depletion threshold | 1 | Current shield capacity |
| Shielded acceleration factor | 0.1 | 2.0 |
| Shield-ram damage | 0 | 300 |
| Minimum shield-ram speed | 40 px/s | 1200 px/s |
| Shield-ram cooldown | 0.15 s | 4 s |
| Shield-hit healing fraction | 0 | 1 |
| Auto-repair delay | 0.1 s | 20 s |
| Auto-repair rate | 0.1 | 400 health/s |
| Projectile count | 1 | 6 |
| Pierce count | 0 | 12 |
| Ricochet count | 0 | 12 |
| Mine capacity | 0 | 1000 |

### 7.2 Rarity and Offer Weighting

Every card declares one of seven visible rarity tiers. When all tiers contain eligible cards, the chance that each offer slot selects that tier is Common 45%, Uncommon 27%, Rare 15%, Epic 8%, Legendary 3.3%, Mythical 1.2%, and Unobtanium 0.5%. After selecting a tier, choose uniformly among its eligible cards. Cards are never repeated within one five-card offer. If a tier has no eligible card, remove it and renormalize the remaining tier weights for that slot. These percentages are tier weights, not the probability of a particular card. Fractional high-tier chances remain visible on the card rather than rounding to zero.

### 7.3 Catalog

The launch catalog contains 133 unlimited-stack cards: 40 ship, 46 shield, and 47 weapon cards. The weapon-heavy split gives each firing model more combinatorial space, while multiple shield cards enable distinct melee, defensive-healing, and projectile-rebound builds. Catalog validation rejects duplicate IDs, exact modifier/special-behavior signatures, and cards that touch the same stats in the same directions with only their magnitudes changed. Similar themes are permitted only when their stat interactions or tradeoffs create meaningfully different builds.

| ID | Card | Category | Rarity | Effect per stack |
| --- | --- | --- | --- | --- |
| `reinforced_hull` | Reinforced Hull | Ship | Common | +25 maximum health; ×0.92 maximum speed |
| `overcharged_thrusters` | Overcharged Thrusters | Ship | Uncommon | ×1.12 maximum speed; ×1.15 acceleration |
| `vector_jets` | Vector Jets | Ship | Common | ×1.20 acceleration; ×1.25 drag |
| `auto_repair` | Auto-Repair | Ship | Rare | After 5 seconds without damage, repair 8 health/s until damaged or full |
| `kinetic_plating` | Kinetic Plating | Ship | Common | +15 maximum health; ×1.05 drag |
| `phase_thrusters` | Phase Thrusters | Ship | Uncommon | ×1.18 acceleration; ×0.90 shield block cost |
| `glass_reactor` | Glass Reactor | Ship | Rare | ×1.18 maximum speed; ×1.22 acceleration; ×0.85 maximum health |
| `emergency_bulkheads` | Emergency Bulkheads | Ship | Rare | +45 maximum health; ×0.80 auto-repair delay |
| `inertial_dampers` | Inertial Dampers | Ship | Uncommon | ×1.35 drag; ×1.05 shielded acceleration |
| `nanite_reservoir` | Nanite Reservoir | Ship | Legendary | Enable auto-repair; +35 maximum health; ×0.90 maximum speed |
| `capacitor_bank` | Capacitor Bank | Shield | Uncommon | +30 capacity; ×1.10 regeneration |
| `quick_charge` | Quick Charge | Shield | Uncommon | ×1.22 regeneration; ×0.95 shield block cost |
| `wide_emitter` | Wide Emitter | Shield | Uncommon | +20° arc; ×1.15 continuous drain |
| `efficient_field` | Efficient Field | Shield | Common | ×0.80 continuous drain |
| `flux_reservoir` | Flux Reservoir | Shield | Common | +20 capacity |
| `mirror_field` | Mirror Field | Shield | Rare | +10° arc; ×1.25 regeneration |
| `fortress_emitter` | Fortress Emitter | Shield | Epic | +60 capacity; ×1.20 drain; ×0.90 maximum speed |
| `blink_capacitor` | Blink Capacitor | Shield | Legendary | ×1.80 regeneration; ×1.15 shielded acceleration |
| `reactive_barrier` | Reactive Barrier | Shield | Uncommon | ×0.85 drain; ×0.85 regeneration delay |
| `omnidirectional_field` | Omnidirectional Field | Shield | Legendary | +240° arc; ×0.75 capacity |
| `heavy_rounds` | Heavy Rounds | Weapon | Rare | ×1.35 damage; ×0.80 fire rate |
| `rapid_cycling` | Rapid Cycling | Weapon | Uncommon | ×1.30 fire rate |
| `rail_accelerant` | Rail Accelerant | Weapon | Rare | ×1.35 projectile speed; ×1.10 damage |
| `extended_magazine` | Extended Magazine | Weapon | Common | +4 magazine |
| `quick_loader` | Quick Loader | Weapon | Uncommon | ×0.75 reload duration; −2 magazine |
| `twin_shot` | Twin Shot | Weapon | Epic | +1 projectile; +10° total spread; ×0.70 damage |
| `piercing_rounds` | Piercing Rounds | Weapon | Rare | +1 pierce; ×1.08 damage |
| `ricochet_rounds` | Ricochet Rounds | Weapon | Rare | +1 ricochet; ×1.08 projectile speed |
| `scatter_array` | Scatter Array | Weapon | Epic | +2 projectiles; +18° spread; ×1.15 fire rate; ×0.62 damage |
| `beam_emitter` | Beam Emitter | Weapon | Legendary | Enable pulse beams; ×1.05 damage; ×2.50 projectile speed |
| `prismatic_lance` | Prismatic Lance | Weapon | Legendary | Enable pulse beams; +2 pierces; ×1.25 damage; ×0.72 fire rate |
| `laser_repeater` | Laser Repeater | Weapon | Epic | Enable pulse beams; ×1.28 fire rate; ×0.86 damage |
| `siege_cannon` | Siege Cannon | Weapon | Rare | ×1.60 damage; ×0.65 fire rate; ×0.82 projectile speed |
| `micro_barrage` | Micro Barrage | Weapon | Epic | +2 projectiles; +14° spread; ×0.80 speed; ×0.72 damage |
| `endless_belt` | Endless Belt | Weapon | Uncommon | +8 magazine |
| `zero_point_loader` | Zero-Point Loader | Weapon | Legendary | ×0.50 reload duration; +4 magazine |
| `ablative_shell` | Ablative Shell | Ship | Common | +20 maximum hull |
| `plasma_thrusters` | Plasma Thrusters | Ship | Uncommon | ×1.12 maximum speed; ×1.18 shielded acceleration |
| `gyroscopic_core` | Gyroscopic Core | Ship | Rare | ×1.25 drag; ×1.08 maximum speed |
| `phoenix_chassis` | Phoenix Chassis | Ship | Epic | ×1.30 maximum hull; ×1.08 maximum speed |
| `starheart_reactor` | Starheart Reactor | Ship | Legendary | ×1.35 hull; ×1.35 acceleration; ×1.18 speed |
| `event_horizon_drive` | Event Horizon Drive | Ship | Mythical | ×1.60 speed; ×1.60 acceleration; ×1.50 shielded acceleration |
| `quantum_reconstruction` | Quantum Reconstruction | Ship | Legendary | Enable auto-repair; ×1.50 maximum hull |
| `impossible_engine` | Impossible Engine | Ship | Unobtanium | ×2.00 speed; ×2.00 acceleration; ×1.50 drag |
| `reserve_cell` | Reserve Cell | Shield | Common | +15 shield capacity; ×0.92 regeneration delay |
| `regenerative_coils` | Regenerative Coils | Shield | Uncommon | ×1.18 shield regeneration; ×0.88 recovery threshold |
| `focused_deflector` | Focused Deflector | Shield | Rare | ×1.25 capacity; ×0.82 drain; ×0.82 arc |
| `shield_siphon` | Shield Siphon | Shield | Rare | ×0.65 drain; ×1.20 regeneration |
| `aegis_matrix` | Aegis Matrix | Shield | Epic | ×1.35 capacity; ×1.25 regeneration |
| `solar_barrier` | Solar Barrier | Shield | Legendary | ×1.50 capacity; ×1.50 regeneration; ×0.70 drain |
| `chronal_shield` | Chronal Shield | Shield | Mythical | ×0.30 regeneration delay; ×1.75 regeneration |
| `infinite_refraction` | Infinite Refraction | Shield | Unobtanium | ×3.00 arc; ×2.00 capacity; ×2.00 regeneration |
| `hollow_points` | Hollow Points | Weapon | Common | ×1.08 projectile damage |
| `cycling_servo` | Cycling Servo | Weapon | Uncommon | ×1.12 fire rate; ×0.92 reload duration |
| `accelerator_coil` | Accelerator Coil | Weapon | Rare | ×1.25 projectile speed; ×1.12 lifetime |
| `trident_array` | Trident Array | Weapon | Epic | +2 projectiles; +1 pierce; +14° spread; ×0.78 damage |
| `sunbeam_core` | Sunbeam Core | Weapon | Mythical | Enable beams; ×1.45 damage; ×1.15 fire rate; +1 pierce |
| `causality_cannon` | Causality Cannon | Weapon | Mythical | ×2.00 damage; ×1.50 projectile speed; +2 pierces |
| `singularity_lance` | Singularity Lance | Weapon | Unobtanium | Enable beams; ×1.75 damage; +3 pierces; +1 ricochet |
| `reality_shredder` | Reality Shredder | Weapon | Unobtanium | Enable beams; ×2.50 damage; ×1.60 fire rate; +2 projectiles; +4 pierces; +2 ricochets |
| `lightweight_frame` | Lightweight Frame | Ship | Common | ×1.08 maximum speed; ×0.95 maximum hull |
| `vectored_nozzles` | Vectored Nozzles | Ship | Common | ×1.12 acceleration; ×1.08 shielded acceleration |
| `combat_gyros` | Combat Gyros | Ship | Common | ×1.18 drag |
| `scar_tissue` | Scar Tissue | Ship | Common | +12 maximum hull; ×1.08 auto-repair rate |
| `sprint_reactor` | Sprint Reactor | Ship | Uncommon | ×1.15 maximum speed; ×0.90 drag |
| `braking_foils` | Braking Foils | Ship | Uncommon | ×1.30 drag; ×0.96 maximum speed |
| `shielded_drive` | Shielded Drive | Ship | Uncommon | ×1.20 shielded acceleration; ×0.92 shield drain |
| `damage_control` | Damage Control | Ship | Uncommon | ×0.85 auto-repair delay; activates after repair technology is owned |
| `adaptive_chassis` | Adaptive Chassis | Ship | Rare | ×1.15 maximum hull; ×1.10 acceleration |
| `repair_gel` | Repair Gel | Ship | Rare | Enable auto-repair; ×1.12 repair rate; ×0.92 repair delay |
| `pursuit_engine` | Pursuit Engine | Ship | Rare | ×1.20 maximum speed; ×1.08 acceleration; ×0.90 shield capacity |
| `juggernaut_frame` | Juggernaut Frame | Ship | Rare | ×1.35 maximum hull; ×1.20 drag; ×0.85 acceleration |
| `comet_drive` | Comet Drive | Ship | Epic | ×1.35 maximum speed; ×1.15 projectile speed; ×0.80 maximum hull |
| `recursive_nanites` | Recursive Nanites | Ship | Epic | Enable auto-repair; ×0.70 delay; ×1.50 rate; ×0.90 maximum hull |
| `phase_brakes` | Phase Brakes | Ship | Epic | ×1.70 drag; ×0.75 shield recovery threshold |
| `warpshell` | Warpshell | Ship | Legendary | ×1.50 maximum hull; ×1.25 maximum speed; ×0.80 shield capacity |
| `immortal_lattice` | Immortal Lattice | Ship | Legendary | Enable auto-repair; ×1.25 hull; ×1.80 rate; ×1.30 shield capacity |
| `lightspeed_frame` | Lightspeed Frame | Ship | Mythical | ×1.80 maximum speed; ×1.50 shielded acceleration; ×0.60 shield capacity |
| `ouroboros_hull` | Ouroboros Hull | Ship | Mythical | ×1.75 maximum hull; ×1.50 shield regeneration; enable auto-repair; ×2.00 rate |
| `transcendent_chassis` | Transcendent Chassis | Ship | Unobtanium | ×2.00 hull; ×1.50 speed, acceleration, and drag; enable auto-repair |
| `pulse_capacitor` | Pulse Capacitor | Shield | Common | +12 shield capacity; ×0.95 recovery threshold |
| `low_loss_coils` | Low-Loss Coils | Shield | Common | ×0.90 continuous drain; ×0.95 block cost |
| `compact_deflector` | Compact Deflector | Shield | Common | +12° arc; ×0.92 block cost |
| `recovery_switch` | Recovery Switch | Shield | Uncommon | ×0.80 recovery threshold; ×0.90 regeneration delay |
| `kinetic_converter` | Kinetic Converter | Shield | Uncommon | ×0.78 block cost; ×0.90 capacity |
| `pursuit_screen` | Pursuit Screen | Shield | Uncommon | ×1.18 shielded acceleration; ×0.90 arc |
| `broadside_field` | Broadside Field | Shield | Uncommon | ×1.18 arc; ×1.08 continuous drain |
| `deep_reserves` | Deep Reserves | Shield | Rare | ×1.25 capacity; ×0.90 regeneration |
| `flash_recharger` | Flash Recharger | Shield | Rare | ×1.50 regeneration; ×1.15 regeneration delay |
| `resilient_grid` | Resilient Grid | Shield | Rare | ×0.65 recovery threshold; ×1.10 capacity |
| `duelist_aegis` | Duelist Aegis | Shield | Rare | ×0.70 arc; ×0.65 block cost |
| `mobile_bulwark` | Mobile Bulwark | Shield | Rare | ×1.35 shielded acceleration; ×1.15 continuous drain |
| `vacuum_insulation` | Vacuum Insulation | Shield | Epic | ×0.55 continuous drain; ×0.85 regeneration |
| `cascade_barrier` | Cascade Barrier | Shield | Epic | ×0.50 block cost; ×1.20 capacity |
| `second_wind` | Second Wind | Shield | Epic | ×0.40 recovery threshold; ×0.80 regeneration delay; ×1.25 capacity |
| `stellar_aegis` | Stellar Aegis | Shield | Legendary | ×1.60 capacity; ×1.25 arc; ×0.75 block cost |
| `perpetual_field` | Perpetual Field | Shield | Legendary | ×0.40 continuous drain; ×1.30 capacity |
| `inviolable_front` | Inviolable Front | Shield | Mythical | ×0.55 arc; ×2.00 capacity; ×0.35 block cost |
| `instant_recovery` | Instant Recovery | Shield | Mythical | ×0.20 regeneration delay; ×0.25 recovery threshold; ×2.00 regeneration |
| `absolute_barrier` | Absolute Barrier | Shield | Unobtanium | ×2.50 capacity; ×3.00 arc; ×0.35 drain; ×0.25 block cost; ×0.20 recovery threshold |
| `long_fuse_rounds` | Long-Fuse Rounds | Weapon | Common | ×1.20 projectile lifetime; ×0.95 projectile speed |
| `short_fuse_payload` | Short-Fuse Payload | Weapon | Common | ×0.75 projectile lifetime; ×1.15 damage |
| `tight_bore` | Tight Bore | Weapon | Common | −4° projectile spread |
| `drum_spring` | Drum Spring | Weapon | Common | +2 magazine; ×1.05 reload duration |
| `hot_load` | Hot Load | Weapon | Uncommon | ×1.15 fire rate; −1 magazine |
| `rangefinder` | Rangefinder | Weapon | Uncommon | ×1.25 projectile lifetime; ×1.10 speed; ×0.95 fire rate |
| `impact_lens` | Impact Lens | Weapon | Uncommon | ×1.12 damage; ×0.95 projectile speed |
| `bank_shot` | Bank Shot | Weapon | Uncommon | +1 ricochet; ×1.15 lifetime; ×0.90 damage |
| `flechette_payload` | Flechette Payload | Weapon | Rare | +1 pierce; ×1.12 fire rate; ×0.85 damage |
| `overpressure_chamber` | Overpressure Chamber | Weapon | Rare | ×1.30 damage; ×0.80 lifetime; ×0.90 fire rate |
| `sustained_barrage` | Sustained Barrage | Weapon | Rare | +6 magazine; ×1.18 fire rate; ×1.25 reload duration |
| `deadeye_calibration` | Deadeye Calibration | Weapon | Rare | −10° spread; ×1.20 damage; ×0.90 fire rate |
| `orbital_rounds` | Orbital Rounds | Weapon | Epic | ×2.00 lifetime; ×1.25 damage; ×0.75 speed |
| `chain_ricochet` | Chain Ricochet | Weapon | Epic | +2 ricochets; +1 pierce; ×0.85 damage |
| `needle_storm` | Needle Storm | Weapon | Epic | +2 projectiles; +8° spread; ×1.25 speed; ×0.68 damage; ×1.10 fire rate |
| `annihilator_shell` | Annihilator Shell | Weapon | Legendary | ×1.80 damage; ×0.70 lifetime; +1 pierce |
| `impossible_magazine` | Impossible Magazine | Weapon | Legendary | +20 magazine; ×0.70 reload; ×1.20 fire rate |
| `horizon_round` | Horizon Round | Weapon | Mythical | ×2.50 lifetime; ×1.50 speed; +2 pierces |
| `storm_of_one` | Storm of One | Weapon | Mythical | ×2.00 fire rate; ×0.50 reload; −5 magazine; ×0.80 damage |
| `supernova_array` | Supernova Array | Weapon | Unobtanium | +4 projectiles; +32° spread; ×1.40 damage; ×1.25 fire rate; ×1.50 lifetime |
| `kinetic_prow` | Kinetic Prow | Shield | Rare | +22 shield-ram damage |
| `impact_capacitor` | Impact Capacitor | Shield | Epic | +34 shield-ram damage; +25 shield capacity |
| `breach_vector` | Breach Vector | Shield | Legendary | +48 shield-ram damage; ×1.20 maximum speed |
| `sundering_aegis` | Sundering Aegis | Shield | Mythical | +66 shield-ram damage; ×0.70 minimum ram speed |
| `worldbreaker_prow` | Worldbreaker Prow | Shield | Unobtanium | +90 shield-ram damage; ×1.25 shield capacity; ×0.55 ram cooldown |
| `afterburner` | Afterburner | Ship | Rare | Enable the Special-input forward burst; ×0.88 cooldown |
| `cloak` | Cloak! | Ship | Legendary | Special cloaks for 5 seconds; damage breaks it; cannot fire; +1 match-long use per stack |
| `ramming_shields` | Ramming Shields | Shield | Epic | +44 shield-ram damage; ×0.70 ram trigger speed; ×1.12 shielded acceleration |
| `concussion_rounds` | Concussion Rounds | Weapon | Rare | +180 projectile knockback; shields retain 20% |
| `repulsor_payload` | Repulsor Payload | Weapon | Epic | +320 projectile knockback; ×0.90 projectile speed; shields retain 20% |
| `nosferatu_shield` | Nosferatu Shield | Shield | Legendary | Heal hull for 25% of blocked projectile damage |
| `rebound_shields` | Rebound Shields | Shield | Legendary | Blocked projectiles return toward their source at 50% damage and 50% remaining range; one rebound maximum |
| `mine_layer` | Star Mines | Weapon | Legendary | Special drops a 75-damage proximity mine; +10 match-long charges per stack; 10-second placement cooldown |

For multi-projectile shots, distribute projectiles evenly across the total spread and center odd projectile counts on the aim direction. All projectiles use the final derived per-projectile damage.

## 8. Networking Specification

### 8.1 Authority and Timing

- Use `ENetMultiplayerPeer` over UDP with protocol version `17` and a maximum of 32 client peers in addition to the server. Version 17 carries authoritative rebound ownership plus cloak activity and remaining match-long charges while retaining the isolated player-snapshot, projectile-delta, projectile-correction, and objective streams introduced earlier.
- The server simulates at 60 Hz. Clients send the latest input at 30 Hz. Player snapshots are sent at 20 Hz; projectile corrections are sent at 5 Hz; replaceable objective snapshots are sent at 4 Hz.
- Use six logical channels: reliable ordered control/state events, unreliable ordered input, unreliable ordered player snapshots, unreliable ordered projectile deltas, unreliable ordered projectile corrections, and unreliable ordered objective snapshots. Durable objective transitions use the reliable control channel.
- The server is the only authority for admission, player IDs, simulation position, projectile creation, collision, damage, RNG, build changes, scoring, and state transitions.

### 8.2 One-Click Hosting and LAN Discovery

- **Host & Join** creates an authoritative server inside the client process under an isolated `MultiplayerAPI`, then connects the playable client to it through `127.0.0.1` using the normal ENet handshake. The two roles never share authority or bypass the network protocol.
- The host supplies a bounded server display name and a gameplay UDP port. The fixed discovery port `7359` is reserved and cannot also be selected as the gameplay port.
- A listening server answers bounded UDP discovery queries on port `7359` with its protocol version, instance ID, display name, gameplay port, human/NPC occupancy, total-player limit, and whether a match is active. Discovery messages never carry gameplay state or authority.
- A client browser broadcasts a fresh nonce on the local subnet and also probes loopback. It accepts only bounded, well-formed responses matching that nonce, uses the packet source as the join address, deduplicates by server instance, marks protocol-incompatible sessions as unavailable, and expires stale entries after 3.5 seconds.
- Responders reply by unicast and rate-limit each source endpoint. Discovery collections and packet sizes are hard-bounded. A discovery bind failure logs a warning but does not prevent the authoritative gameplay server from running.
- LAN discovery is convenience for one broadcast domain, not public matchmaking. Direct host/IP plus port remains available for routed LANs and manually configured internet hosting.

### 8.3 Connection and Control Messages

Client-to-server messages:

- `client_hello(protocol_version, display_name)` — reliable, required within 10 seconds of ENet connection.
- `request_lobby_config(rounds_to_win)` — reliable, lobby leader only.
- `request_player_limit(total_participants)` — reliable, lobby leader and lobby state only; bounded by 2, server capacity, and 32.
- `request_npcs_enabled(enabled)` — reliable, lobby leader and lobby state only.
- `request_game_mode(mode)` — reliable, lobby leader and lobby state only; validates one of the five supported modes and clears human readiness.
- `request_team_count(team_count)` — reliable, lobby leader and waiting Team Death Match only; bounded from 2 through 8 and cannot exceed the participant limit.
- `request_team_assignment(peer_id, team_selection)` — reliable and waiting team mode only; `0` requests Auto, otherwise the selection must name an available team. The leader may target anyone, a human may target themselves, and any human may target an NPC.
- `request_random_spawn_powerups(enabled)` — reliable, lobby leader and lobby state only; defaults to false.
- `request_random_powerup_interval(seconds)` — reliable, lobby leader and lobby state only; bounded from 5 through 90.
- `request_random_powerups_permanent(enabled)` — reliable, lobby leader and lobby state only; defaults to false.
- `request_overtime_start(seconds)` — reliable, lobby leader and lobby state only; bounded from 30 through 120.
- `request_player_color(random, rgb_hex)` — reliable, waiting human only; a custom value must be exactly six hexadecimal RGB digits.
- `request_npc_difficulty(npc_peer_id, difficulty)` — reliable, lobby leader and lobby state only; target must be a current server-owned NPC and difficulty must be one of the five supported tiers.
- `request_all_npc_difficulty(difficulty)` — reliable, lobby leader and lobby state only; updates every current NPC and the default for later NPC fills.
- `request_ready_state(ready)` — reliable, waiting human only.
- `request_eject_player(peer_id)` — reliable, lobby leader and lobby state only; the sender cannot target themselves or an NPC.
- `request_start_match()` — reliable, lobby leader only; all connected humans must be ready.
- `request_extend_match()` — reliable, lobby leader and `MATCH_RESULT` only; adds exactly five rounds and resumes the same builds and scores when at least two competitors remain.
- `request_return_to_lobby()` — reliable, lobby leader and `MATCH_RESULT` only; closes final standings for every connected client.
- `select_card(offer_token, card_id)` — reliable, current participant and draft only.
- `submit_input(sequence, client_tick, move_x, move_y, aim_angle, action_bits)` — unreliable ordered.

Server-to-client messages:

- `server_welcome(peer_id, lobby_state)` — reliable handshake acceptance.
- `connection_rejected(reason_code, display_message)` — reliable rejection followed by disconnect.
- `lobby_state(revision, leader_id, config, players)` — reliable full lobby state.
- `draft_offer(offer_token, card_ids, deadline_tick)` — reliable and sent only to its owner.
- `match_event(event_type, server_tick, payload)` — reliable transitions, card results, powerup spawn/collection, damage deaths, and scores.
- `world_snapshot(server_tick, acknowledged_input, player_states)` — unreliable ordered.
- `projectile_batch(server_tick, sequence, chunk, spawned, removed)` — unreliable ordered; every spawn/removal is preserved across bounded chunks.
- `projectile_correction(server_tick, sequence, chunk, active_projectiles, complete_snapshot)` — unreliable ordered; rotating partial corrections update a subset and periodic complete corrections are applied only after all chunks assemble.
- `objective_snapshot(server_tick, objective)` — unreliable ordered replaceable progress, carrier, and position state.

Control and objective payloads may use typed Godot arrays/dictionaries because they are low frequency and bounded by the participant/objective model. Input, player snapshots, and projectile payloads must use versioned `PackedByteArray` encoding with fixed field order, bounded counts, explicit decode failure handling, and projectile transport messages no larger than 1,200 bytes.

### 8.4 Input, Prediction, and Rendering

- `sequence` and ticks use wrapping unsigned 32-bit values. The server ignores duplicate or older input and remembers the most recent valid input until a newer frame arrives.
- Movement components are quantized signed 16-bit values representing `[-1, 1]`; aim is quantized to an unsigned 16-bit turn; action bits contain fire, shield, manual reload, and one-shot special activation flags.
- The server accepts at most 60 input messages per peer per second and disconnects a peer after sustained malformed or excessive traffic.
- The controlled client runs the shared movement function immediately, buffers at least 120 input frames, and replays unacknowledged input after every authoritative snapshot.
- Correction errors up to 128 pixels are smoothed over 100 ms. Larger errors snap immediately and increment a diagnostic counter.
- Remote players render approximately 100 ms behind server time by interpolating the two surrounding snapshots. Extrapolation is limited to 100 ms before holding the last state.
- The local client may show an immediate predicted muzzle flash and projectile volley. Every predicted projectile in a multi-shot volley is tracked under its owner ID and shot sequence; the entire predicted volley is replaced when the authoritative spawns arrive so no collisionless visual copies survive. Rejected shots fade within 100 ms.
- Clients simulate every projectile visual from authoritative spawn data using the same swept arena rebound geometry as the server, so each projectile and short-lived beam in a multi-shot volley visibly ricochets without waiting for the 5 Hz correction interval. Partial corrections add or synchronize their listed projectiles without deleting absent ones. A complete correction adds missed projectiles, synchronizes position, velocity, lifetime, pierce and ricochet budgets, and removes absent projectiles only after every chunk for that sequence has assembled.

### 8.5 Validation and Rejection

- Never trust a peer ID supplied by a client; use the RPC sender identity.
- Reject non-finite numbers, movement magnitudes above tolerance, impossible action bits, stale offer tokens, invalid card IDs, out-of-state requests, unauthorized lobby actions, and version mismatches.
- Accept at most 20 reliable control requests per peer per second, bound offer tokens and card IDs to 64 characters before interning or lookup, and disconnect only the sender after sustained excessive control traffic.
- Clamp accepted movement after validation. Do not clamp malformed or non-finite messages into validity.
- Rejection reason codes are `SERVER_FULL`, `VERSION_MISMATCH`, `INVALID_NAME`, `HANDSHAKE_TIMEOUT`, `MALFORMED_TRAFFIC`, `SERVER_CLOSED`, and `EJECTED`.
- Clients display a human-readable error and return to the connection screen after rejection or network loss.
- The vertical slice provides authority and validation but no identity authentication, encryption, ban service, or denial-of-service protection.

## 9. User Experience

### 9.1 Screens

1. **Connection:** A centered menu over the non-gameplay neon backdrop with three tabs: a refreshable LAN-server list with server name, endpoint, occupancy, lobby/match state, ping, compatibility, and Join action; Direct Connect with address defaulting to `127.0.0.1` and gameplay port defaulting to `7000`; and Host Game with bounded server name, gameplay port, and Host & Join. Display name is shared across all connection paths. Keep Quit, settings access, and inline connection/hosting errors available. The arena and its map are not rendered before a match begins.
2. **Lobby:** A centered pre-match menu on the same non-gameplay backdrop with a scrollable human/NPC player list, player colour swatches, team labels when applicable, leader and ready markers, a local ready toggle, leader-only eject controls, individual and bulk NPC difficulty dropdowns, round target, total-player limit, NPC-fill toggle, context-aware Start Match button, connection status, and a Match Options panel for the five-mode selector and description, random-powerup enablement/interval/permanence, and overtime timing. Each human's own roster swatch opens their persistent Random/custom HSV-wheel selector with an explicit Apply action; colour selection is not a separate lobby option. The arena, internal spawn anchors, and inactive ship markers remain hidden through the initial draft.
3. **Draft:** Five or fewer card panels with name, category, exact effects, current/new stack count, selection state, and synchronized timer. Put rarity and tier drop chance in smaller print at the bottom; use the rarity color for the card background and border. Hovering a choice uses the same rarity-styled graphical card preview as scoreboard and victory build inspection, showing the projected post-pick stack effects rather than a generic text tooltip. Support clicking, keys 1–5, and focused controller navigation with confirm. A previous-round winner instead sees a clear no-card draft-bye message.
4. **Combat HUD:** A compact upper-left panel no larger than 430×148 at the 1920×1080 virtual canvas integrates mode, objective state/progress, match state, round/heat, synchronized timer, alive count, overtime warning, health, shield, ammunition/reload, and active-profile shortcuts. The arena renders the hill or flag and valid extraction/base zones. A compact local ammo bar and `AMMO`/`RELOAD` readout also stays directly above the player ship. The former top-center match banner is not visible during gameplay. Holding the configured scoreboard action displays a centered live scoreboard with ranked structured rows, teams, heat/round scores, match-total kills, public builds, and a highlighted local-player row; releasing it immediately closes the scoreboard while the match continues behind it.
5. **Spectator:** Current target, cycle controls, remaining players, and the normal score display.
6. **Results:** A strong victory title and separate champion plate followed by rank, pilot, rounds-won, match-total kills, and final-build columns. Do not show heat wins because they reset when the decisive round resolves. Highlight the winner, alternate neon row treatments for scanability, wrap builds within their column, and scroll for large lobbies. Render every final-build card as an individual rarity-colored hover target; its popup shows description, tier chance, owned stacks, per-stack modifiers, compounded totals, and special behavior. The lobby leader receives Play 5 More Rounds and Exit to Lobby buttons; extending preserves current scores and cards. Other clients see disabled leader-controlled actions. No automatic close timer is present.

### 9.2 Presentation Rules

- Use a dark space background with procedural geometric ships, bright outlines, bloom/glow, trails, shield arcs, and concise particles. Each living moving ship emits a small, bounded color-matched thruster trail opposite its travel direction; emission intensity follows speed and stops on elimination.
- Replace the system arrow over keyboard/mouse gameplay with a high-contrast crosshair centered on the aim point. Hide the stale mouse pointer during controller-controlled combat and restore it whenever an interactive menu is visible.
- Give every participant a stable server-serialized colour: the human's custom lobby choice or a Random high-contrast palette entry, with NPCs using that palette. Add name, outline pattern, and local-player marker so identity never depends on colour alone. In-world health and shield displays use each participant's own derived card stats, never the local player's maxima; a full authoritative resource therefore always renders full at heat start. While Afterburner is active, enlarge and brighten the bounded exhaust bloom without obscuring the ship. While Cloak! is active, show only a faint outline to its local pilot and hide the ship, nameplate, shield, and exhaust from opponents.
- The local ship has a persistent chevron and stronger outline. Damage sources flash the impacted side; shield blocks and shield breaks have distinct effects.
- Keep compact combat resources at least 17 px and secondary shortcut text at least 14 px on the virtual canvas, using bars and color to preserve scanability. Scale UI with window size. Use enlarged lobby controls, a scrollable player roster, and card body text that remains readable at 1280×720 without scrolling inside an individual card.
- Draft cards use dark category-tinted backgrounds with at least 85% opacity so arena action cannot overpower their text.
- Avoid full-screen white flashes. Screen shake is subtle, local-only, and never affects aim coordinates.
- Start with an animated splash that accepts keyboard, mouse, or controller input immediately and automatically proceeds to the connection menu after 10 seconds. The connection menu displays the canonical game version and release label. Provide one persistent settings screen from the main menu and in-match pilot menu with separate Display & Audio and Controls tabs. Include persistent Windowed, Borderless Fullscreen, and Exclusive Fullscreen selection; sixteen standard, 3:2, ultrawide, and super-ultrawide resolutions through 5120×2160; Newtonian/Relative flight selection; input-profile switching; connected-controller status; controller deadzone; binding capture; and per-profile defaults. Borderless mode uses the desktop resolution, while Windowed and Exclusive Fullscreen use the saved selection. The lobby/menu must remain hidden during draft, countdown, combat, results, and spectating. Each heat countdown uses a high-contrast centered `READY` plate; it changes to `BEGIN` at 0.10 seconds remaining, persists for 0.10 seconds after unlock, and fades during that post-roll. Match completion opens a dedicated victory screen until the lobby leader explicitly returns everyone to the lobby. Returning to the same connected lobby clears match-only renderer state without discarding the local peer identity, monotonic input sequence, or client tick required for prediction and server input acceptance in a rematch.
- Provide build-aware synthesized weapon sounds that distinguish standard, automatic, heavy, rail, scatter, pulse-beam, beam-repeater, and beam-lance families. Weapon damage, total volley, cadence, speed, pierce, ricochet, knockback, beam conversion, rarity, and accumulated stacks drive bounded power and modification weight without multiplying loudness per pellet. Provide synthesized placeholders for legacy fire/beam fallbacks, projectile impact, ricochet, reload completion, shield activate/block/break, damage, elimination, card lock, countdown, overtime, round win, and match win. Authored `.wav`, `.ogg`, or `.mp3` files with documented stable names replace individual cues or weapon-family/tier variants without code changes; repeated prediction/authority events must not replay a cue, simultaneous pilots must not suppress one another, the local weapon has mix priority, and distant world effects are attenuated.
- Support `assets/audio/music/main_menu.*` for menu/lobby, a filename-ordered `assets/audio/music/gameplay/` playlist for draft through combat, and optional `assets/audio/music/win.*` for match results. Accept `.wav`, `.ogg`, and `.mp3`, including compound names whose final extension is supported. Crossfade the final three seconds of menu music into a second player at the track start so authored fade tails do not produce dead air or a hard restart. Use a generated victory theme if win music is absent. Persist master, music, effects, and mute settings between launches. All supplied audio must be original or properly licensed.

## 10. Observability and Failure Handling

- The server writes JSON-line logs to stdout with UTC timestamp, level, event name, and bounded fields.
- Log startup configuration, match seed, joins/leaves, rejected requests, state transitions, heat/round/match results, shutdown, and fatal errors. Do not log every input frame or a client's IP address.
- Every 10 seconds during a match, log connected peers, participant/entity counts, mean/p95/maximum simulation duration, outbound byte counts, static memory, object/node counts, and orphan-node count.
- A debug-only client overlay shows FPS, round-trip time and variance, ENet loss/throttle, snapshot arrival jitter and gaps, interpolation delay and extrapolation rate, reconciliation error/snaps, buffered input count, expired predicted shots, and the last acknowledged input.
- Scene or payload decode failures must produce an error, reject the affected operation, and leave the server state valid. A single bad client message must not terminate the server.

## 11. Testing and Acceptance

### 11.1 Automated Tests

- **Stat tests:** Every card alone and at cap, order-independent stacking, clamps, Twin Shot spread, and build-complete offers.
- **Combat tests:** Movement normalization and both flight bases, fire cadence, automatic/manual reload, ship-overlap recovery, shield arc edges, depletion lock, shield-ram qualification/cooldown, pierce, continuous swept ricochet for complete projectile/beam volleys, owner immunity, timed powerup placement/pickup, overtime, repair interruption, and simultaneous lethal hits.
- **State tests:** Valid transition graph, solo and team first-to-two heat resolution, hill hold, solo/team flag capture, objective-safe locations on all maps, round target 1 and 5, draft early completion/timeout, forfeit, leader transfer, and lobby reset.
- **Protocol tests:** Encode/decode round trips, maximum bounded payloads, sequence wraparound, malformed/truncated packets, game-mode/lobby-option/colour authorization, host/self/NPC team-assignment permissions, multi-team serialization, friendly-fire rejection, rate limiting, version mismatch, and stale card tokens.
- **Integration tests:** One server plus two protocol clients completes a seeded match, returns to lobby, starts a second match with cleared state, and exits cleanly. A separate production-flow test starts an in-process authority, admits its loopback client through the real handshake, discovers its advertisement through the LAN browser, and shuts both roles down cleanly.
- **NPC lobby integration:** One human leader sets a four-participant limit, enables immediate NPC fill, configures the waiting NPC rows, starts with three authoritative NPCs, receives a five-card draw, and reaches active combat with snapshots, full-map acquisition, close-contact recovery, and difficulty-profiled NPC input.

### 11.2 Load and Soak Acceptance

- Launch one exported or headless server and 32 scripted protocol clients through the real ENet paths.
- Run randomized movement, aim, fire, shield, and valid card selections for at least 10 minutes.
- All 32 clients must connect; no unhandled errors, invalid state transitions, leaked participants, or ever-growing entity collections may occur.
- The server's 95th-percentile simulation duration must remain below the 16.67 ms physics budget on the development machine.
- The test must complete at least one heat, exercise overtime, disconnect one client during combat, admit one late spectator, and finish with a clean server shutdown.

### 11.3 Manual Acceptance

- Two Windows clients can connect to the exported server over localhost and LAN and play through two consecutive matches.
- Input prediction feels immediate; remote ships interpolate without continuous jitter; large corrections are exceptional and visible in diagnostics.
- Every card's displayed values match the derived gameplay result.
- Shooting, shield blocking/breaking, damage, elimination, overtime, heat wins, round wins, and match victory are visually and audibly distinguishable.
- Connection failure, server full, version mismatch, leader disconnect, active-player disconnect, and server shutdown all return clients to a usable screen with a clear message.
- UI remains usable at 1280×720, 1920×1080, 2560×1080, and 3440×1440 with 32 listed players, without nonuniform stretching.

### 11.4 Release Artifacts

- `SuperStarFighter.exe` Windows x64 client export.
- `SuperStarFighterServer.exe` stripped Windows x64 dedicated-server export.
- Automated test runner and 2-client smoke-test script.
- Configurable 32-client soak-test script.
- Export script that fails nonzero when tests or export fail.
- README covering controls, local hosting, direct-IP joining, UDP port forwarding, tests, exports, known limitations, and troubleshooting.

The vertical slice is complete only when every milestone in [milestones.md](./milestones.md) is complete and all acceptance checks in this section pass.
