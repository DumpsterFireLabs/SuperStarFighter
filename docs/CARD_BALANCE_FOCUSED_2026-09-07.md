# Focused card balance investigation — 2026-09-07

## Recommendations

The two recommended rarity changes are now **applied: Twin Shot is Epic and Mobile Bulwark is Uncommon**. Numerical mechanics are unchanged. Trial modifiers existed only in duplicated, in-memory catalogues. The results and raw catalogue signatures below preserve the pre-implementation study state.

| Card | Tier during study | Applied decision | Confidence and reason |
| --- | --- | --- | --- |
| Twin Shot | Rare | Restore **Epic**, retain current mechanics | Strong evidence of dominance over the tested Rare weapons; moderate confidence in Epic placement. Shield pressure survives a small damage nerf, and results against Epic peers are substantially less favorable. |
| Adaptive Chassis | Uncommon | Keep | Moderate. Good hull breakpoint, but does not dominate the broader mobility comparisons or objective skirmishes. |
| Pursuit Screen | Uncommon | Keep +30% shielded acceleration / -10% arc | Moderate. Competitive with other Uncommons, with a real coverage cost. |
| Mobile Bulwark | Rare | Move to **Uncommon**, retain current mechanics | Moderate. Its package is close to existing Uncommons; a +45% thrust trial did not establish a consistent improvement. |
| Storm of One | Mythical | Keep current -3 magazine version | Moderate. Weak standalone against the strongest tested weapons, competitive with support. The dependency is appropriate to the intended drafting design. |
| Causality Cannon | Mythical | Keep | Moderate for one-copy builds; low for repeated-copy balance. Powerful, but not a universal winner against Mythical peers. |

The Twin Shot recommendation revises the earlier demotion. The broader comparisons now include actual shield pressure and multiple peers rather than relying primarily on potential damage and repeat-pick penalties. Rarity changes affect availability, not an individual fight's mechanics; this study does not establish the resulting full-draft acquisition balance.

## Method and verification

Ran **888 duels, 96 two-versus-two elimination fights, 240 objective skirmishes, and 28 controlled firing layouts**. Of those, the initial focused study contained 576 duels and 168 objective skirmishes; the follow-up trials added 312 duels and 72 objective skirmishes. Repeated current-card scenarios from the earlier validation are corroboration, not independent new samples.

The combat runs use production world simulation and deterministic Skilled NPC pilots on Core Arena and Prism Array, with both peer/spawn assignments. Duels and objectives use three spawn configurations; teams use two. Duels and teams stop on elimination or at 60 seconds. Objective skirmishes use the production hill/flag handlers and correct map-specific objective positions, with one life and a 45-second cutoff. These are **not full matches with respawns, drafting, or pickups**. Team tests are elimination fights, not team objective matches.

Prescribed builds have equal pick counts. Each side receives one focal card, either alone or with a shared two-card support package:

| Group | Shared support |
| --- | --- |
| Twin Shot and weapon peers | Heavy Rounds + Extended Magazine |
| Adaptive Chassis and movement peers | Two Ablative Shells |
| Shield movement peers | Capacitor Bank + Efficient Field |
| Mythical weapons | Endless Belt + Extended Magazine |
| Mythical additional context | Twin Shot + Heavy Rounds |

When Heavy Rounds is itself the focal peer, it receives a second copy as support. Objectives use single-card builds. Teams use single and supported builds. The main study also records derived stats at one, three, and five copies; those are stat inspections, not repeated-copy match tests.

Both scripts completed with exit code zero. JSON checks verified recorded source hashes, matching catalogue signatures across studies, equal pick counts, valid outcomes and time bounds. No script/parse errors appeared. Godot emitted its existing root-certificate-store warning. After applying the two rarity changes and updating the existing rarity expectations, `tools/run-tests.ps1` passed **9,465 assertions with zero failures**. The catalogue inventory was verified as 19 Common, 28 Uncommon, 29 Rare, 21 Epic, 18 Legendary, 12 Mythical and 9 Unobtanium.

The mirrored configurations remain correlated and are not human win-rate estimates. Several movement matchups change substantially by side assignment. Conclusions below use consistency across contexts and mechanics, not statistical significance or an aggregate success threshold.

## Twin Shot

Current Twin Shot's duel record against five Rare peers was **103 wins / 13 losses / 4 draws**:

| Opponent | Twin wins / opponent wins / draws, single and supported combined |
| --- | ---: |
| Heavy Rounds | 20 / 3 / 1 |
| Siege Cannon | 21 / 1 / 2 |
| Rail Accelerant | 22 / 2 / 0 |
| Piercing Rounds | 22 / 1 / 1 |
| Sustained Barrage | 18 / 6 / 0 |

The advantage held on both maps (52/4/4 and 51/9/0) and both assignments (58/2/0 and 45/11/4). In 2v2, Twin teams finished 12/3/1 against Piercing Rounds and 13/3/0 against Heavy Rounds.

Two projectiles do more than raise close-range volley damage from 25 to 35. Normal shield impacts consume a fixed block cost per projectile, regardless of projectile damage. Both pellets can therefore spend shield energy separately. In the Heavy Rounds comparison, opponents suffered 38 shield breaks while Twin users suffered 11. Against Piercing Rounds the counts were 38 versus 13. These are observed totals, not a controlled attribution of every win to shielding.

The spread downside is real: a centered stationary target took 35 damage at 200 units, but zero at 600 units. A deliberately aligned two-target fan took 17.5 each. In a centered three-target column, Twin missed while Piercing Rounds dealt 27 to the first two targets. The pilots and fight geometry frequently favor Twin's strengths; humans can exploit its aiming gap.

An in-memory damage multiplier change from 0.70 to **0.65** reduced its Rare-peer record only to **102/14/4**. That lowers theoretical close-range damage but leaves pellet count and shield pressure intact. It is not persuasive evidence that a small damage cut solves the rarity issue.

Against five Epic peers, unchanged Twin finished **37/80/3**:

| Epic opponent | Twin wins / opponent wins / draws |
| --- | ---: |
| Micro Barrage | 14 / 9 / 1 |
| Needle Storm | 2 / 21 / 1 |
| Scatter Array | 3 / 21 / 0 |
| Trident Array | 6 / 18 / 0 |
| Laser Repeater | 12 / 11 / 1 |

Twin is competitive with some Epics and weak against others. **Restore Epic without changing its identity** is the least speculative correction supported here. This does not certify the entire Epic tier as balanced. Repeated Twin picks still lose efficiency; intentional bad build choices are not a reason to make the strong first copy commoner.

## Adaptive Chassis

At base hull, +15% health means 115 hull: five ordinary 25-damage hits instead of four. Its +10% acceleration also works with and without shielding. That is a useful first pick, but the broader results do not show universal superiority.

| Opponent | Adaptive wins / opponent wins, single and supported combined |
| --- | ---: |
| Overcharged Thrusters | 12 / 12 |
| Phase Thrusters | 18 / 6 |
| Vector Jets | 19 / 5 |
| Plasma Thrusters | 16 / 8 |
| Reinforced Hull, Common reference | 11 / 13 |

Against Overcharged Thrusters, Adaptive went 8/4 alone but 4/8 with shared hull support. Combined hill/flag results were 12/12 against both Plasma and Overcharged. Across all duel peers its record was 48/12 in one assignment and 28/32 in the other, another reason not to generalize the earlier Phase Thrusters result.

Three and five copies yield roughly 152 and 201 hull before additional hull cards. That scaling deserves ordinary late-build observation, but no demonstrated issue here justifies reversing the Uncommon placement. **Keep.**

## Pursuit Screen and Mobile Bulwark

At one copy on the base ship:

| Card | Shielded acceleration | Arc | Hold time without impacts |
| --- | ---: | ---: | ---: |
| Base | 675 | 120° | 5.00 s |
| Pursuit Screen | 877.5 | 108° | 5.00 s |
| Mobile Bulwark | 911.25 | 120° | 4.35 s |
| Shielded Drive | 810 | 120° | 5.43 s |

Mobile has only **3.85% more shielded acceleration than Pursuit**, restores 12 degrees of arc, and pays 15% higher continuous drain. Against Shielded Drive, its acceleration advantage is 12.5%, but its shield hold time is 20% shorter. These are distinct tradeoffs without a convincing Rare premium.

| Matchup | Duel left wins / right wins / draws | Hill + flag left wins / right wins / draws |
| --- | ---: | ---: |
| Pursuit / Mobile | 7 / 14 / 3 | 14 / 10 / 0 |
| Pursuit / Shielded | 9 / 14 / 1 | 13 / 10 / 1 |
| Pursuit / Plasma | 14 / 10 / 0 | 11 / 13 / 0 |
| Mobile / Shielded | 10 / 10 / 4 | 9 / 13 / 2 |
| Mobile / Plasma | 9 / 15 / 0 | 10 / 14 / 0 |

Mobile's advantage against Pursuit was concentrated in supported duels (9/2/1 from Mobile's perspective); the standalone result was 5/5/2. It has a useful niche, but not broad superiority over the Uncommon alternatives.

The in-memory **+45% shielded acceleration** trial, retaining +15% drain, produced a mixed 30/39/3 duel record across Pursuit, Shielded and Plasma. Against Pursuit specifically, its supported result fell to 5/6/1. The acceleration increase changes positioning and collisions; it is not a monotonic win-rate control. Objectives were also mixed, with no consistent improvement.

**Keep Pursuit; move unchanged Mobile to Uncommon.** Avoid another unvalidated stat buff simply to preserve Rare. At high stack counts, the shared thrust cap can remove benefits while drain/arc penalties continue; those intentional draft traps remain intact.

## Storm of One and Causality Cannon

The expanded Mythical comparisons show why Causality should not be treated as a mandatory benchmark that Storm must beat without support.

| Matchup | Single, left/right/draw | Magazine support | Multishot support |
| --- | ---: | ---: | ---: |
| Storm / Causality | 3 / 9 / 0 | 7 / 5 / 0 | 9 / 3 / 0 |
| Storm / Sunbeam Core | 1 / 11 / 0 | 8 / 4 / 0 | 4 / 7 / 1 |
| Storm / Horizon Round | 7 / 5 / 0 | 7 / 5 / 0 | 11 / 1 / 0 |
| Causality / Sunbeam Core | 3 / 8 / 1 | 3 / 8 / 1 | 1 / 11 / 0 |
| Causality / Horizon Round | 7 / 5 / 0 | 8 / 4 / 0 | 7 / 5 / 0 |

In 2v2, Storm versus Causality changed from **2/6** alone to **6/2** with magazine support. Storm versus Sunbeam remained unfavorable: 0/7/1 alone and 3/5 with support. Causality versus Sunbeam finished 6/9/1 overall; versus Horizon it finished 6/7/3.

Storm's one-copy ideal sustained output is 80 versus base 61.54; the corresponding Causality value is 123.08. Those figures exclude aim, shielding and multi-target value. Storm applies more frequent shield impacts, and support reduces its magazine limitation. The latest -3 magazine version has demonstrated viable supported matchups. **Keep its meaningful build dependency.** There is no reason here to guarantee beneficial offers or remove stacking penalties.

Causality is still a very strong raw package: 50 damage, 1,350 projectile speed and two additional pierces. In the controlled three-target column, one projectile dealt **150 total damage**, compared with Horizon's 75 and Sunbeam's 72.5. This establishes its multi-target benefit without pretending it is an average combat outcome. Shields terminate these ordinary piercing shots.

However, Causality did not dominate other Mythicals in either duel or team contexts. Its 22/14 duel edge over Horizon was especially assignment-sensitive (18/0 versus 4/14). Sunbeam's much faster beam delivery is a plausible contributor to its strong results; this harness does not isolate aim policy from weapon power. **Keep Causality for now.** Its three-copy 200-damage projectiles and five-copy damage cap of 600 remain a late-build watch item, not evidence from repeated-copy match tests.

Sunbeam Core emerged as the strongest additional comparator in these scenarios, including 31/3/2 against Horizon. It belongs in the next human weapon playtest, especially at different engagement ranges. That is a new watch item, not a demonstrated need for another immediate numerical change.

## Reproduction and evidence

- [Focused harness](card-balance-focused-2026-09-07.gd) and [raw focused results](card-balance-focused-2026-09-07.json).
- [In-memory trial harness](card-balance-trials-2026-09-07.gd) and [raw trial results](card-balance-trials-2026-09-07.json).
- [Earlier validation and its limitations](CARD_BALANCE_VALIDATION_2026-09-07.md).

From the repository root:

```powershell
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file .tools/card-focused.log --script docs/card-balance-focused-2026-09-07.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file .tools/card-balance-trials.log --script docs/card-balance-trials-2026-09-07.gd
```
