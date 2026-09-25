# Gameplay follow-up: shields and population scaling

This follows the comprehensive review's gameplay findings after its authority, feedback, presentation and network fixes. **No balance values were changed.** The automated study and coverage checks are complete; human LAN validation is a separate, unexecuted session described in the [playtest sheet](LAN-PLAYTEST-2026-09-04.md).

## Shield versus multishot

The new shield study runs 54 deterministic skilled-bot bouts: three comparisons, Core Arena / Prism Array / Solar Tide, three spawn cases and both side assignments. Bouts stop at 60 seconds; surviving pairs are censored draws. Spawn-case indices choose authored anchors, not independent human skill samples. Builds are prescribed; natural draft availability is not simulated here.

| Comparison | Left wins | Right wins | Draws | Median duration |
| --- | ---: | ---: | ---: | ---: |
| Base versus multishot | 0 | 16 | 2 | 8.76 s |
| Shield versus multishot | 0 | 16 | 2 | 10.50 s |
| Shield versus shield | 7 | 7 | 4 | 15.63 s |

The shield recipe is Capacitor Bank, Quick Charge and Wide Emitter; multishot is Twin Shot, Scatter Array and Rapid Cycling. The shield recipe produces 130 energy and a 160-degree arc, versus the base 100 energy and 120 degrees. It improves median survival in this sample but does not change the matchup's win count. The mirror's equal left/right wins help check side assignment; they do not establish population-wide balance.

Across the shield-versus-multishot bouts, the shield side recorded 164 blocks and 37 depletion events, spending about 14.9% of simulated time locked. The NPC policy stops firing while shielding and combines threat reaction with a periodic shield schedule. That policy, exact recipes and projectile spread constrain the inference. The result supports a human counterplay experiment, not a general claim that shields are ineffective.

## Controlled impact checks

Forty-eight direct authoritative-hit fixtures compare base/upgraded shields, fresh/expired guard windows, one/three/five simultaneous projectiles and frontal/arc-boundary/outside-arc/rear bearings. They isolate energy and coverage; they do not simulate projectile travel, spread, human aim or network delay.

| Base shield, frontal volley | Fresh Perfect Guard | Ordinary held shield |
| --- | --- | --- |
| 1 projectile | 5 energy, blocked | 25 energy, blocked |
| 3 projectiles | 55 energy, all blocked | 75 energy, all blocked |
| 5 projectiles | Depletes, all five blocked | Depletes after four, fifth reaches hull |

The depleting impact still blocks. The upgraded recipe blocks all five frontal impacts without depletion: 99.75 energy with a fresh guard, 118.75 otherwise. The exact arc boundary blocks; one degree outside it and rear attacks bypass defense. This preserves directional counterplay and confirms that a guard discount belongs to the first pellet, not the entire volley.

## Population study

The run completed **45 cases / 135 heats**, spanning all five modes, 2/8/32 pilots and seeds 7100–7102. Each table row covers nine heats. Depending on the group, natural rotation exercised two to four maps: Dead Freight, Solar Tide, Prism Array and Longwave Array. This is not ten-map coverage.

| Mode | Pilots | Median heat | Median first contact | Timeouts | Longest eliminated wait |
| --- | ---: | ---: | ---: | ---: | ---: |
| Death Match | 2 | 16.48 s | 6.35 s | 0/9 | 0.00 s |
| Death Match | 8 | 29.00 s | 0.93 s | 0/9 | 77.45 s |
| Death Match | 32 | 32.22 s | 0.13 s | 0/9 | 69.62 s |
| Team Death Match | 2 | 14.93 s | 4.52 s | 0/9 | 0.00 s |
| Team Death Match | 8 | 16.55 s | 2.73 s | 0/9 | 16.27 s |
| Team Death Match | 32 | 25.20 s | 0.68 s | 0/9 | 32.32 s |
| King of the Hill | 2 | 34.87 s | 4.80 s | 0/9 | — |
| King of the Hill | 8 | 105.00 s | 1.68 s | 9/9 | — |
| King of the Hill | 32 | 105.00 s | 0.13 s | 9/9 | — |
| Capture the Flag | 2 | 9.08 s | 3.86 s | 0/9 | — |
| Capture the Flag | 8 | 15.10 s | 1.57 s | 0/9 | — |
| Capture the Flag | 32 | 53.88 s | 0.12 s | 3/9 | — |
| Team Capture the Flag | 2 | 6.98 s | 3.57 s | 0/9 | — |
| Team Capture the Flag | 8 | 7.15 s | 2.65 s | 0/9 | — |
| Team Capture the Flag | 32 | 7.63 s | 0.32 s | 0/9 | — |

Timeouts use the authoritative transition flag, not a duration heuristic. First-contact medians omit heats with no recorded contact; raw sample counts are retained. Eliminated waits include only DM/TDM, where one death causes a continuous wait until the heat ends. Zero in a duel means the heat ended with the elimination, not that post-heat turnaround disappears.

The strongest pacing signal is unchanged: all 18 crowded hill heats timed out, while all nine duels completed before the cap. The expanded sample also found substantially longer DM waits than the original single-seed study. Large-lobby contact remains almost immediate. Solo CTF timed out in three of nine 32-pilot heats; team CTF completed quickly in this bot sample. Treat the very short team-flag heats as a route/contest playtest question, not automatic evidence of a good mode.

## Decisions

1. Keep current shield rules as the baseline for the prepared human duel/volley sessions. If matched human builds reproduce the multishot disadvantage despite correct timing and aim, compare a bounded volley-level guard benefit against the current first-pellet discount. Recheck single-shot weapons, rear attacks and depletion; do not buff every shield parameter at once.
2. Prioritize population-specific objective pacing experiments when repeated timeouts persist across maps. Compare one parameter at a time and preserve duel results as a regression check.
3. Measure human inactivity and spawn pressure before choosing shorter elimination heats, respawn presets or population-aware maps/spawns. Bot first-contact times are not reaction-time measurements.

## Reproduction and limits

Run `tools/measure-gameplay.ps1 -Section shield -Seeds 3 -OutputPath reports/gameplay-followup/shield.json` and the same command with `-Section pacing` / `pacing.json`. Then run `python tools/summarize-gameplay-followup.py --shield reports/gameplay-followup/shield.json --pacing reports/gameplay-followup/pacing.json --output reports/gameplay-followup/summary.json`. The summarizer checks the seed/map/side matrix, all 45 pacing cases, three completed heats per case and explicit timeout classification.

The ordinary unit suite passed **6,322 assertions**, including independent ability edges as well as a simultaneous shield/cloak edge. Gameplay wrappers reject unexpected engine errors. Current protocol is 34; packet version is 14. There was no physical LAN session, controller hardware trial, audio listening test, full-frame performance acceptance or human draft-decision measurement. The bot studies must not be presented as those results.


Retained evidence: [shield bouts and impact rows](gameplay-evidence-2026-09-04/shield.json), [all pacing heats](gameplay-evidence-2026-09-04/pacing.json), [coverage and grouped summaries](gameplay-evidence-2026-09-04/summary.json), and [verification record](gameplay-evidence-2026-09-04/validation.txt). Failed exploratory runs from earlier investigations remain preserved; they are not replaced by this report.
