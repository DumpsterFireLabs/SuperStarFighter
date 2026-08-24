# Super Star Fighter — Vertical Slice Specification

**Status:** Approved implementation baseline  
**Engine:** Godot 4.7.2 Standard, GDScript  
**Primary platform:** Windows x64 client and Windows x64 headless server  
**Related documents:** [Product plan](./plan.md) · [Implementation milestones](./milestones.md)

This document is the authoritative contract for the vertical slice. It defines observable behavior, starting balance, technical interfaces, failure handling, and acceptance criteria. If it conflicts with `plan.md`, this document takes precedence. Intentional changes must update this specification and any affected milestone acceptance criteria together.

## 1. Product Definition

### 1.1 Goal

Deliver a complete, replayable multiplayer vertical slice in which 2–32 players connect directly to an authoritative server, draft persistent build-modifying cards, and fight through heats and rounds until one player wins the match.

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

The vertical slice does not include public matchmaking, a server browser, accounts, progression between matches, teams, chat, controller support, gameplay bots, reconnect restoration, cosmetics, monetization, downloadable content, map selection, anti-DDoS infrastructure, or console/mobile/web exports.

## 2. Terminology

- **Participant:** A connected player admitted before a match starts and eligible to spawn in its heats.
- **Spectator:** A connected client that cannot affect the current heat or match.
- **Heat:** One last-ship-standing combat instance. Players respawn between heats.
- **Round:** A sequence of heats that ends when one player has won two heats.
- **Match:** A sequence of rounds that ends when one player reaches the configured round-win target.
- **Draft:** The simultaneous card-selection phase before each round, including round one.
- **Build:** The complete set of card stacks currently owned by a player.
- **Lobby leader:** The connected participant allowed to change the round target and start a match.

For more than two players, a round is not limited to three heats. Heats continue until one player accumulates two heat wins; different players may each hold one heat win simultaneously.

## 3. Runtime, Configuration, and Project Layout

### 3.1 Runtime Requirements

- Use the non-.NET Godot 4.7.2 Standard build and typed GDScript.
- Run gameplay physics at 60 ticks per second.
- Support a resizable window with a minimum usable resolution of 1280×720 and a default of 1920×1080.
- Support keyboard and mouse only: WASD, mouse aim, left mouse fire, right mouse shield, number keys 1–5 for card choice, left-click UI interaction, Tab scoreboard, and Escape pause/disconnect overlay.
- Multiplayer never pauses the server simulation. The Escape overlay only captures local input.

### 3.2 Command-Line Contract

The same project supplies client, server, tests, and protocol test-client entry paths.

| Option | Applies to | Default | Behavior |
| --- | --- | --- | --- |
| `--server` | Server | Off | Starts authoritative headless server mode. |
| `--port=<1024-65535>` | Server/client | `7000` | Selects the ENet UDP port. |
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
assets/              # Fonts and generated/synthesized audio only
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
| `LOBBY` | Indefinite | Clear match-only state; admit participants. | Leader starts with 2–32 ready participants. |
| `DRAFT` | 20 s max | Generate private offers for every participant. | Everyone selects or the timer expires. |
| `COUNTDOWN` | 3 s | Spawn/reset ships with controls locked. | Timer reaches zero. |
| `ACTIVE_HEAT` | Variable | Enable controls and combat. | One survivor remains or all survivors die in one tick. |
| `HEAT_RESULT` | 3 s | Freeze combat and show heat result. | Continue current round or resolve it. |
| `ROUND_RESULT` | 4 s | Award a round win and clear all heat wins. | Start next draft or resolve match. |
| `MATCH_RESULT` | 10 s | Show winner and final builds/scores. | Return all connected clients to lobby. |

State transitions are reliable server events containing the new state, server tick, end time, and state-specific score data. Clients derive countdown displays from the server time, not local timers.

### 4.2 Lobby Rules

- The first admitted client is lobby leader. On leader disconnect, leadership transfers to the admitted client with the earliest join sequence.
- The leader may set `rounds_to_win` from 1 through 5 and start when at least two participants are connected.
- Display names are trimmed, must contain 1–16 printable non-control Unicode characters, and are made unique for display by appending `#2`, `#3`, and so on.
- A client joining during `DRAFT` or any later match state becomes a spectator until the server returns to `LOBBY`.
- When a match returns to the lobby, connected spectators become normal participants and all builds and scores are cleared.

### 4.3 Draft Rules

- Every participant drafts before round one and before each later round. No draft occurs between heats in the same round.
- The server creates a private offer token and samples five distinct eligible card IDs for each player using the match PRNG.
- A card is eligible while the player's current stack count is below its stack cap.
- Selecting a card requires the current offer token and one card ID from that offer. Invalid, stale, duplicate, or out-of-state selections are rejected without changing the build.
- Choices lock immediately, but all chosen cards apply simultaneously when the draft ends. Other clients see only ready/not-ready status during the draft.
- If the timer expires, the server randomly selects one of that player's offered cards. If every player locks a choice early, the draft ends immediately.
- If fewer than five cards remain eligible, offer all eligible cards. If none remain, mark the build complete and require no selection for that player.
- After the draft, all players may inspect every participant's selected card and aggregate build through the scoreboard.
- The server seeds the match PRNG once at match start and records the seed in server logs. Tests may inject a fixed seed; production clients never choose it.

### 4.4 Heat, Round, and Match Resolution

- Each heat starts every participant alive at full derived health, full shield energy, full magazine, and no active reload or repair timer.
- Spawn assignments are shuffled by the server each heat. Controls remain locked during the countdown.
- A player at zero health is eliminated immediately and becomes a spectator for the remainder of the heat.
- When exactly one participant remains alive, that player gains one heat win.
- When zero participants remain because multiple deaths resolve during the same server tick, award no heat win and replay the heat after `HEAT_RESULT`.
- The first player to reach two heat wins gains one round win. All heat-win counters then reset to zero.
- The first player to reach `rounds_to_win` wins the match.
- A participant disconnecting during `ACTIVE_HEAT` is eliminated before survivor resolution. Disconnecting during another match state removes the participant from subsequent spawns.
- If only one participant remains connected anywhere during a match, that participant wins by forfeit. If none remain, return immediately to an empty lobby.

## 5. Arena, Camera, and Spawning

- The logical arena is 3200×1800 pixels with an impermeable outer boundary.
- The layout is rotationally symmetric: one central octagonal obstacle, four mirrored rectangular cover islands, and open circulation lanes between them.
- Provide exactly 32 spawn anchors distributed around two symmetric rings. Anchors must not overlap obstacles and must keep at least 160 pixels between neighboring ships.
- Spawn anchors are assigned without replacement. Players receive no post-countdown invulnerability because all players gain control on the same server tick.
- Ships collide with walls, obstacles, and other ships using slide response. Ship collisions deal no damage.
- Each client uses a smoothing follow camera centered on its controlled or spectated ship. The camera clamps to arena bounds and uses a fixed gameplay zoom at supported aspect ratios.
- Show edge indicators for off-screen ships within 900 pixels and for the nearest incoming off-screen projectile. Indicators must use shape plus color so color alone does not carry meaning.
- A spectator may cycle living ships with left/right mouse buttons or A/D. If no player is alive during a tie result, the camera returns to arena center.

## 6. Combat Specification

### 6.1 Base Ship and Movement

| Property | Base value |
| --- | ---: |
| Collision radius | 20 px |
| Maximum health | 100 |
| Maximum speed | 480 px/s |
| Acceleration | 900 px/s² |
| Drag | 700 px/s² |

- Normalize combined WASD input so diagonal movement is not faster.
- With movement input, move velocity toward `input_direction × maximum_speed` at `acceleration × delta`.
- Without movement input, move velocity toward zero at `drag × delta`.
- Aim is independent of movement. The ship's forward vector snaps to the latest valid cursor-derived aim angle.
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

- Holding left mouse fires automatically whenever the cooldown, ammunition, shield, and projectile limits permit.
- Reload begins automatically when the magazine reaches zero. There is no manual reload input in the vertical slice.
- Firing is disabled while reloading or shielding. Releasing the shield does not reset the fire cooldown.
- Projectiles ignore their owner, do not collide with other projectiles, and damage every other participant because the mode is free-for-all.
- A normal projectile is destroyed on its first ship, shield, wall, or obstacle collision. Piercing allows additional unshielded ship hits; ricochet allows wall/obstacle bounces. A shield always consumes the projectile regardless of remaining pierces or bounces.
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

- Holding right mouse activates the shield if it is not depletion-locked and has positive energy.
- Shielding reduces acceleration by 25%, disables firing, and leaves maximum speed and drag unchanged.
- A projectile is blockable when the vector from ship center to the projectile impact point falls inside half the current shield arc around the ship's aim direction.
- A successful block destroys the projectile and subtracts the block cost. The current projectile is still blocked if the cost takes energy to zero; the shield then deactivates and locks until energy regenerates to the threshold.
- Energy regeneration begins only after no shield activation or block has occurred for the full regeneration delay.
- Projectiles striking outside the shield arc continue to the hull. Overtime boundary damage bypasses the shield.

### 6.4 Damage, Repair, and Death

- The server applies damage once per physics tick in stable projectile-ID order.
- Health is clamped to `[0, derived_max_health]`. Zero health eliminates the player.
- Taking projectile or overtime damage resets the Auto-Repair grace timer. Repair never revives a dead player and never exceeds maximum health.
- Death removes the ship's collision and input authority immediately, despawns all projectiles owned by that player after 0.5 seconds, emits a reliable death event, and switches that client to spectating.

### 6.5 Overtime

- At 90 seconds of `ACTIVE_HEAT`, activate a centered circular safe boundary large enough to enclose the arena.
- Shrink its radius linearly to 120 pixels over 45 seconds.
- Ships outside the current safe radius take 30 health/second, accumulated continuously and applied by the server each physics tick.
- After the boundary reaches minimum radius, increase boundary damage by 10 health/second every 10 seconds, up to 100 health/second.
- The HUD announces overtime five seconds before activation and displays the boundary timer and current damage rate.

## 7. Card and Stat System

### 7.1 Evaluation Rules

`CardDefinition` is a data resource with a stable ID, category, title, description, stack cap, additive modifiers, multiplicative modifiers, and optional special behavior ID.

Derived stats are recomputed from base values whenever the build changes:

1. Sum all flat additions by stat.
2. Multiply all multiplicative factors by stat; stacking therefore compounds but does not depend on acquisition order.
3. Apply integer special additions such as projectile, pierce, and ricochet counts.
4. Apply the clamps below.

| Stat | Minimum | Maximum |
| --- | ---: | ---: |
| Maximum health | 25 | 250 |
| Maximum speed | 200 | 900 px/s |
| Acceleration | 300 | 2000 px/s² |
| Drag | 250 | 2500 px/s² |
| Projectile damage | 5 | 100 |
| Fire rate | 1 | 12 shots/s |
| Magazine | 1 | 30 |
| Reload duration | 0.35 s | 4 s |
| Projectile speed | 400 | 1800 px/s |
| Shield capacity | 20 | 250 |
| Shield regeneration | 5 | 100 energy/s |
| Shield drain | 5 | 100 energy/s |
| Shield regeneration delay | 0.25 s | 4 s |
| Shield arc | 60° | 240° |
| Projectile count | 1 | 3 |
| Pierce count | 0 | 3 |
| Ricochet count | 0 | 3 |

### 7.2 Initial Catalog

| ID | Card | Category | Effect per stack | Cap |
| --- | --- | --- | --- | ---: |
| `reinforced_hull` | Reinforced Hull | Ship | +25 maximum health; ×0.92 maximum speed | 3 |
| `overcharged_thrusters` | Overcharged Thrusters | Ship | ×1.12 maximum speed; ×1.15 acceleration; −10 maximum health | 3 |
| `vector_jets` | Vector Jets | Ship | ×1.20 acceleration; ×1.25 drag | 3 |
| `auto_repair` | Auto-Repair | Ship | After 5 seconds without damage, repair 8 health/s until damaged or full | 1 |
| `capacitor_bank` | Capacitor Bank | Shield | +30 capacity; ×0.90 regeneration | 3 |
| `quick_charge` | Quick Charge | Shield | ×1.25 regeneration; −10 capacity | 3 |
| `wide_emitter` | Wide Emitter | Shield | +20° arc; ×1.15 continuous drain | 3 |
| `efficient_field` | Efficient Field | Shield | ×0.80 continuous drain; +0.25 s regeneration delay | 3 |
| `heavy_rounds` | Heavy Rounds | Weapon | ×1.35 damage; ×0.80 fire rate | 3 |
| `rapid_cycling` | Rapid Cycling | Weapon | ×1.30 fire rate; ×0.80 damage | 3 |
| `rail_accelerant` | Rail Accelerant | Weapon | ×1.35 projectile speed; ×0.90 damage | 3 |
| `extended_magazine` | Extended Magazine | Weapon | +4 magazine; ×1.20 reload duration | 3 |
| `quick_loader` | Quick Loader | Weapon | ×0.75 reload duration; −2 magazine | 3 |
| `twin_shot` | Twin Shot | Weapon | +1 projectile; +10° total spread; ×0.70 damage | 2 |
| `piercing_rounds` | Piercing Rounds | Weapon | +1 pierce; ×0.85 damage | 3 |
| `ricochet_rounds` | Ricochet Rounds | Weapon | +1 ricochet; ×0.90 projectile speed | 3 |

For multi-projectile shots, distribute projectiles evenly across the total spread and center odd projectile counts on the aim direction. All projectiles use the final derived per-projectile damage.

## 8. Networking Specification

### 8.1 Authority and Timing

- Use `ENetMultiplayerPeer` over UDP with protocol version `1` and a maximum of 32 client peers in addition to the server.
- The server simulates at 60 Hz. Clients send the latest input at 30 Hz. Player snapshots are sent at 20 Hz; projectile correction snapshots are sent at 5 Hz.
- Use three logical channels: reliable ordered control/state events, unreliable ordered input, and unreliable ordered snapshots/projectile batches.
- The server is the only authority for admission, player IDs, simulation position, projectile creation, collision, damage, RNG, build changes, scoring, and state transitions.

### 8.2 Connection and Control Messages

Client-to-server messages:

- `client_hello(protocol_version, display_name)` — reliable, required within 10 seconds of ENet connection.
- `request_lobby_config(rounds_to_win)` — reliable, lobby leader only.
- `request_start_match()` — reliable, lobby leader only.
- `select_card(offer_token, card_id)` — reliable, current participant and draft only.
- `submit_input(sequence, client_tick, move_x, move_y, aim_angle, action_bits)` — unreliable ordered.

Server-to-client messages:

- `server_welcome(peer_id, lobby_state)` — reliable handshake acceptance.
- `connection_rejected(reason_code, display_message)` — reliable rejection followed by disconnect.
- `lobby_state(revision, leader_id, config, players)` — reliable full lobby state.
- `draft_offer(offer_token, card_ids, deadline_tick)` — reliable and sent only to its owner.
- `match_event(event_type, server_tick, payload)` — reliable transitions, card results, damage deaths, and scores.
- `world_snapshot(server_tick, acknowledged_input, player_states)` — unreliable ordered.
- `projectile_batch(server_tick, spawned, removed)` — unreliable ordered.
- `projectile_correction(server_tick, active_projectiles)` — unreliable ordered recovery snapshot.

Control payloads may use typed Godot arrays/dictionaries because they are low frequency. Input, player snapshots, and projectile payloads must use versioned `PackedByteArray` encoding with fixed field order, bounded counts, and explicit decode failure handling.

### 8.3 Input, Prediction, and Rendering

- `sequence` and ticks use wrapping unsigned 32-bit values. The server ignores duplicate or older input and remembers the most recent valid input until a newer frame arrives.
- Movement components are quantized signed 16-bit values representing `[-1, 1]`; aim is quantized to an unsigned 16-bit turn; action bits contain fire and shield flags.
- The server accepts at most 60 input messages per peer per second and disconnects a peer after sustained malformed or excessive traffic.
- The controlled client runs the shared movement function immediately, buffers at least 120 input frames, and replays unacknowledged input after every authoritative snapshot.
- Correction errors up to 128 pixels are smoothed over 100 ms. Larger errors snap immediately and increment a diagnostic counter.
- Remote players render approximately 100 ms behind server time by interpolating the two surrounding snapshots. Extrapolation is limited to 100 ms before holding the last state.
- The local client may show an immediate predicted muzzle flash and projectile. It reconciles predicted projectiles using owner ID plus shot sequence when the server spawn arrives; rejected shots fade within 100 ms.
- Clients simulate projectile visuals from authoritative spawn data. The 5 Hz correction list adds missed projectiles, corrects ricochets, and removes projectiles absent from the authoritative list.

### 8.4 Validation and Rejection

- Never trust a peer ID supplied by a client; use the RPC sender identity.
- Reject non-finite numbers, movement magnitudes above tolerance, impossible action bits, stale offer tokens, invalid card IDs, out-of-state requests, unauthorized lobby actions, and version mismatches.
- Clamp accepted movement after validation. Do not clamp malformed or non-finite messages into validity.
- Rejection reason codes are `SERVER_FULL`, `VERSION_MISMATCH`, `INVALID_NAME`, `HANDSHAKE_TIMEOUT`, `MALFORMED_TRAFFIC`, and `SERVER_CLOSED`.
- Clients display a human-readable error and return to the connection screen after rejection or network loss.
- The vertical slice provides authority and validation but no identity authentication, encryption, ban service, or denial-of-service protection.

## 9. User Experience

### 9.1 Screens

1. **Connection:** Display name, address defaulting to `127.0.0.1`, port defaulting to `7000`, Connect, Quit, and inline connection errors.
2. **Lobby:** Player list, leader marker, round target, Start button for leader, waiting message for others, and connection status.
3. **Draft:** Five or fewer card panels with name, category, exact effects, current/new stack count, selection state, and synchronized timer. Support clicking and keys 1–5.
4. **Combat HUD:** Health, shield, ammunition/reload, heat wins, round wins, alive count, heat timer, overtime warning, current cards, and collapsible Tab scoreboard.
5. **Spectator:** Current target, cycle controls, remaining players, and the normal score display.
6. **Results:** Match winner, round totals, each player's final build, and automatic return-to-lobby countdown.

### 9.2 Presentation Rules

- Use a dark space background with procedural geometric ships, bright outlines, bloom/glow, trails, shield arcs, and concise particles.
- Give every participant a stable color chosen from a high-contrast palette, then add name, outline pattern, and local-player marker so identity never depends on color alone.
- The local ship has a persistent chevron and stronger outline. Damage sources flash the impacted side; shield blocks and shield breaks have distinct effects.
- Keep critical HUD text at least 18 px at 1080p and scale UI with window size. Card body text must remain readable at 1280×720 without scrolling.
- Avoid full-screen white flashes. Screen shake is subtle, local-only, and never affects aim coordinates.
- Provide synthesized effects for fire, reload completion, shield activate/block/break, damage, elimination, card lock, countdown, overtime, round win, and match win. Music is out of scope.

## 10. Observability and Failure Handling

- The server writes JSON-line logs to stdout with UTC timestamp, level, event name, and bounded fields.
- Log startup configuration, match seed, joins/leaves, rejected requests, state transitions, heat/round/match results, shutdown, and fatal errors. Do not log every input frame or a client's IP address.
- Every 10 seconds during a match, log connected peers, active ships/projectiles, mean and maximum simulation duration, and outbound byte counts.
- A debug-only client overlay shows FPS, round-trip time, interpolation delay, reconciliation error, last acknowledged input, and active entity counts.
- Scene or payload decode failures must produce an error, reject the affected operation, and leave the server state valid. A single bad client message must not terminate the server.

## 11. Testing and Acceptance

### 11.1 Automated Tests

- **Stat tests:** Every card alone and at cap, order-independent stacking, clamps, Twin Shot spread, and build-complete offers.
- **Combat tests:** Movement normalization, fire cadence, automatic reload, shield arc edges, depletion lock, pierce, ricochet, owner immunity, overtime, repair interruption, and simultaneous lethal hits.
- **State tests:** Valid transition graph, first-to-two heat resolution with more than three heats, round target 1 and 5, draft early completion/timeout, forfeit, leader transfer, and lobby reset.
- **Protocol tests:** Encode/decode round trips, maximum bounded payloads, sequence wraparound, malformed/truncated packets, authorization, rate limiting, version mismatch, and stale card tokens.
- **Integration tests:** One server plus two protocol clients completes a seeded match, returns to lobby, starts a second match with cleared state, and exits cleanly.

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
- UI remains usable at 1280×720 and 1920×1080 with 32 listed players.

### 11.4 Release Artifacts

- `SuperStarFighter.exe` Windows x64 client export.
- `SuperStarFighterServer.exe` stripped Windows x64 dedicated-server export.
- Automated test runner and 2-client smoke-test script.
- Configurable 32-client soak-test script.
- Export script that fails nonzero when tests or export fail.
- README covering controls, local hosting, direct-IP joining, UDP port forwarding, tests, exports, known limitations, and troubleshooting.

The vertical slice is complete only when every milestone in [milestones.md](./milestones.md) is complete and all acceptance checks in this section pass.
