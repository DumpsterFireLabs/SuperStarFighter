# Card balance validation — 7 September 2026

The revised cards pass the automated suite. Controlled bot scenarios provide a watchlist, but do not justify another immediate balance patch. One real defect was found and fixed: NPCs led moving targets using nominal projectile speed even for fixed-speed beams. NPC aiming now shares `ProjectileState.travel_speed` with projectile creation. Regression tests check actual beam lead, invariance under ineffective speed modifiers, and the greater lead required for slower ordinary projectiles.

The current full suite passes **9,465 assertions, zero failures**. The earlier concurrent Cloak-description failures no longer occur. No card values or offer eligibility rules changed during this validation pass.

## What ran

- **384 controlled duel runs:** eight card pairings, one-copy and three-card supported builds, two maps, three spawn configurations, both peer/spawn assignments, and pre-balance versus current card values. Each revision has 192 runs. The common support package is Capacitor Bank plus Extended Magazine on both sides. Runs stop at death or 60 seconds; 18 of the 384 runs time out as draws.
- **96 current-card objective skirmishes:** four mobility/shield pairings, flag and hill modes, two maps, three spawn/objective configurations, and both assignments. These use production objective handlers and `GameModeRules.objective_spawn`. Runs have one life, no respawns or pickups, and a 45-second cutoff. One run times out. They are objective skirmishes, not complete match simulations.
- **48 forced two-card draft comparisons** across duel, hill, and flag roles, with and without the shared support build.
- **960 natural weighted draft samples:** 40 fixed seeds per mode, eight successive drafts, three modes, no byes. Each has five offers. Bots choose using production candidate and scoring rules. Every selection remained within the offer.
- **Six controlled beam-range checks:** one beam against a stationary target at 600, 900, and 1,200 units using old and current Beam Emitter values. Old beams hit only at 600; revised beams hit at 600 and 900; neither hits at 1,200.

Both pre-balance and current duel runs use the same corrected NPC aiming. Pre-balance values are reconstructed for the four numerically changed cards; earlier rarities are restored for Twin Shot, Fortress Emitter, and Adaptive Chassis. This isolates card changes from the aiming fix. Rarity itself cannot change the outcome of a prescribed-build duel.

An initial objective fixture used the geometric map center, which was blocked on Core Arena. Those results were discarded and replaced with runs using the game's actual objective placement. The saved evidence contains only the corrected objective samples.

## Duel results

Each entry is **first card wins / second card wins / draws**, combined across the single-card and supported-build contexts: 24 runs per revision and pairing.

| Pair | Before | Current | Interpretation |
| --- | --- | --- | --- |
| Vectored Nozzles / Lightweight Frame | 10 / 14 / 0 | 12 / 12 / 0 | No evidence of a consistent duel advantage for the revised Nozzles in this matchup. The apparent improvement despite a nerf illustrates sensitivity to bot trajectories. |
| Pursuit Screen / Shielded Drive | 9 / 12 / 3 | 11 / 13 / 0 | Competitive in these samples; no clear reason for another change. |
| Pursuit Screen / Mobile Bulwark | 9 / 13 / 2 | 13 / 8 / 3 | Watch the Uncommon/Rare boundary. Most of the swing occurs with support cards. |
| Twin Shot / Piercing Rounds | 19 / 3 / 2 | 19 / 3 / 2 | Strong head-to-head result for Twin Shot, but a one-target duel cannot fully value piercing. More Rare peers and multi-target play are needed before changing its tier again. |
| Beam Emitter / Prismatic Lance | 13 / 11 / 0 | 13 / 11 / 0 | These close-range bot duels do not expose the range improvement. Controlled range checks confirm the actual benefit. |
| Storm of One / Causality Cannon | 6 / 18 / 0 | 7 / 17 / 0 | Still weak in this particular Mythical matchup. Standalone improves from 0–12 to 3–9; supported goes from 6–6 to 4–8. The combined evidence is mixed, not a strong causal win-rate gain. |
| Fortress Emitter / Shield Siphon | 11 / 10 / 3 | 11 / 10 / 3 | Broadly competitive against this Rare peer. The support context favors Siphon more. |
| Adaptive Chassis / Phase Thrusters | 18 / 6 / 0 | 18 / 6 / 0 | Worth watching at Uncommon. The hull advantage is strong in these duels; compare more same-tier peers before drawing a general conclusion. |

Unchanged mechanics for the three rarity-only changes reproduce identical paired duel outcomes, as expected. These repetitions are not additional independent evidence about card strength.

## Objective results

Each entry is first card wins / second card wins / draws, with 12 runs per mode and pairing.

| Pair | Hill | Flag |
| --- | --- | --- |
| Vectored Nozzles / Lightweight Frame | 6 / 6 / 0 | 7 / 5 / 0 |
| Pursuit Screen / Shielded Drive | 7 / 5 / 0 | 6 / 5 / 1 |
| Pursuit Screen / Mobile Bulwark | 6 / 6 / 0 | 8 / 4 / 0 |
| Fortress Emitter / Shield Siphon | 6 / 6 / 0 | 5 / 7 / 0 |

Nozzles does not dominate its sampled Common peer. Pursuit Screen remains a watchlist item against Mobile Bulwark, especially in flag play. These one-life scenarios omit respawn pressure and team interactions; they cannot establish overall objective-mode balance.

## NPC drafting observations

Counts below combine three modes. The same offer seeds are reused across modes, so these are correlated observations. Picks/offers describes the NPC heuristic, not player preference or power.

| Card | Picked / offered |
| --- | ---: |
| Vectored Nozzles | 1 / 117 |
| Pursuit Screen | 0 / 51 |
| Mobile Bulwark | 4 / 30 |
| Twin Shot | 12 / 21 |
| Beam Emitter | 1 / 6 |
| Storm of One | 0 / 6 |
| Fortress Emitter | 0 / 27 |
| Adaptive Chassis | 34 / 60 |

The heuristic favors hull cards strongly, even though pairwise combat and objective results show some ignored mobility/shield cards are competitive. A zero pick count therefore does not justify buffing a card. Beam Emitter and Storm of One appeared only twice per mode, far too little to infer preference reliably. The forced pairs do show useful context: a hill defender prefers standalone Fortress Emitter over Shield Siphon, but prefers Siphon once the shared support package is present; beam builds correctly disregard speed-only bonuses in regression tests.

Do not add offer filters or guarantee improvements in response to these results. Dud and net-negative choices remain intentional. NPC utility weights may merit later calibration against broader match samples, but these results alone do not establish the correct new weights.

## Remaining evidence needed

Prioritize human or broader multi-bot playtests for Twin Shot against additional Rare peers, Adaptive Chassis against additional Uncommon peers, Pursuit Screen versus Mobile Bulwark in team objectives, and Storm of One across different supported builds. All runs here use deterministic Skilled pilots. Spawn configurations, side swaps, and pre/post replicas are correlated; prescribed builds ignore acquisition probabilities, byes, and player strategy. No human win rates or statistical significance are claimed.

## Reproduction and raw evidence

- [Combat and objective harness](card-balance-validation-2026-09-07.gd), [raw runs, source hashes, card signatures, and range checks](card-balance-validation-2026-09-07.json).
- [Draft sampler](npc-draft-sampling-2026-09-07.gd), [raw draft traces and counts](npc-draft-sampling-2026-09-07.json).

From the repository root:

```powershell
& .\tools\run-tests.ps1
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file .tools/card-balance-validation.log --script docs/card-balance-validation-2026-09-07.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file .tools/npc-draft-sampling.log --script docs/npc-draft-sampling-2026-09-07.gd
```
