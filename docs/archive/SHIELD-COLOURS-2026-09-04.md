# Stable shield rarity colours — 2026-09-04

Perfect Guard previously replaced the entire shield's colour with `#fff36a`, exactly the Legendary card colour. An Epic shield (`#d39cff`) therefore alternated purple/gold as the NPC raised it, exhausted the guard window, or received successful-guard feedback. The highest-rarity selector itself correctly chooses the highest positive-count **shield** card, independent of dictionary order or stack count.

The outer shield now retains that build colour. A short white inner arc identifies the guard window and its brief successful-guard confirmation. It sits inside the green health ring so the two cues do not cover each other. Existing white impact flashes remain impact feedback, and reduced-flash mode continues to suppress those flashes while retaining the guard timing cue. Shield geometry, hit detection, energy costs, timing, NPC policy and replication are unchanged.

Validation used the actual rendered `CombatShipView._draw()` path. The verifier samples outer-arc pixels for Base, Epic, Legendary and Mythical shields across normal, guard-window and guard-confirmation states, with reduced flashes both off and on: **24 colour checks and 16 guard-indicator checks**. Running the same fixture with the original draw method reproduced the colour collision; its Epic guard pixel was Legendary gold. The changed renderer passed every check, and the comparison was visually inspected.

The full suite passed **7,402 assertions**, including mixed Epic/Legendary builds in both dictionary orders, larger Epic stack counts, expired Legendary stacks and an empty build. Editor import and shipping resource checks passed. The existing exact Windows certificate-store diagnostic was the only allowed environment error.

Run `tools/verify-shield-colors.ps1` to reproduce the rendered verification. [Before](shield-colour-evidence-2026-09-04/before.png), [after](shield-colour-evidence-2026-09-04/after.png) and [validation markers](shield-colour-evidence-2026-09-04/validation.txt) are retained. Columns show normal, guard window and guard confirmation; rows show Base, Epic, Legendary and Mythical.
