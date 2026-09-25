# Card balance review — 7 September 2026

Follow-up: [controlled combat, objective, and NPC draft validation](CARD_BALANCE_VALIDATION_2026-09-07.md) records 480 bot combat/objective runs, 960 draft samples, a beam-aiming fix, and a clean 9,465-assertion suite. It identifies a focused playtesting watchlist without making further card-value changes.

## Draft design decision

Build awareness is the player's responsibility. Dud and net-negative offers are intentional parts of the game. Do not introduce build-based offer filtering, prerequisite guarantees, or a rule that every repeat pick must improve a build. Explain actual effects, limits, and tradeoffs so players can make informed choices.

This resolves the suggested conditional-offer follow-up: Tight Bore without spread and Damage Control without auto-repair may remain in offers. It also means a capped Omnidirectional Field or a harmful multishot/Hot Load repeat is not, by itself, a balance defect requiring a buff or scaling redesign. Evaluate rarity and power in context; do not use monotonic improvement as a balance requirement. The implemented output-loss previews support this design.

This decision introduces no gameplay or draft-rule change. NPC and timeout candidate rules are unchanged. NPC scoring has subsequently been updated as described below; remaining review work focuses on match playtesting, contextual rarity/power assessment, and the accuracy of player-facing information.

Vectored Nozzles is a credible Common outlier. The larger catalog also has weak higher-tier alternatives, ineffective advertised bonuses, and repeat-pick penalties that rarity changes alone would not fix. The review below records the pre-pass state. The first pass has since been applied; see the implementation notes at the end for current values.

The review covers the current 136-card catalog: 19 Common, 26 Uncommon, 30 Rare, 22 Epic, 18 Legendary, 12 Mythical, and 9 Unobtanium. Every card was derived at one, three, and five copies using the actual `StatSystem`, including clamps. `WeaponState` was stepped for 120 seconds per build at the configured physics rate, continuously firing without shielding. Catalog validation passed for all 136 cards and all 408 samples completed.

Evidence: [pre-pass snapshot JSON](card-balance-evidence-2026-09-07.json) and [Godot snapshot script](card-balance-evidence-2026-09-07.gd). Recalculate the current working tree from the repository root with the command below. It writes `.tools/card-balance-current.json`, preserving the dated pre-pass evidence:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script docs/archive/card-balance-evidence-2026-09-07.gd
```

The firing measurements assume every projectile hits one target, exclude collision and travel effects, and include the opening full magazine. They measure potential output, not match strength. Movement and shield timing metrics are analytical. No human match telemetry or win-rate evidence was collected. Proposed values below are starting points for playtesting, not experimentally established optima.

## Vectored Nozzles

[`vectored_nozzles.tres`](../../data/cards/vectored_nozzles.tres) multiplies acceleration by 1.12 and shield acceleration factor by 1.08. [`MovementSystem`](../../src/shared/combat/movement_system.gd) multiplies those stats together while shielding: **1.12 × 1.08 = 1.2096**, or **+20.96% effective shielded acceleration**. It also improves unshielded acceleration by 12%, with no downside.

| Copies | Normal acceleration improvement | Shielded acceleration improvement |
| --- | ---: | ---: |
| 1 | +12.0% | +21.0% |
| 3 | +40.5% | +77.0% |
| 5 | +76.2% | +158.9% |

On the base ship, one copy reduces shielded time from rest to maximum speed from 0.711 to 0.588 seconds. Three copies bring shielded acceleration above an unmodified ship's unshielded acceleration. Maximum speed and passive braking are unchanged, so this is a responsiveness advantage rather than a top-speed increase.

Its closest comparisons are revealing:

| Card | Tier | Shielded acceleration gain, one copy | Other effects |
| --- | --- | ---: | --- |
| Vectored Nozzles | Common | +20.96% | +12% normal acceleration |
| Pursuit Screen | Uncommon | +18% | −10% shield arc |
| Shielded Drive | Uncommon | +20% | −8% shield drain |
| Plasma Thrusters | Uncommon | +18% | +12% maximum speed |
| Vector Jets | Uncommon | +20% | +20% normal acceleration; +25% passive braking |
| Mobile Bulwark | Rare | +35% | +15% shield drain |

Nozzles does not strictly dominate Shielded Drive or Vector Jets because their other benefits matter. It does offer unusually broad, drawback-free value for Common, and outperforms Pursuit Screen on both normal and shielded acceleration while avoiding its arc penalty.

Availability reinforces this: for the first slot of a fresh offer, each Common has approximately 45/19 = 2.37% selection probability versus 27/26 = 1.04% for each Uncommon. Nozzles is therefore about 2.28 times as likely as an individual Uncommon in that slot. Subsequent slots exclude earlier selections, so these are not exact full-offer probabilities.

**Recommended trial:** retain Common, reduce to **+8% acceleration and +4% shield acceleration factor**, giving +12.32% effective shielded acceleration. This preserves its identity and keeps a useful movement option in Common. Moving the existing card to Uncommon is a reasonable alternative, but also makes Common mobility less accessible. Its description should distinguish the shield *factor* from the combined acceleration improvement.

## Highest-priority findings

| Priority | Card or family | Evidence | Recommended direction |
| --- | --- | --- | --- |
| High | Pursuit Screen — Uncommon | Same +18% shield acceleration factor as Plasma Thrusters, but trades away arc instead of gaining speed. Shielded Drive provides a larger factor bonus and lower drain with no drawback. Nozzles also exceeds its shielded acceleration gain. | Retain the narrow-arc tradeoff and trial +30% shield acceleration factor. Reassess Mobile Bulwark alongside it so the Rare upgrade remains attractive. |
| High | Beam Emitter — Legendary | Its advertised +150% projectile speed is ineffective. `ProjectileState.create` forces every beam to 4,000 speed, ignoring `stats.projectile_speed`. It actually supplies beam unlock and only +5% damage; beam unlock also exists at Epic through Laser Repeater. | Resolve beam speed semantics before assigning power to this bonus. Prefer replacing the dead modifier with a meaningful beam benefit, then reassess tier. If making projectile speed affect beams instead, audit all beam/speed combinations. |
| High | Twin Shot — Epic | One copy gives 1.40× potential damage output. Same-tier Trident Array gives 1.95× before counting its pierce, at 14° rather than 10° spread. Needle Storm gives about 2.14× measured sustained output, faster projectiles, and only 8° spread. | Trial Twin Shot at Rare, retaining its simple two-shot identity. Spread geometry means these are potential-output comparisons, not guaranteed hit damage. |
| High | Multishot repeat picks | Projectile count clamps at six, but per-copy damage reductions continue. Extra copies can reduce output even before the cap because projectile count grows additively and damage penalties compound. | Inspect marginal output for each repeat pick and for mixed multishot builds. Redesign repeat scaling or clearly expose when a pick reduces potential output. Moving rarity does not solve this. |
| Medium | Storm of One — Mythical | On the base ship it raises burst DPS from 100 to 160, but cuts the magazine from eight to three. Measured sustained DPS falls from 61.67 to 60.00. It relies on magazine support to realize its advertised power. | Trial a −3 magazine penalty instead of −5, then compare both standalone and magazine-supported builds. Treat burst pressure as a real benefit rather than judging only sustained DPS. |
| Medium | Fortress Emitter — Epic | Gives 160 shield, 24 drain/s, and −10% speed: 6.67 seconds of no-hit shield hold. Uncommon Capacitor Bank gives 130 shield, 20 drain/s, and +10% regeneration: 6.50 seconds of hold with no speed penalty. Fortress retains more hit-buffer capacity, but pays heavily for it. | Trial Rare with current values, or retain Epic and replace one penalty with a useful defensive benefit. |
| Medium | Adaptive Chassis — Rare | Only +15% hull and +10% acceleration, without an unlock. Nearby Uncommon movement cards give +15–20% acceleration plus other benefits; Common Ablative Shell adds more hull on an otherwise base build (+20). Multiplicative hull becomes more valuable in larger builds. | Candidate for Uncommon; validate on both base and hull-stacked builds. |
| Medium | Combat Gyros and the braking family | The description promises tighter turns, but drag only applies while movement input is zero. Reversing or changing direction under input uses acceleration. This makes Nozzles especially attractive next to cards presented as handling upgrades. | Correct the handling descriptions first; measure stop-and-reposition use before changing braking values. |

Beam Emitter's dead modifier is an implementation fact, while the tier and tuning recommendations are design judgments. Beam conversion itself is substantial: base lifetime becomes 0.18 seconds and actual nominal travel distance is 720, versus 2,250 for the base projectile. Faster delivery and shorter reach both matter; a beam unlock should not be valued as an unconditional DPS multiplier.

## Repeat-pick evidence

Potential sustained DPS over 120 seconds, always firing, with all pellets assumed to hit:

| Build | 1 copy | 3 copies | 5 copies |
| --- | ---: | ---: | ---: |
| Base, no cards | 61.67 | — | — |
| Twin Shot | 86.33 | 84.61 | 62.19 |
| Scatter Array | 122.84 | 107.25 | 45.81 |
| Trident Array | 120.25 | 101.61 | 42.93 |
| Needle Storm | 132.18 | 134.42 | 66.88 |
| Hot Load | 68.54 | 67.71 | 46.88 |
| Rapid Cycling | 70.00 | 86.67 | 100.00 |
| Endless Belt | 76.67 | 86.67 | 90.62 |

Scatter Array and Trident Array are below base potential output at five copies even before accounting for spread. Pierce can still provide multi-target value; other builds can offset damage penalties. Hot Load has a similar magazine-penalty problem: its burst identity remains, but repeated picks make continuous fire worse. This argues for contextual pick evaluation, not a blanket nerf to multishot or fire-rate cards.

[`StatSystem.has_effective_benefit`](../../src/shared/cards/stat_system.gd) checks whether *any* stat improves. It does not establish that the complete pick is useful. At review time NPC utility omitted shielded acceleration, shield drain, shield arc, and beam speed override. The scoring follow-up below addresses those omissions, but scores should still not be treated as balance measurements.

Other candidates for a later pass include Omnidirectional Field (one copy already reaches the 360° arc cap; further copies only reduce capacity) and conditional cards such as Tight Bore and Damage Control. Tight Bore provides no immediate effect on the zero-spread base weapon; Damage Control requires auto-repair. These can have legitimate build roles, but should be evaluated as conditional offers.

## Proposed first balance pass and validation

Start with the Nozzles reduction, a Pursuit Screen buff, and Twin Shot at Rare. Resolve Beam Emitter's dead modifier and misleading braking language as mechanical/description issues. Treat multishot repeat scaling as a separate design decision, then revisit Storm of One, Fortress Emitter, and Adaptive Chassis with their intended roles in mind. Avoid a global rarity reshuffle based solely on these measurements.

Playtest paired drafts at equal pick counts, rotating players and sides. Include base builds, three repeats, and mixed shield/mobility or magazine/multishot builds. Compare duel survival and hit rate, objective travel and possession, shielded repositioning, and how often each card is selected over same-tier alternatives. Keep game mode separate: mobility that is merely comfortable in a duel can be decisive in flag play. Stronger evidence would come from repeated paired matches and pick/win data adjusted for player skill, mode, and prior build.

At review time, the older [rarity audit](../CARD_RARITY_AUDIT.md) reported 135 cards with different tier counts and said Nanite Reservoir moved to Legendary, while the resource was Epic. These documentation discrepancies are corrected in the first pass below. Unit assertions pin some rarities and exact Nozzles values; they validate the chosen tuning, not whether that tuning is balanced.

## First pass applied

- Vectored Nozzles stays Common with +8% acceleration and +4% shield thrust factor, combining to +12.32% shielded acceleration per copy before clamps. Its description now explains the combined benefit.
- Pursuit Screen stays Uncommon with +30% shielded acceleration and the existing −10% shield arc tradeoff.
- Twin Shot moves from Epic to Rare with its mechanics unchanged.
- Beam Emitter stays Legendary and replaces +150% projectile speed with +50% projectile lifetime. It retains +5% damage. One copy now produces 1,080 units of beam travel; three copies produce 2,430, at the existing 4,000 beam speed. This gives it a range role distinct from the other beam cards and works when another card already supplies beam conversion.
- Braking descriptions specify passive braking; detailed tooltips explain that it acts after movement input is released. Combat Gyros no longer promises tighter powered turns.

Mobile Bulwark remains Rare at +35% shield thrust and +15% drain: unlike Pursuit Screen it preserves full shield arc. The current rarity audit has been synchronized, including Nanite Reservoir's actual Epic tier. Multishot repeat scaling and the medium-priority tuning candidates were deferred to the second pass below.

The regression suite now checks actual shielded movement, passive stopping versus powered reversal, and created beam projectiles at one and three copies, both standalone and alongside Laser Repeater. Only the nine stat-baseline hashes for the three numerically changed cards are refreshed; other card derivations retain their previous baselines.

Validation: `tools/run-tests.ps1` completed with **7,541 assertions passed, zero failed**, including existing card layout checks. The post-pass snapshot completed all **408 samples across 136 cards** and confirmed the updated tier counts, 758.16 shielded acceleration for one Nozzles copy, 877.5 for Pursuit Screen, and Beam Emitter's 1,080/2,430 travel distances at one/three copies. Human match playtesting remains the next evidence needed for tuning confidence.

## Second pass applied

The four remaining findings now have the following implementations:

| Finding | Applied change | Verification |
| --- | --- | --- |
| Multishot repeat picks | Show lower potential DPS on the offer, in graphical/accessibility details, and at confirmation. | Third Twin Shot is caught before any stat hits a limit. Repeated Twin Shot, Scatter Array, Micro Barrage, Needle Storm, and Trident Array are checked with damage support; a mixed multishot build is also checked. A useful second Twin Shot clears the warning. |
| Storm of One | Magazine penalty reduced from −5 to −3; remains Mythical. | One copy retains five shots and measures 80 sustained DPS, versus 60 before the change and 61.67 base. Actual firing checks verify an improvement both standalone and with Extended Magazine. |
| Fortress Emitter | Moved to Rare with its +60 shield capacity, +20% drain, and −10% speed intact. | Catalog tier, capacity, and both drawbacks checked. |
| Adaptive Chassis | Moved to Uncommon with +15% hull and +10% acceleration intact. | Derived on base and three-Ablative-Shell builds: hull becomes 115 and 184 respectively, preserving multiplicative scaling. |

For multishot, this implements the review's **explicit-preview option**, rather than changing per-copy scaling. A lower-output pick can still offer piercing, coverage, or other benefits, and remains selectable. Manual and automatic draft eligibility rules are unchanged. This is a mitigation for hidden losses; it does not make every repeated card stronger than the preceding build.

Potential burst DPS equals volley damage times fire rate. Potential sustained DPS uses a full repeating magazine cycle: `(magazine − 1) / fire rate + max(reload time, 1 / fire rate)`. The last shot's cooldown overlaps reload, matching `WeaponState`. The preview assumes every projectile hits one target and excludes physics-tick rounding, accuracy, range, multi-target hits, and special abilities. Details state these assumptions. The compact face prioritizes a sustained-output warning if both measures fall; both remain in details. Warning text uses the existing note space so it does not crowd the rarity footer, and confirmation text can wrap.

The current catalog has 19 Common, 27 Uncommon, 31 Rare, 20 Epic, 18 Legendary, 12 Mythical, and 9 Unobtanium cards. All tier offer weights are unchanged. The dated JSON remains pre-pass evidence; rerunning its script measures the current catalog separately.

Second-pass validation: **7,577 assertions passed, zero failed** through `tools/run-tests.ps1`, including visible output warnings, confirmation, warning reset on reused offers, actual firing comparisons, and all existing layout checks. The snapshot completed **136 cards / 408 samples**. A targeted layout check verified that the compact `DPS -30.0%` note keeps capped Twin Shot's pending selection above its rarity footer. Potential DPS remains a model for informed drafting, not measured match win rate.

## NPC scoring follow-up

NPCs now evaluate the complete derived build using these additional combat effects:

- Shielded acceleration uses acceleration times the shield thrust factor. Passive braking receives a small separate contribution. Top speed remains the dominant mobility term.
- Shield value combines capacity per block cost, capacity per continuous drain, recovery time after depletion, and regeneration. Arc coverage scales that value; narrower coverage is a real cost. Square roots give diminishing returns to shield efficiency and coverage.
- Weapon output uses the same steady-state reload/cooldown model as the draft preview, including the overlapping cooldown on the last shot.
- Projectile reach and delivery speed come from actual `ProjectileState.create` results. Fixed-speed beams receive no benefit from unused projectile-speed stats, and lifetime modifiers affect their actual shortened lifetime and reach. Faster delivery gets a separate modest score from longer reach.

Existing role priorities remain: flag runners emphasize mobility, hill defenders emphasize survival, and other combat roles retain more offense weight. New ability unlock credit remains one-time. The scorer computes the current build's utility once per choice set and compares each offered pick against it.

This changes NPC preferences only. The offer pool, manual choices, and existing NPC/timeout candidate rules are unchanged. When passed an all-negative choice set, the policy still selects the highest-scoring offered card; it does not invent a replacement or skip the draft.

Regression scenarios cover working shield benefits versus duds, positive and negative shield changes for all four roles, speed versus lifetime picks before and after beam conversion, capped coverage, pre-cap multishot output loss, and all-negative offers. The whole 136-card pool is scored at one, three, and twenty copies for all four roles to check finite results.

These are deterministic comparative heuristics. Coverage is not an observed hit probability, capacity/block cost is not an exact block count, and the weapon estimate does not simulate aim, spread, multi-target hits, or active-ability use. The new weights still need match playtesting; this is not proof that NPC drafting is optimal or that card rarity is fully balanced.

NPC follow-up validation: the isolated NPC objective/draft suite passed **1,762 assertions with zero failures**, including existing route/role/holding tests. The full shared-workspace suite reported **9,278 passed and two failed**: both failures concerned the concurrently changed Cloak description (length and missing `Per stack:` text), outside this scoring change. No offer filtering or changes to that concurrent Cloak work were made.

## Focused investigation follow-up

The [focused six-card investigation](CARD_BALANCE_FOCUSED_2026-09-07.md) adds broader peer comparisons, 2v2 fights, objective skirmishes, firing layouts and in-memory tuning trials. Its recommendations are now applied: Twin Shot is restored to Epic and Mobile Bulwark moves to Uncommon, while Adaptive Chassis, Pursuit Screen, Storm of One and Causality Cannon retain their current configurations. These two rarity changes preserve all numerical mechanics and tier offer weights. See that report for evidence, confidence and remaining human/late-build playtest limits.
