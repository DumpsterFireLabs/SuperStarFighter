# Super Star Fighter — Multiplayer Vertical Slice

## Summary

Build a Windows-first, top-down 2D arena shooter in **Godot 4.7.2 Standard with GDScript**. Godot 4.7.2 is the current stable release, while its ENet multiplayer API and dedicated-server export support the required authoritative 32-player architecture. [Godot download](https://godotengine.org/download/windows/) · [ENet multiplayer](https://docs.godotengine.org/en/4.6/tutorials/networking/high_level_multiplayer.html) · [Dedicated-server exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)

The empty workspace will become a complete vertical slice containing a Windows client, headless server, one arena, card drafting, match flow, server-owned NPC opponents, neon-vector presentation, tests, load-test clients, export scripts, and operating instructions.

## Documentation Set

- [spec.md](./spec.md) is the authoritative, decision-complete gameplay and technical specification. Implementation behavior, constants, interfaces, edge cases, and acceptance requirements come from that document.
- [milestones.md](./milestones.md) divides the specification into ordered, independently verifiable implementation stages. A milestone is complete only when its stated exit criteria pass.
- This plan remains the concise product direction. If wording here conflicts with `spec.md`, the specification takes precedence; intentional behavior changes must update all affected documents in the same change.

## Gameplay and Content

- Support 2–32 total participants in free-for-all matches, consisting of human players and optional server-owned NPC opponents. A lobby leader may set the total seat limit from 2 through the server capacity (never above 32), enable NPC fill, and force-start alone; NPC fill occupies every vacant configured seat and waiting NPCs yield seats to joining humans.
- Players move in ship-relative space with `W`/`S` for forward/back and `A`/`D` for strafing, using acceleration, drag, and independent mouse-facing; hold left-click to fire and right-click for a forward shield.
- Each round starts with a simultaneous 30-second draft. Everyone drafts before round one; after that, the previous round winner keeps their existing build while every other participant receives five distinct server-generated card offers. Humans choose from a private rendered draw while NPCs lock a server-selected offer. Human timeout causes a random offered card to be selected. A fully capped build follows the reduced-offer/build-complete rules in `spec.md`.
- Cards stack and persist until the match ends. All players draft before round one and every subsequent round.
- A heat ends when one ship remains. Eliminated players spectate surviving ships until the next heat. The first player to win two heats wins the round; heat scores then reset.
- The first player to win the configured number of rounds wins the match. The lobby leader selects 1–5 round wins, defaulting to 3.
- At 90 seconds, a circular damage boundary shrinks to the arena center over 45 seconds and deals 30 health per second through shields. If every survivor dies during the same server tick, replay the heat without awarding a point.
- Disconnecting during a heat counts as elimination. Late joiners spectate until the next match; reconnect recovery is not included.
- Use one symmetric 3200×1800 arena with outer walls, a central octagonal obstacle, four mirrored cover islands, and 32 shuffled spawn anchors.
- Starting combat values: 100 health, 480 px/s maximum speed, 900 px/s² acceleration, 25 projectile damage, four shots/second, eight-round magazine, 1.5-second automatic reload, and 900 px/s projectile speed.
- The directional shield covers a 120-degree forward arc. It has 100 energy, drains 20/second while held plus 25 per blocked shot, and regenerates at 30/second after a 1.25-second delay. Shielding disables firing and reduces acceleration by 25%.
- The launch catalog contains 36 cards across ship, shield, and weapon categories. Five rarity tiers use visible tier weights (Common 45%, Uncommon 28%, Rare 16%, Epic 8%, Legendary 3%); the server rolls tiers and cards authoritatively without replacement for each offer. Beam Emitter, Laser Repeater, and Prismatic Lance enable pulse-beam builds.
- Cards use explicit additive/multiplicative modifiers and recompute derived stats from base values, making stacking order-independent. Cards may be pure upgrades, tradeoffs, or transformative effects; positive effects from different picks deliberately compound into extreme late-match builds. Hard limits protect transport, physics, and entity budgets rather than enforcing a narrow balance ceiling. Stack caps are declared per card from one through four.
- Present the game with an animated splash, procedural neon geometry, glow, projectile and beam trails, shield arcs, impact particles, distinct color-and-pattern player identities, nameplates, synthesized placeholder sound effects, and drop-in support for original or licensed menu/gameplay/victory music.
- Include connection, lobby, audio settings, draft, combat HUD, Escape pilot menu, spectator, and dedicated victory screens. The HUD exposes health, shield, ammo/reload, survivors, heat points, round standings, overtime status, and current card stacks; the lobby UI is absent during the match loop.

## Architecture and Interfaces

- Use one Godot project with shared deterministic combat/stat code and separate client/server startup paths. Export Windows x64 client and stripped headless server builds.
- Run an authoritative 60 Hz server. Clients send sequenced input at 30 Hz; the server publishes world snapshots at 20 Hz. Use local movement prediction and reconciliation for the controlled ship and approximately 100 ms interpolation for remote ships.
- Separate ENet traffic into unreliable-ordered input, unreliable-ordered snapshots, and reliable match/control events. The server exclusively owns movement validation, projectiles, collision, damage, shield energy, RNG, card offers, deaths, and state transitions.
- Model the match as `LOBBY → DRAFT → COUNTDOWN → ACTIVE_HEAT → HEAT_RESULT → ROUND_RESULT → MATCH_RESULT`. Reliable events carry transitions and scores; snapshots carry transient world state.
- Define typed shared models:
  - `MatchConfig`: protocol version, maximum players, rounds-to-win, port, draft duration, and overtime timings.
  - `PlayerInputFrame`: sequence, simulation tick, normalized movement, aim angle, fire state, and shield state.
  - `CardDefinition`: stable ID, category, display text, stack cap, modifiers, and optional special behavior.
  - `PlayerMatchState`: peer ID, display name, alive/spectator state, health, shield, ammo, heat wins, round wins, and card stacks.
- Expose reliable client requests for handshake, lobby start/settings, and card selection. Validate the requesting peer from the RPC sender rather than trusting IDs in payloads.
- Use compact snapshot payloads with stable entity IDs. Reject malformed, stale, non-finite, out-of-range, excessive-rate, and protocol-incompatible input.
- Provide server options: `--server`, `--port=7000`, `--max-players=32`, `--rounds-to-win=3`, and a test-only `--auto-start`.
- Clients connect through an IP/hostname and UDP port. The first connected player becomes lobby leader; leadership transfers to the earliest remaining player on disconnect.
- NPCs consume match participant seats but no ENet client connections. Their movement, targeting, firing, shielding, and draft choices run exclusively on the authoritative server through the same validated combat-input and card systems used for humans.
- Add a headless test-client mode that connects through the real protocol, drafts cards, and generates scripted movement/combat input. It remains developer tooling and is not exposed as playable AI.
- Initialize Git, add Godot-appropriate ignores, and provide PowerShell commands for tests, client/server exports, local server startup, and multi-client smoke tests.

## Test Plan and Acceptance

- Unit-test stat recomputation, stacking caps, card-offer uniqueness, seeded RNG reproducibility, shield-angle detection, projectile damage, reload timing, overtime damage, and input validation.
- Exercise the complete match state machine, including draft timeout, first-to-two heat scoring with multiplayer ties beyond three heats, configurable round targets, simultaneous deaths, leader transfer, active-player disconnects, and late spectators.
- Run integration tests with one headless server and two protocol clients through a complete match, verifying authoritative card selection, combat, scores, rematch reset, and clean shutdown.
- Run a 32-client, ten-minute local soak test using randomized real-protocol test clients. Require all peers to connect and remain synchronized, no unhandled errors, invalid states, orphan nodes, or unbounded entity/allocation trends, and server p95 simulation time to remain within its 16.67 ms tick budget on the development machine.
- Manually verify prediction, interpolation, shield feedback, spectator cycling, card readability, and all HUD states at 1280×720 and 1920×1080.
- Confirm the exported Windows client connects to the exported headless server over localhost and LAN, and document that public direct-IP hosting requires forwarding the configured UDP port.

## Assumptions and Defaults

- Godot and its export templates are not currently installed; implementation will bootstrap the official portable Godot 4.7.2 Standard tools.
- The vertical slice has no public server browser, matchmaking, accounts, persistence, teams, chat, controller support, configurable NPC difficulty, cosmetics, monetization, or reconnect restoration.
- Balance values are initial playable defaults stored as data resources so they can be tuned without changing networking or combat code.
- Direct-IP traffic is unauthenticated and unencrypted for this milestone; server authority protects game state but is not a substitute for a production account or anti-abuse service.
