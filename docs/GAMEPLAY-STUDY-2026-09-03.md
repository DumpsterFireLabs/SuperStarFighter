# Gameplay study — September 3, 2026

This records exploratory evidence for R02, R06, and R07. The fixtures use the production world, draft manager, card catalog, NPC controller, and match coordinator. They measure the implemented bot policy; they do not estimate human win rates or prove that the game is balanced.

## Reproduce

```powershell
./tools/measure-gameplay.ps1 -Section balance -Seeds 10 -OutputPath reports/balance.json
./tools/measure-gameplay.ps1 -Section pacing -Seeds 2 -OutputPath reports/pacing.json
./tools/measure-gameplay.ps1 -Section fairness -Seeds 3 -OutputPath reports/fairness.json
```

Raw rows preserve builds, seed/spawn index, map, result, censoring, timings, and pickup/bye cohorts. Saved evidence for this batch is under ignored `reports/review-2026-09-03/batch6-{balance,pacing,fairness}.json` and matching logs. The script fails its wrapper on script errors or a missing completion marker. Real servers also emit bounded `heat_observation` summary and `heat_player_observation` cohort rows at each heat result. Logged builds over 16 card types explicitly set `build_log_truncated`; full builds remain in the bounded coordinator history and study JSON.

## Ordinary draft availability

For each recipe, 200 deterministic draft streams ran through eight rounds with five-card production offers and prescribed winner byes at rounds 3 and 6. Selection prioritized missing recipe cards, otherwise taking the first useful offered card. This measures opportunity under a target-aware policy, not how humans actually select. Each recipe contains three distinct single-stack cards; exact recipes are deliberately narrower than the many viable family combinations.

| Recipe | Exact cards | Complete by round 8 / 200 | Mean recipe cards acquired |
| --- | --- | --- | --- |
| burst | extended_magazine, heavy_rounds, twin_shot | 0 | 0.76 |
| cover | quick_loader, reinforced_hull, ricochet_rounds | 1 | 0.75 |
| mobility | afterburner, lightweight_frame, vector_jets | 1 | 0.89 |
| multishot | rapid_cycling, scatter_array, twin_shot | 0 | 0.49 |
| ram | capacitor_bank, phase_thrusters, ramming_shields | 1 | 0.65 |
| range | heavy_rounds, long_fuse_rounds, rangefinder | 5 | 0.91 |
| shield | capacitor_bank, quick_charge, wide_emitter | 0 | 0.86 |
| sustain | auto_repair, quick_loader, reinforced_hull | 2 | 0.79 |

These rare exact completions mean a three-card duel result cannot be treated as the frequency or balance impact of that matchup in a normal match.

## Prescribed archetype bouts

Each row contains 20 bouts: ten spawn arrangements with both builds exchanged across peer IDs and spawn sides. Both use Skilled AI. The initial measurement only swapped spawn sides and exposed an identity bias; that output was rejected. The final equal-build controls are symmetric. Each bout ends on death or at 60 seconds, without overtime. All draw counts below were retained as draws, including censored survivors; they are not awarded to whoever had more hull.

| Left build / right build | Map | Left wins | Right wins | Draws |
| --- | --- | --- | --- | --- |
| sustain / burst | core_arena | 3 | 16 | 1 |
| sustain / burst | prism_array | 4 | 15 | 1 |
| shield / multishot | core_arena | 0 | 15 | 5 |
| shield / multishot | prism_array | 0 | 18 | 2 |
| ram / mobility | core_arena | 11 | 4 | 5 |
| ram / mobility | prism_array | 8 | 9 | 3 |
| range / cover | core_arena | 7 | 13 | 0 |
| range / cover | prism_array | 1 | 16 | 3 |

Burst beats the sustain recipe in most of these bouts; multishot dominates the shield recipe. Ram varies by map, and the cover recipe beats the range recipe more often. These are useful targets for player testing, not evidence of optimal counterplay. Skilled AI does not intentionally bank ricochets off cover and its standard combat policy often avoids ram contact. Spawn indices repeat after 32; no independent-random-sample or confidence-interval claim is made.

**Decision:** retain current card values. Test shield timing/angle versus scatter and repair disengagement versus burst with players (R24) before choosing buffs or nerfs. Broad numeric tuning from rare, prescribed recipes and a fixed AI would be premature.

## Saturated stacking

The scan derives each of 136 cards alone at 1, 3, 10, and 100 stacks, then compares one additional stack. It reports every changed effective stat and the production benefit classifier; contextual stats still use that classifier's documented conventions.

| Existing stacks | Cards with no effective benefit from next stack | Such cards still changing stats |
| --- | --- | --- |
| 1 | 2 | 1 |
| 3 | 3 | 2 |
| 10 | 52 | 14 |
| 100 | 135 | 0 |

For example, a second Omnidirectional Field cannot expand an already full arc but lowers shield capacity from 75 to 56.25. A fourth Micro Barrage adds no effective upside while reducing damage/speed and widening spread. At ten stacks, 14 cards with no improving effective stat still incur changes such as lower health, slower projectiles, or greater shield drain. At 100, 135 cards are fully unchanged; Cloak still gains a charge.

**Decision:** retain explicit drawbacks, unlimited manual ownership, the no-benefit warning, and useful-only automatic choices. Silently freezing penalties would change card contracts and enable free stacking; this evidence does not justify it. The strengthened draft layout keeps the warning and confirmation visible.

## Controlled comeback and pickup comparisons

Each cell reports prior-leader wins / challenger wins / draws across 20 mirrored bouts. Both begin with the named recipe. Equal builds are the control. For the bye condition the challenger receives one Heavy Rounds while the leader skips. The permanent-pickup condition gives the leader one Capacitor Bank. The expired-temporary condition uses the production temporary-card add/clear behavior before the next heat. These are controlled inventory treatments, not a simulated claim that either side actually won an earlier heat.

| Starting family | Equal | Leader bye | Leader permanent pickup | Temporary pickup expired |
| --- | --- | --- | --- | --- |
| burst | 9/9/2 | 14/4/2 | 15/3/2 | 9/9/2 |
| shield | 7/7/6 | 11/5/4 | 7/7/6 | 7/7/6 |
| mobility | 9/9/2 | 9/8/3 | 12/6/2 | 9/9/2 |
| sustain | 9/9/2 | 13/5/2 | 13/5/2 | 9/9/2 |

Permanent extra shield capacity helps burst, mobility, and sustain in this fixture but not the shield recipe. The extra Heavy Rounds does not reliably help the challenger: card count is not effective power, because drawbacks and matchup behavior matter. Expired temporary pickups exactly reproduce the equal-build control.

Six natural eight-pilot death matches (three paired seeds, temporary/permanent pickups) each completed five heats. They yielded 240 player-heat observations with actual builds and byes. Only **one pickup was collected in each treatment**, by the same seeded pilot; the collector won that heat, then won **neither of the two later sampled heats** in the permanent treatment. Six player-heat observations per treatment had a prior draft bye; those pilots won two. These tiny, selected cohorts cannot establish snowballing or its absence, and survival time also increases collection opportunity.

**Decision:** keep permanent drops opt-in and use temporary drops in the quick presets. Retain full build and pickup cohort logs for longer player sessions. Neither automatic catch-up bonuses nor a universal pickup nerf is supported by these samples.

## Pacing

Thirty scenarios (two match seeds × five modes × three lobby sizes) each completed three heats, for 90 observed heats. Skilled NPCs draft immediately, so the observed draft duration is one server tick when a draft occurs; it must not be interpreted as human reading/decision time. Durations use simulation time at 60 Hz, not wall-clock test execution. All defaults, including overtime and result/countdown timers, are retained.

| Mode | Pilots | First contact median, s | Heat median, s | Eliminated mean / max per player-heat, s | Heat turnaround median, s | Round turnaround median, s |
| --- | --- | --- | --- | --- | --- | --- |
| Death Match | 2 | 6.97 | 18.65 | 0.00 / 0.00 | 5.00 | 7.02 |
| Death Match | 8 | 0.90 | 28.35 | 17.72 / 69.15 | 5.00 | 7.02 |
| Death Match | 32 | 0.11 | 41.97 | 35.70 / 70.02 | 5.00 | — |
| Team Death Match | 2 | 4.16 | 30.01 | 0.00 / 0.00 | 5.00 | 7.02 |
| Team Death Match | 8 | 2.74 | 17.74 | 6.35 / 46.47 | 5.00 | 7.02 |
| Team Death Match | 32 | 0.63 | 25.09 | 10.94 / 31.67 | 5.00 | 7.02 |
| King of the Hill | 2 | 4.05 | 36.66 | 6.89 / 17.32 | 5.00 | 7.02 |
| King of the Hill | 8 | 1.35 | 105.00 | 43.55 / 55.62 | 5.00 | — |
| King of the Hill | 32 | 0.09 | 105.00 | 48.52 / 57.67 | 5.00 | — |
| Capture the Flag | 2 | 3.86 | 7.85 | 0.00 / 0.00 | 6.01 | 7.02 |
| Capture the Flag | 8 | 1.54 | 9.57 | 2.90 / 14.18 | 5.00 | — |
| Capture the Flag | 32 | 0.12 | 23.94 | 17.41 / 46.87 | 5.00 | — |
| Team Capture the Flag | 2 | 3.37 | 5.48 | 0.00 / 0.00 | 6.01 | 7.02 |
| Team Capture the Flag | 8 | 2.48 | 6.59 | 0.51 / 5.00 | 5.00 | 7.02 |
| Team Capture the Flag | 32 | 0.59 | 11.20 | 2.34 / 10.00 | 6.01 | 7.02 |

Eliminated time is summed across lives in respawning modes. Heat turnaround includes result panels and the next countdown, plus a draft/round panel when applicable; round turnaround begins at the deciding heat's end. Dashes mean the three-heat sample never reached the next round, not zero delay. First contact counts real hull damage or shield blocks, excludes overtime damage, and stays null if absent.

The first Hill pass reached the 105-second time limit in every sampled heat. Investigation reproduced an objective NPC deadlock: close-contact logic suppressed fire while objective steering prevented separation. The fix preserves separation and combat while keeping arrived defenders near their objective; the table above is from the final rerun. Some dense Hill matches still reach the limit because scoring requires uncontested control. That is a pacing signal for human mode testing, not a reason to silently change the win condition.

**Decision:** recommend Duel/Skirmish for learning and small parties, the eight-seat team-objective preset for quick respawning rounds, and explicitly label 32-seat Chaos as crowded. Keep the 5-second normal inter-heat presentation/countdown, immediate all-ready draft completion, and existing global timers. Human draft time is still unknown. Avoid treating 32-player elimination spectating or a short two-seed flag fixture as a universal timer target.


## Scope of acceptance

This completes measurement and initial policy decisions for R02/R06/R07. Human comprehension, optimal counterplay, perceived fairness, WAN behavior, and release-hardware performance remain separate review items. No numeric card, scoring, or global phase-duration changes were made by this study.
