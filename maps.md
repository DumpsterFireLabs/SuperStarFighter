# Super Star Fighter — Ten-Map Expansion Plan

**Status:** Static ten-map roster and authoritative per-round rotation implemented. Advanced map mechanics and manual lobby selection remain planned.

**Scope:** Preserve the existing arena, add nine distinct static topologies, rotate them authoritatively between rounds, and retain the advanced-mechanics/full-capacity roadmap.

**Related documents:** [Product plan](./plan.md) · [Specification](./spec.md) · [Implementation milestones](./milestones.md)

## 1. Outcome

Super Star Fighter has a ten-map static roster. The existing 3200×1800 arena remains the neutral competitive benchmark; nine additional arenas introduce materially different sightlines, routing, cover, and weapon interactions without changing the core ship or card rules.

Every map must support all 32 participants at once. “Supports 32” means every map definition contains exactly 32 simultaneously usable spawn anchors and passes automated clearance, separation, reachability, and hazard-safety checks. Lower-capacity matches use a server-shuffled subset of the same validated anchors.

At match start the server creates a deterministic shuffled deck containing all ten maps. A map is selected when a round begins and remains fixed through every heat, tied replay, and the round-result presentation. Only a completed round advances to the next map; the deck does not repeat until all ten maps have appeared. Manual lobby selection and voting are future options and will not change this heat-stability rule.

## 2. Non-Negotiable Map Contract

This section defines the target contract for the expansion, including future dynamic mechanics and a proposed `MapDefinition` resource. It is not a claim that every item has shipped. Current static maps are implemented through `ArenaLayout`; the test suite verifies the implemented geometry and mode rules. Dynamic hazard safe states, portals, manual selection, and the proposed resource/validator remain roadmap work.

All ten maps use the current 3200×1800 logical playfield for the first release. Shared dimensions keep camera behavior, overtime timing, network quantization, projectile budgets, and existing movement balance comparable. A later large-map experiment can extend the data format without making the first map pack harder to validate.

### 2.1 Thirty-two clear starting positions

Every map must satisfy all of the following in code and in automated tests:

- Define exactly **32 unique spawn anchors**.
- Keep anchor centers at least **160 px apart**, matching the current multiplayer spacing contract.
- Reserve a **96 px obstacle-free spawn disk** around every anchor. No wall, cover shape, portal, force field, damaging volume, moving obstacle envelope, or outer boundary may touch this closed disk. With the 20 px ship radius, this leaves at least 76 px of open space beyond the hull.
- Provide at least **two obstacle-clear exit headings** from every spawn disk into the main navigation region. Each exit corridor is at least 96 px wide and 180 px long, preventing a ship from beginning inside a decorative pocket or one-way trap.
- Keep every anchor on the same ship-navigable component as the overtime destination. Portals, opening doors, or timed mechanics may provide shortcuts, but may never be the only route to safety.
- Disable damage, forced movement, teleportation, and moving geometry inside every spawn disk during countdown and for the first three seconds of an active heat.
- Validate the complete 32-anchor set, even when the current lobby contains fewer players. Spawn assignment remains shuffled authoritatively each heat.
- Render spawn markers only in developer/debug views; the production arena does not advertise future spawn locations.

`MapDefinition.validate()` must fail project verification when any invariant is violated. Validation uses collision shapes expanded by the spawn-clear radius, not approximate artwork bounds.

### 2.2 Fairness and overtime

- The overtime destination is explicit map data rather than assumed to be the global arena center.
- Every spawn must have a collision-free route to the overtime destination for a ship at full collision radius.
- Static geometry must leave at least three independent approaches into the final 420 px around the overtime destination. No map may reduce overtime to a single campable doorway.
- Dynamic map mechanics enter a deterministic overtime-safe state at the five-second warning. Moving walls stop in validated positions, movement fields weaken, and portals remain optional rather than mandatory.
- No spawn has direct unobstructed line of fire into more than eight other spawn disks. This reduces full-lobby countdown firing galleries without requiring every spawn to be visually isolated.
- Symmetric or rotationally balanced anchor groups are preferred. Any intentional asymmetry requires spawn-rotation simulation to show that repeated heat assignment distributes it evenly.

### 2.3 Gameplay and networking

- The server owns the selected map, collision, dynamic mechanic state, and map RNG seed.
- Clients receive the stable map ID and mechanic seed before countdown and must load the matching local presentation before accepting combat snapshots.
- Unknown or incompatible map IDs reject admission cleanly as a content/protocol mismatch.
- Map mechanics must use bounded state and events. They may not add per-frame reliable traffic or bypass the existing authoritative movement, projectile, damage, and entity limits.
- NPC line-of-sight, flanking, overtime steering, and navigation must query the selected map rather than the original arena’s hard-coded rectangles and center obstacle.

## 3. Ten-Map Roster

Names are working titles and can change without changing the mechanical plan.

### Map 01 — Core Arena (existing benchmark)

- **Identity:** The current central octagon with four mirrored cover islands.
- **Play style:** Balanced; a control case for card and weapon tuning.
- **Feature:** Clean mix of open fire lanes, simple cover, and circular overtime pressure.
- **Spawn plan:** Preserve the existing 12-anchor inner ring and 20-anchor outer ellipse after upgrading them to the new 96 px clearance and egress validation.
- **Purpose in testing:** Every generic map-system migration must reproduce current collision, visuals, NPC behavior, spawn assignment, and overtime behavior here before new layouts are enabled.

### Map 02 — Riftline

- **Identity:** A long fractured divider runs north–south, crossed by three broad gaps and two offset end routes.
- **Play style:** Lane control, ambushes, and deliberate rotations. Short-range builds can approach under cover while long-range builds contest crossings.
- **Unique feature:** The divider’s middle gap widens during the overtime warning, ensuring the endgame becomes more connected instead of more congested.
- **Spawn plan:** Four open staging fields hold eight anchors each. Every field has one route to the nearest crossing and one route around a divider end.
- **Overtime:** Centered on the widened middle crossing, with north, south, east, and west approaches remaining open.

### Map 03 — Prism Array

- **Identity:** Eight angled prism fins form offset chevrons around an open center.
- **Play style:** Ricochet mastery, bank shots, and rapidly changing firing angles. Straight-line beam builds retain strong central lanes but cannot dominate every approach.
- **Unique feature:** Angled reflective surfaces use the existing ricochet rules; they do not create a separate projectile type or random reflection.
- **Spawn plan:** Sixteen anchors on an outer ellipse and sixteen in four open corner fans. Prism tips remain at least 96 px outside every spawn disk.
- **Overtime:** The prisms point tangentially around the final zone, leaving four direct and four bank-shot approaches.

### Map 04 — Twin Suns

- **Identity:** Two large circular reactor obstacles sit east and west of center, creating a figure-eight flow.
- **Play style:** Flanking, pursuit, and shield-angle mind games. Players can orbit a reactor, switch loops through the middle, or take the exposed outer route.
- **Unique feature:** The paired round obstacles make aim tracking and NPC flanking meaningfully different from rectangular cover.
- **Spawn plan:** Eight anchors in each of four outer quadrants, all outside the reactor orbit lanes with inward and perimeter exits.
- **Overtime:** Centered between the reactors. The north, south, east, and west gaps remain wider than two ship diameters after collision expansion.

### Map 05 — Dead Freight

- **Identity:** Six cargo clusters create compact courtyards and short, offset corridors without becoming a maze.
- **Play style:** Close quarters, scatter weapons, piercing, shields, and quick disengagements. Long-range builds must earn sightlines by controlling courtyards.
- **Unique feature:** Selected cargo panels are destructible. They have shared fixed health, never respawn during a heat, and open new lanes for everyone when destroyed.
- **Spawn plan:** Four cargo-free launch aprons contain eight anchors each. No destructible panel is close enough to expose or obstruct a spawn disk when it breaks.
- **Overtime:** Destructible panels surrounding the central yard automatically retract at warning time, guaranteeing multiple final approaches.

### Map 06 — Longwave Array

- **Identity:** The sparsest map: four low-profile sensor fins near the perimeter and two narrow midfield screens.
- **Play style:** Speed, projectile lifetime, accuracy, leading, and long-range beam duels. Minimal cover makes positioning and shield timing decisive.
- **Unique feature:** Broad uninterrupted diagonals provide the roster’s clearest long-range combat without creating spawn-to-spawn shooting galleries.
- **Spawn plan:** Twenty anchors use recessed perimeter bays with angled sight blockers; twelve use four open mid-perimeter pads. Every bay has two exits and opens sideways rather than toward the opposite spawn bank.
- **Overtime:** The final circle remains largely open, with the midfield screens providing limited relief rather than a permanent bunker.

### Map 07 — Broken Orbit

- **Identity:** Three incomplete concentric rings have deliberately misaligned gaps.
- **Play style:** Circular rotations, interception, pursuit, and choosing when to move inward. Players can stay within a ring lane or cut across at exposed gaps.
- **Unique feature:** Ring segments are smooth collision arcs, expanding the geometry system beyond circles and axis-aligned rectangles.
- **Spawn plan:** Four eight-anchor sectors sit between the outer boundary and outer ring. Each anchor has clockwise and counter-clockwise egress, and every sector has two inward gaps.
- **Overtime:** Ring gaps align into at least four inward routes during warning; no closed ring may separate a survivor from safety.

### Map 08 — Switchyard

- **Identity:** Six rail-mounted barrier pairs form a readable grid of rooms and lanes.
- **Play style:** Adaptation and route planning. The same visual arena supports open diagonals, tight side lanes, or a broad central channel on different heats.
- **Unique feature:** At heat setup, the server chooses one of three prevalidated barrier configurations from the match seed. Barriers never move during active combat; their next configuration is previewed during countdown.
- **Spawn plan:** Eight permanent launch pads contain four anchors each. Spawn clearance and egress must pass against the union of all three barrier configurations, not only the selected configuration.
- **Overtime:** Every configuration has four routes into the center. Barrier selection never changes after countdown begins.

### Map 09 — Solar Tide

- **Identity:** Four luminous current lanes sweep tangentially around a calm central basin.
- **Play style:** Momentum, high-speed rotations, interception, and daring escapes. Pilots can ride a current for fast repositioning or fight across it for a shorter route.
- **Unique feature:** Clearly telegraphed movement fields add a bounded world-space acceleration to ships, never projectiles. The force respects the normal speed and collision systems and weakens during overtime warning.
- **Spawn plan:** Four calm docks contain eight anchors each. Spawn disks and both exit corridors lie completely outside current volumes.
- **Overtime:** Currents fade to 25% strength at warning time and to zero when the circle reaches its minimum radius.

### Map 10 — Relay Zero

- **Identity:** Four paired relay gates connect distant sides of an otherwise moderately covered arena.
- **Play style:** Rapid flanks, escapes, prediction, and map awareness. Conventional routes remain viable, while relays reward players who track exit positions.
- **Unique feature:** Ships may enter a relay after a short visible charge and emerge with preserved facing but capped velocity. A per-ship cooldown prevents loops. Projectiles do not teleport in the first implementation.
- **Spawn plan:** Eight shielded launch bays contain four anchors each. Every relay entrance and exit is at least 240 px from a spawn disk, and each bay has two ordinary non-relay exits.
- **Overtime:** Relays remain active but are never required to reach center. Exits outside the current safe circle disable automatically so a relay cannot involuntarily eject a player into overtime damage.

## 4. Technical Foundation

The current `ArenaLayout` is a static singleton and assumes one central circle plus four rectangles. It should be migrated before authoring new maps.

### 4.1 Data model

Introduce a dedicated-server-safe `MapDefinition` containing:

- stable ID, display name, revision, logical bounds, overtime center, and visual theme ID;
- exactly 32 spawn anchors plus optional authored exit headings;
- typed collision primitives: rectangles, circles, convex polygons, and sampled arc segments;
- mechanic descriptors with bounded parameters and deterministic seeds;
- presentation-only labels and palette references kept outside server exports where practical.

A `MapRegistry` loads all built-in definitions, rejects duplicate IDs, validates every map at startup, and exposes maps in stable display order. The current layout becomes `core_arena`; no gameplay code should special-case it after migration.

### 4.2 Shared geometry services

Replace direct calls to `ArenaLayout.cover_rectangles()`, `CENTRAL_RADIUS`, and global arena center with a selected `MapGeometry` service. It provides:

- ship sweep/collision resolution;
- projectile collision normal and ricochet response;
- segment line-of-sight queries for NPCs;
- spawn validation and free-space queries;
- overtime center and initial-radius calculation;
- coarse navigation connectivity used by validation and NPC routing.

The same map definition drives authoritative collision and client drawing. Client decorative art may add detail but must never imply collision that the server does not have.

### 4.3 Match and lobby integration

- The authoritative match payload carries the current `map_id` and visible map name through draft, countdown, combat, results, and late-spectator synchronization.
- The match seed creates a stable shuffled rotation without consuming draft or spawn randomness.
- Change maps only when entering a new round; every heat and tied replay retains the current geometry.
- Rebuild client collision/presentation before countdown and clear stale projectile state when geometry changes.
- A future leader-only selector may choose the rotation pool or order, but must not permit per-heat changes.

### 4.4 Dynamic mechanics

Dynamic features use a small authoritative interface: `reset_for_heat(seed)`, `step(delta)`, `apply_ship_effect(combatant)`, `apply_projectile_effect(projectile)`, and `snapshot_state()`. Each map opts into only the methods it needs.

Mechanic state must be deterministic or explicitly synchronized at a bounded rate. Destructible panel removal is a reliable event; movement fields are static volumes with time derived from authoritative heat ticks; Switchyard configuration is a reliable heat-setup value; relay transitions are authoritative combat events.

## 5. Delivery Stages

### Stage A — Map data foundation

- Create `MapDefinition`, `MapRegistry`, collision primitives, validation, and selected-map geometry services.
- Migrate Core Arena with no intentional visual or gameplay change.
- Route overtime, NPC navigation, collision, sandbox rendering, network world rendering, and spawn assignment through the selected definition.
- Exit when the existing assertion, real match-loop, NPC-lobby, and presentation gates pass unchanged on Core Arena.

### Stage B — Selection and synchronization

- Add lobby map selection, Random resolution, discovery metadata, pre-match loading, and revision mismatch handling.
- Verify local host, LAN join, direct join, late spectator, lobby return, and same-lobby rematch on a non-default map ID.
- Exit when no client can enter countdown with a different map or mechanic seed from the server.

### Stage C — Static topology pack

- Deliver Riftline, Prism Array, Twin Suns, Longwave Array, and Broken Orbit.
- Add polygon, circle, and arc rendering/collision plus map-aware NPC line-of-sight and flanking.
- Tune geometry using 2-, 8-, 16-, and 32-participant bot matches.
- Exit when all six available maps pass the full spawn and reachability contract.

### Stage D — Stateful map mechanics

- Deliver Dead Freight destructibles, Switchyard heat configurations, Solar Tide movement fields, and Relay Zero teleporters.
- Add bounded mechanic events/snapshots, reset logic, spectator presentation, and diagnostics.
- Exit when dynamic state remains synchronized through elimination, overtime, reconnect-to-lobby, and two consecutive matches.

### Stage E — Presentation and balance

- Give every map a distinct palette, floor treatment, obstacle language, ambience, minimap/scoreboard name, and loading plate while retaining ship/card readability.
- Add map-specific NPC navigation hints only where generic geometry queries are insufficient.
- Review sightline lengths, cover density, average first-contact time, overtime convergence, beam dominance, ricochet opportunity, and short-range viability.
- Exit when each map has a recognizable play style without invalidating an entire major weapon family.

### Stage F — Full-capacity acceptance

- Run the geometry validator and automated 32-anchor spawn test for all ten maps.
- Run repeated 32-NPC heat simulations on every map with randomized spawn assignment and card builds.
- Run real-protocol 32-client soak coverage across a deterministic map rotation.
- Complete two consecutive real matches while switching maps in the lobby between them.
- Capture countdown, active combat, overtime, spectator, and victory states for every map at 1280×720, 1920×1080, 2560×1080, and 3440×1440.

## 6. Acceptance Matrix

| Area | Required evidence |
| --- | --- |
| Registry | Ten unique built-in IDs and revisions load in stable order; invalid and duplicate definitions fail startup verification. |
| Spawn capacity | Every map exposes exactly 32 anchors; all 320 anchors pass 96 px clearance, 160 px separation, two-exit, hazard, and boundary checks. |
| Navigation | A collision-expanded flood-fill or navigation query reaches the overtime region from every anchor without relying on portals or timed doors. |
| Collision | Ships, standard projectiles, ricochets, piercing shots, and beams agree with authored rectangles, circles, polygons, and arcs. |
| Networking | Host, remote clients, spectators, and NPCs use the same map ID, revision, seed, geometry, and mechanic state. |
| Match lifecycle | Draft, both heats, overtime, round transition, victory, exit to lobby, map change, and rematch clear and rebuild map state correctly. |
| NPCs | NPCs route around selected-map cover, respect hazards and overtime, use relays intentionally, and do not enter symmetric cover loops. |
| Performance | A 32-participant match on the most expensive map stays inside the existing 60 Hz server tick budget and entity limits. |
| Presentation | Collision is visually legible, spawn/debug markers remain hidden in production, and all ten maps frame correctly at supported 16:9 and ultrawide resolutions. |

## 7. Scope Guardrails

- The pack ships as built-in content; downloadable maps and user-authored map loading are not part of this milestone.
- Map voting, custom playlists, procedural maps, and public-server content distribution are deferred; built-in per-round rotation is implemented.
- Environmental mechanics must create routing choices, not unavoidable damage or random deaths.
- No map-specific card balance modifiers. Cards retain the same authoritative definitions on every map.
- The current specification continues to describe the implemented one-map slice until Stage A begins. Implementation must update `spec.md`, network protocol versioning, tests, manual text, and milestone evidence together.
