# R01–R08 implementation and validation

Implemented on `codex/review-r01-r08`, with one commit per finding. Validation uses the working tree, including the owner's existing changes; unrelated edits and staged asset removals are excluded from these commits. Private exports are verification artifacts, not a new beta release. Network peers must both use protocol **40**, binary packet version **17**.

| Finding | Change |
| --- | --- |
| R01 | Aligned release metadata with runtime; restored missing shipping resources; made the foundation gate check export policy. |
| R02 | Shared antialiased disc and mine-ring masks replace repeated circle tessellation. Weapon bodies, directional trails, team markers and danger radii remain. |
| R03 | Cold weapon audio returns a prepared fallback immediately. A single worker prepares private profile copies; main-thread publication updates the bounded LRU cache. Requests are deduplicated and capped at 96; teardown joins the worker. |
| R04 | Every received recovery chunk publishes its records immediately. Only complete assembly authorizes absence-based removal. Full recovery uses reliable delivery once per second; frequent movement corrections remain unreliable. |
| R05 | Public life epochs clear and reseed remote interpolation, including when the death snapshot is lost. Three legal charge counters are packed into 30 bits to make room for the epoch without increasing snapshot size. |
| R06 | Two remaining packed bits select a shared velocity exponent. Ordinary movement retains 1/8-unit precision; legal boost and knockback velocities no longer clip at 4,095 units/s. |
| R07 | Competitive team participants may spectate living visible allies. No available ally produces a waiting screen instead of an opponent/arena camera. Casual and neutral spectator policies remain explicit and unrestricted. |
| R08 | Derive each draft baseline once, share candidate stats with NPC scoring, and construct rarity groups once. Preserve first-remaining-card rarity order and RNG consumption. Release prepared stats when the draft resolves. |

## CPU evidence

This machine's sub-60-FPS restriction is not used as a performance verdict. The rendering figures measure CPU time inside drawing callbacks, excluding GPU execution, engine traversal and presentation wait.

| Probe | Before | After |
| --- | ---: | ---: |
| 1,024 mixed projectiles, drawing p95 | 17.892 ms | 8.505 ms |
| Combined ship/projectile/effect drawing p95 | 25.470 ms | 15.953 ms |
| Cold weapon lookup, 24 profiles/variants, p95 | 16.532 ms | 0.063 ms |
| 32-player human draft start, median of 8 | 67.682 ms | 36.803 ms |
| 32 NPC draft preparation and selection, 12-card builds with two stacks each, median of 8 | 113.115 ms | 45.353 ms |
| Remote respawn immediate position error | 2,236 pixels | 0 pixels |
| 6,000-unit/s knockback wire error | 1,905 units/s | 0 units/s |

The rendering replay measured 600 frames after 60 warmup frames, retained all 1,024 projectiles, and preserved final-state SHA-256 `a0d148c29c2bc069806415ef4cb50755b8eef7eafc1a04b85ce6caa127a33094`. A second optimized run agreed with the first (8.401 ms p95). The final rendered image was inspected. Cold audio timings now cover enqueue/fallback work; synthesis still costs CPU on the worker and custom timbre becomes available asynchronously.

## Validation

- Foundation verification passed all 216 checks, including import/parse/startup checks, 14,542 passing unit assertions, the intentional failing-test path and the engine-error gate. The two legacy audio assertions were updated for asynchronous preparation, and a synthetic correction fixture now supplies its required server tick.
- Strict CPU physics benchmark passed. The combined 32-player / 1,024-projectile fixture measured 13.092 ms p95 and 15.521 ms maximum across 360 measured ticks, with no tick over the 16.667 ms budget. Full recovery ticks peaked at 14.682 ms. This excludes RPC/socket transport and rendering and is not an achievable-FPS certification.
- Focused draft parity: 671 assertions, including offers, benefit filtering, three NPC roles, subsequent timeout RNG and cache release against the frozen pre-change draft reference.
- Focused network and respawn checks: 4,021 assertions passed after the wire changes. Public epochs wrap correctly, legal charge caps round-trip, and 32-player snapshots remain 1,193 bytes.
- Spectator policy: 25 assertions passed, including ally-only cycling, no-ally waiting screen, cloaked allies, casual sessions and neutral spectators.
- Dense recovery: 27 chunks for 1,024 entities; withholding one chunk still published 987 entities including a retained ghost. Repair restored exactly 1,024 live entities and removed the ghost.
- Real ENet impairment verification: all eight profiles passed (baseline, latency, loss, reordering/duplication, blackout, combined faults, tail loss, and limited bandwidth). This fixture exercises small combat scenes; the separate dense chunk test covers maximum-size recovery assembly.
- Windows client and dedicated-server exports built and passed embedded-resource audits. A test driver mounted the exported client package in the Godot runtime, instantiated its production client scene, and connected to the standalone exported server: 341 player snapshots and 18 full recoveries, protocol 40 / packets 17. Export templates do not execute the external `--script` driver directly.

## Practical limits

Draft preparation is substantially cheaper but still a synchronous transition, and its 32-player CPU cost exceeds one 60-Hz tick. Further scheduling work should use populated-build and NPC fixtures, not alter draft probability or skip benefit checks. The dense renderer still warrants GPU profiling on an unrestricted machine.

Reliable full recovery retains the existing bounded 1,024-record / 32,176-byte payload per recipient per second. Loss adds retransmission traffic; this is not a bandwidth reduction or an instantaneous-recovery guarantee during a blackout. The public life epoch is 16 bits; local prediction retains its full 32-bit generation. Velocity precision scales from 0.125 to 8 units/s across ranges, with a maximum component magnitude of 262,136 units/s.

Competitive spectating is a presentation policy, not anti-cheat: opponent data is still replicated. Organized matches should use trusted neutral spectators.
