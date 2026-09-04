# Arena Mechanics Roadmap

The review identified three arena mechanics that should all be developed for future releases. They are product priorities because each adds a different kind of routing decision without requiring more weapons or a larger card catalog. Release timing remains subject to playtesting and multiplayer performance acceptance.

## 1. Telegraphed movement fields

**Status:** First playable implementation completed and human-accepted on Solar Tide. Visual comprehension, movement feel, counter-steering, restrained route value, and crowded-combat readability passed. Broader telemetry may inform future tuning.

Solar Current is a visible clockwise annular stream around the central sun. A pilot moving with the stream can reach up to 118% of ordinary maximum speed at full influence. The current also adds a modest directional pull that normal thrust can oppose. It does not damage, stun, drain shields, alter projectiles, or introduce synchronized runtime entities. Authority, client prediction, NPC movement, and presentation read the same static map resource.

Future improvement should use broader Solar Current playtests to decide whether to tune its width or strength. The first playtest found a slight but acceptable tactical effect, so measure whether players actually choose the route before increasing it. Its visibility, wake, countdown teaching, and counter-steering have passed initial human acceptance. If accepted more broadly, the same shared definition can support carefully differentiated fields on later maps. New fields must remain readable without relying on color and must not create one-way traps or unpredictable corrections.

## 2. Destructible cover

**Status:** Committed future-release priority; design and implementation remain.

Destructible cover can turn a protected route into a temporary tactical resource and let a match reshape a lane through deliberate pressure. Durability and destruction must be server-owned, bounded, included in late-join snapshots, and deterministic under simultaneous hits. Collision and NPC route data must change on the same authoritative transition.

Acceptance requires clear intact, damaged, critical, and destroyed states; readable weapon feedback; no invisible collision remnants; safe spawn and overtime routes in every cover state; and a strict cap on replicated state and debris effects. Cover placement and durability must avoid making concentrated fire the only sensible opening or enabling permanent spawn traps.

## 3. Teleporter relays

**Status:** Committed future-release priority; design and implementation remain.

Paired relays can create flank, escape, and objective-route choices that ordinary cover cannot. Every entrance must communicate its destination and current availability. Activation, transit, and arrival should be visible long enough for opponents to understand the play while remaining responsive for the pilot using it.

Acceptance requires server-authoritative transit, client reconciliation, explicit projectile and carried-object rules, cooldown and anti-loop behavior, safe arrival occupancy handling, and useful NPC routing. Relays must not permit unavoidable arrival ambushes, objective exploits, infinite loops, or unbounded replicated events. Reconnect, spectator, and late-join clients must reconstruct relay state correctly.

## Sequencing

1. Complete human and multiplayer acceptance for Solar Current, then keep or tune it from observed route choices and combat readability.
2. Prototype destructible cover on one map with a small fixed state budget and test all geometry states at 2, 8, 16, and 32 participants.
3. Prototype one paired teleporter relay after its transport, objective, spawn, and NPC policies are specified.
4. Expand any mechanic to additional maps only when its first implementation meets server tick, bandwidth, prediction, accessibility, and counterplay targets.

All three mechanics remain on the future-release roadmap even if an individual prototype needs substantial revision. Their shipped forms should be judged by play value, clarity, and multiplayer cost rather than by implementation novelty.
