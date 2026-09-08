# Card Rarity Audit

## Current balance pass — 7 September 2026

The catalog contains **136 cards**: 19 Common, 28 Uncommon, 29 Rare, 21 Epic, 18 Legendary, 12 Mythical, and 9 Unobtanium. Tier offer weights remain 45%, 27%, 15%, 8%, 3.3%, 1.2%, and 0.5% respectively. The sections below preserve earlier audits; this inventory supersedes their counts.

| Card | Applied change | Reason |
| --- | --- | --- |
| Vectored Nozzles | Common; acceleration +12% → +8%, shield thrust factor +8% → +4% | Reduces combined shielded acceleration from +20.96% to +12.32% per copy. |
| Pursuit Screen | Uncommon; shielded acceleration +18% → +30%, retaining −10% shield arc | Makes its coverage tradeoff worthwhile beside Shielded Drive and Plasma Thrusters. |
| Twin Shot | Restored to Epic after the initial Rare demotion; stats unchanged | Broader combat tests show strong Rare-peer dominance, including separate shield pressure from each pellet. |
| Mobile Bulwark | Rare → Uncommon; stats unchanged | Its shielded acceleration and drain tradeoff fit the tested Uncommon peers better. |
| Beam Emitter | Legendary; replaces ineffective +150% speed with +50% projectile lifetime, retaining +5% damage | Actual beam reach grows from 720 to 1,080 units on the base build. |
| Storm of One | Mythical; magazine penalty −5 → −3 per copy | One-copy sustained output rises from 60 to 80 DPS in the 120-second firing check, versus 61.67 base. |
| Fortress Emitter | Epic → Rare; stats unchanged | Its capacity benefit carries drain and speed penalties that better fit Rare. |
| Adaptive Chassis | Rare → Uncommon; stats unchanged | Its modest hull and acceleration package fits Uncommon; hull scaling still rewards supported builds. |

Mobile Bulwark retains +35% shield thrust and +15% drain at Uncommon; Pursuit Screen retains +30% shield thrust and −10% arc. Braking card descriptions now specify passive braking, and their detailed tooltips explain that it applies when movement input is released.

See the [full review and first-pass notes](CARD_BALANCE_REVIEW_2026-09-07.md) and [focused investigation](CARD_BALANCE_FOCUSED_2026-09-07.md) for evidence, caveats, and remaining follow-ups.

Multishot repeat scaling uses the review's explicit-preview mitigation: offers, inspection details, and confirmation show when the complete pick lowers potential burst or sustained DPS. The calculation uses the whole capped build, including fire rate, magazine size, and reload timing. It catches losses before the projectile cap and in mixed multishot builds. The underlying per-copy penalties and manual availability are unchanged; this addresses hidden output loss, not every possible weak repeat pick.

## Historical 120-card audit

The 120-card catalog was reviewed as a whole after the offer-weight rebalance. The review compared each card's immediate combat impact, breadth, drawbacks, stack scaling, enabling behavior, and closest same-category alternatives. Rarity describes power and build-shaping potential; it does not require every higher-tier card to win a one-stat comparison.

## Audit result

| Card | Previous | Audited | Reason |
| --- | --- | --- | --- |
| Endless Belt | Common | Uncommon | A drawback-free +8 magazine increase is distinctly above the basic +4 magazine card. |
| Scatter Array | Uncommon | Epic | Three projectiles at ×0.62 damage and ×1.15 fire rate produces roughly ×2.14 raw volley throughput before spread, matching the Epic multishot family. |
| Ricochet Rounds | Epic | Rare | One ricochet and a modest projectile-speed bonus are useful but narrower than the build-defining Epic projectile packages. |
| Mobile Bulwark | Epic | Rare | Its strong shielded movement carries a continuous-drain drawback and lands between Shielded Drive and the Epic defensive packages. |
| Quantum Reconstruction | Mythical | Legendary | Auto-repair plus ×1.50 hull is powerful, but narrower than the stronger multi-system Mythical packages and comparable to Legendary repair builds. |

The other 115 cards retained their tiers. Transformations such as beam weapons and auto-repair were valued above their visible numeric modifiers because they unlock a new combat model. Large drawbacks were credited when comparing raw multipliers, while synergies that require another card were treated as conditional rather than guaranteed power.

## Catalog shape after audit

| Tier | Cards | Offer-slot weight |
| --- | ---: | ---: |
| Common | 20 | 45% |
| Uncommon | 25 | 27% |
| Rare | 26 | 15% |
| Epic | 18 | 8% |
| Legendary | 14 | 3.3% |
| Mythical | 10 | 1.2% |
| Unobtanium | 7 | 0.5% |

Tier selection happens before uniform selection within that tier, so tier population does not change the displayed offer-slot weight. A five-card offer now has about a 50.2% chance to contain at least one Epic-or-better card, a 22.6% chance for Legendary-or-better, and an 8.2% chance for Mythical-or-better.

## Shield-ram addendum

The later shield-ram expansion adds five mechanically distinct cards, one at every tier from Rare through Unobtanium. Kinetic Prow is the minimal Rare archetype unlock. Impact Capacitor adds defensive breadth at Epic; Breach Vector pairs collision damage with the speed needed to deliver it at Legendary; Sundering Aegis materially lowers the activation threshold at Mythical; and Worldbreaker Prow combines the largest hit with capacity and repeat-impact scaling at Unobtanium. The progression reflects both immediate damage and how reliably each card enables repeated melee attacks.

## Nanite Reservoir balance follow-up

Nanite Reservoir currently occupies Epic and has a stacking ×0.90 maximum-speed drawback. The earlier statement that it occupied Legendary did not match the current resource. Auto-repair plus flat hull remains a strong build-defining package, while the mobility tradeoff gives opponents a clearer way to pressure it.

The former 135-card inventory is superseded by the current counts above. Tier weights remain unchanged because selection rolls rarity before choosing uniformly within that tier.
