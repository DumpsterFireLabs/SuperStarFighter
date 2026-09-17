# Optional arena effects

Enable effects in **Match Setup → Arena Rules → Arena effects**. Only the lobby leader can change these settings before a match; changes clear human readiness. Guests see the same settings. Defaults are Off. The Chaos preset chooses Map signature; the other presets restore Off.

- **Off:** the normal static arenas.
- **Map signature:** solar pulses on Twin Suns, destructible cargo on Dead Freight, and blast doors on Switchyard.
- **Custom:** individually allow those effects on their compatible maps. Other maps retain their existing behaviour, including Solar Tide's movement field.
- **Event frequency:** Low / Normal / High use 24 / 18 / 12 second cycles for pulses and doors.
- **Hazard strength:** Gentle / Standard / Brutal deal 8 / 16 / 28 solar damage. Cargo durability stays fixed and doors never inflict damage.

## Solar pulses — Twin Suns

After three seconds of opening grace, one reactor warns for three seconds before emitting an expanding ring. Subsequent cycles alternate reactors. The ring travels at 650 pixels per second. Exposed ships receive one hit per life per pulse and a bounded outward impulse. The other reactor provides shelter, highlighted during the warning. A directional shield facing the emitting reactor blocks the pulse through the existing shield-energy rules. NPCs turn their shields toward the source during the warning and wave.

Respawned pilots receive three seconds of pulse protection. A wave that passes during protection does not apply delayed damage when protection expires. Solar eliminations explicitly say **SOLAR PULSE** in the death explanation.

## Destructible cargo — Dead Freight

The six cargo blocks each have 120 health. Direct cannon, beam, and missile impacts damage them, including point-blank shots whose muzzle overlaps a block. Outlines, health bars, and cracks identify damaged cargo. Destroyed blocks disappear for everyone and open ship movement, projectile sightlines, and NPC routes. Destruction persists for the rest of that heat. Mine blasts and ship contact do not damage cargo in this prototype.

## Alternating blast doors — Switchyard

The four horizontal barriers act as doors; the two central barriers remain structural. Doors start open. Each cycle leaves all doors open for three seconds, warns for three seconds, then closes the upper or lower pair until the next cycle. The closing group alternates each cycle.

An occupied door waits with its warning visible until the ship clears its footprint. Once closed, a door stays closed until its scheduled opening. The original static layout remains the most restrictive possible configuration, preserving normal routes and objective access.

## Heat, pause, and overtime rules

Terrain restores and schedules restart each heat. Global pause freezes effects. Five seconds before overtime begins, pulses stop, all doors open, and remaining breakable cargo retracts. This safe state persists through overtime. All effects use the server's heat clock; cosmetic pulse interpolation stops during pause.

Server state includes cargo health, open terrain, warning phases, and pulse position. Reliable updates arrive at up to 10 Hz, with immediate terrain-mask changes. A full state is included in match-state payloads for late spectators. Ship prediction, authoritative collision, projectile rendering, respawn checks, and NPC route caches all use the same terrain mask without mutating shared map resources. Network protocol is 37; clients and servers must use matching builds.

## Verification

`tests/unit/arena_effect_tests.gd` runs through the normal unit suite. It covers settings authority and validation, real projectile damage, heat resets, geometry-cache isolation, prediction parity, NPC routing, pulse cover and shield protection, respawn grace, occupied and closed doors, death attribution, and all five modes with 32 pilots on each effect map.

Rendered evidence can be regenerated with Godot's `--script res://src/test/arena_effect_capture.gd` using a graphical renderer. Images are written to `.tools/arena-captures`. The capture includes the actual lobby controls at 1280×720 and all three effects.

Freely orbiting terrain, additional hazards, and cross-map combinations remain future work. This release implements the first three-effect prototype.
