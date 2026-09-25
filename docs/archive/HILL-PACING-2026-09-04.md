# King of the Hill pacing — 2026-09-04

Heats starting with **8 or more participating pilots now allow 30 seconds of overtime**, making the default active-heat limit **75 seconds instead of 105**. Smaller hill heats and other modes retain their existing limit. The host's configured overtime start still applies: for example, a 90-second start gives a crowded hill heat a 120-second limit.

This is a bounded pacing improvement for the [comprehensive review's population findings](COMPREHENSIVE-REVIEW-2026-09-04.md). Crowded heats still frequently settle through the existing highest-control-time result. It does not establish that the hill's contest/scoring balance is solved.

## Evidence and choice

The study uses the production coordinator, combat, automatic NPC draft, normal hill powerups, respawns and scoring. It pins the opening map to Core Arena, Dead Freight or Solar Tide and runs seeds 7100–7102 at 2, 8 and 32 skilled NPCs. Each case measures one opening heat, giving 27 paired cases before and after. These are fixed-tick simulations, not measurements of rendered FPS, internet performance or human decision time.

| Pilots | Cases | Median active heat, before → after | Time-limit results, before → after | Mean accumulated dead time per pilot per heat, before → after |
| --- | ---: | ---: | ---: | ---: |
| 2 | 9 | 32.23 s → 32.23 s | 0 → 0 | 6.41 s → 6.41 s |
| 8 | 9 | 105 s → 75 s | 9 → 9 | 42.96 s → 28.38 s |
| 32 | 9 | 105 s → 75 s | 9 → 9 | 48.18 s → 31.96 s |

Every retained field in the nine duel cases matched the baseline. All 27 production rows matched the earlier shorter-overtime trial exactly. No heat was incomplete or drawn. Dead time is summed across repeated deaths within a heat; these numbers do not represent single uninterrupted waits. The shorter cap necessarily removes some late combat opportunity as well as waiting time.

The baseline hill was contested for a mean 69.8% of active time at eight pilots and 82.6% at 32. The highest accumulated control time in each crowded case ranged from 3.83–7.67 seconds at eight pilots and 1.08–2.88 seconds at 32, far below the 20-second objective. Duels completed naturally in every case. Eight is the lowest population with the consistently stalled result in this sample; this is not a claim that it is an optimal threshold for all parties.

Two smaller experiments, using seed 7100 on all three maps and populations, were rejected:

- Lowering the target to 10 seconds at eight pilots and 5 seconds at 32 still left all six crowded cases at 105 seconds.
- Increasing respawns to 8 and 12 seconds respectively also left all six crowded cases at 105 seconds. Average dead-time fractions rose from about 41%/45% to 51%/66% in those paired samples.

The selected change preserves the 20-second uncontested-control objective, five-second respawns, hill radius, shield behavior and existing timed-result rules. It reduces a long contested ending without making the control target tiny or extending respawn waits. Further scoring or population tuning should include longer matches, additional maps, intermediate populations and human play. Spawn pressure and elimination-mode spectator downtime remain separate follow-ups.

## Authority and validation

The coordinator selects and freezes the overtime allowance when preparing each heat, using participating pilots rather than server capacity or currently living ships. Deaths and disconnects cannot extend an announced limit. Each later heat recalculates from its own participants. Existing `heat_end_tick` publication supplies the same deadline to LAN and internet clients and their overtime HUD; no new wire field is required. The mode description and player manual explain the rule.

**7,398 assertions passed**, including 69 new assertions covering all five modes at 2/7/8/32 pilots, active-state deadline publication, host overtime configuration, disconnect/death stability, later-heat recalculation, exact deadline resolution, a dead control-time leader and objective completion taking precedence on the deadline. The real ENet match-loop check passed private picks, timeout picks, two full matches, reset, rematch and shutdown. Editor import and shipping resource allowlist checks passed. The repository's exact Windows certificate-store diagnostic was the only allowed environment error.

## Reproduction and raw data

Use `tools/measure-hill-pacing.ps1 -Profile legacy-limit -OutputPath reports/hill-before.json` for the old 60-second overtime rule and `-Profile production -OutputPath reports/hill-after.json` for the current rule. Both default to three seeds. `short-target`, `slow-respawn` and `crowded-limit` are isolated test-only profiles; the first two preserve the old heat limit for comparison. They are excluded from shipping resource allowlists.

[Raw evidence](hill-pacing-evidence-2026-09-04) retains the [baseline](hill-pacing-evidence-2026-09-04/baseline.json), [production result](hill-pacing-evidence-2026-09-04/production.json), [summary](hill-pacing-evidence-2026-09-04/summary.json), both rejected experiments and the successful trial. The baseline's original `profile: production` means production at source commit `434f8d6`, before this change; `legacy-limit` reproduces that deadline policy on the current source.

An initial respawn experiment incorrectly extended already pending deadlines again. Its nine rows are retained as `discarded-respawn-prototype.json` for transparency and are **invalid, excluded from every comparison above**. The corrected experiment only adjusts newly scheduled deaths; `longer-respawn.json` contains those corrected results.
