# LAN playtest: shields, readability and pacing

Status: **prepared, not executed**. Automated fixtures cannot supply human timing, recognition, comfort or enjoyment results. Use matching compatibility-version-34 builds. Record actual build IDs and hardware; repeat after any balance change.

## Session setup

Record host/client CPUs, GPUs, refresh rates, input devices, frame-time spikes, in-game RTT, wired/wireless connection, resolution, HUD scale and hold/toggle shield preference. Enable Competitive 16:9 for comparable views. Keep reduced effects as each player's chosen accessibility setting and record it. Do not mix novice and experienced results without labeling them.

Use two short familiarization heats before recording. Rotate hosting and starting positions where practical. Alternate who attacks first in shield exercises. Record natural map rotation and effective build stats from inspection; prescribed three-card recipes from the bot study are not assumed to be obtainable in normal drafting.

## Shield checks first

1. Each player completes the existing Perfect Guard tutorial, then repeats ten attempts. Record successful guards, attempts where they believed a block occurred but hull damage followed, and unclear cues. Observe the target and incoming lane at their chosen HUD scale.
2. Play paired human duels. Compare ordinary weapons with naturally acquired multishot; record projectile count, shield capacity, arc, impact cost and regeneration for each build. Keep matched builds when possible and label differences. Swap attacker/defender roles and repeat ten exchanges per condition.
3. During exchanges, try a quick tap, release/re-press, held defense, a frontal volley, an arc-edge attack and a rear attack. Classify misses from recordings as timing, arc, depletion, input delivery or unknown. Do not label every hull hit a network failure.
4. Ask each defender which hit triggered Perfect Guard, when depletion occurred and when shielding became available again. The five-shot base-shield fixture shows why this matters: a fresh guard can block the depleting fifth impact; an ordinary held shield permits the fifth hit through.

Record both perceived response and authoritative outcome. The current 250 ms guard window starts when authority processes the press, with immediate local prediction and no collision rewind. Do not infer physical input-to-photon latency from displayed RTT.

## Population and objective sessions

Run 2-player duels, an 8-pilot skirmish and a 32-pilot party case separately. Count humans and NPCs explicitly; a two-human/30-NPC case is not 32-human acceptance. Cover DM, TDM, hill and both flag modes over at least two map geometries per population. If player availability prevents a case, mark it unrun.

For each heat record first meaningful encounter, duration, objective completion versus timeout, longest eliminated wait, and whether the local ship/objective remained easy to locate. Keep the production observation rows alongside recordings. Record human draft decision time separately from automatic NPC draft timing.

After each block ask players to identify the threat that hit them and describe the objective route. Record incorrect explanations, obscured indicators and fatigue from repeated waiting. Compare enlarged HUD and reduced-effects settings on the same scene when a problem is reported.

## Per-block record

| Field | Observation |
| --- | --- |
| Build, host, participants and experience | |
| Mode, map, humans/NPCs, input/HUD settings | |
| Effective attacking and shielding stats | |
| Guard attempts / successes / unclear outcomes | |
| Suspected delivery failures and replay evidence | |
| First encounter / heat duration / longest wait | |
| Objective completed or timed out | |
| Threat or objective recognition mistakes | |
| Draft decision time and capped/unhelpful offers | |
| Player comments and recording timestamps | |

## Decisions after the session

- Any reproducible disagreement between a sampled shield transition and authority is a correctness investigation before balance tuning.
- If frontal multishot repeatedly defeats correctly timed, comparable shield builds, prototype a bounded volley-level guard benefit and compare it against the current first-pellet discount. Retain rear/arc counterplay and depletion locks; test impact on ordinary single shots too.
- If crowded hill games repeatedly time out, compare one change at a time: population-specific hold target, objective area, or respawn interval. Recheck duels before adopting a shared rule.
- If eliminated waits or immediate spawn pressure frustrate players, compare shorter elimination heats or a clearly labeled respawn preset, then investigate population-aware map/spawn selection.

These are experiment directions, not approved balance values. Preserve the current rules as the comparison baseline and attach actual player observations before choosing a change.
