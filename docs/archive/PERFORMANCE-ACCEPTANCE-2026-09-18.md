Performance review acceptance — 18 September 2026

Finding 1 — projectile encoding

Pre-sized native writes preserve the protocol layout and original chunk planner. A frozen reference encoder checks all counts 0–1,024 for delta, partial and full correction packets, mixed flags, reflected ownership, clamping, signed velocities, and zero/wrapped sequences. The full suite passed 13,609 assertions, including existing correction/delta interleaving tests. All eight real ENet fault profiles passed (baseline, latency, loss, reorder, blackout, combined, tail loss, limited bandwidth).

The serial review probe completed with `PERF_REVIEW_VALID=true`. Production encoding of 1,024 records averaged 1.811 ms (p95 1.932 ms), versus the original review's 4.762 ms mean. The combined world/scheduler repeat measured recovery mean 14.965 ms and max 17.033 ms across six recovery ticks; overall p95 13.909 ms, max 19.582 ms, four of 360 ticks over 16.667 ms. This reduces the periodic cost but does not establish a complete server budget. Finding 5 adds production composition and explicit recovery-tail reporting.

Local raw logs: `.tools/perf-finding1-tests.log`, `.tools/perf-finding1-enet.log`, `.tools/perf-post-probe.log`. Measurements use the review's machine and engine; no frame or physics rate was changed.

Finding 3 — projectile geometry references

Client sweeps prepare a cache once per presentation step, retain geometry by actual radius, and invalidate on map/hidden-cover changes or session reset. Cargo-enabled authoritative sweeps use the same reference owner; damage refreshes it immediately within the tick. Shared geometry keys now preserve the actual radius instead of rounding different radii to the same hundredth.

The full suite passed 13,849 assertions. Added exact hit-dictionary comparisons across every map, five radii (including two formerly aliased radii), repeated cover/door masks and resets, plus a two-projectile test proving that cargo destroyed by the first projectile is traversable by the second in the same tick. Existing prediction, recovery, ricochet and multi-impact tests pass. Local log: `.tools/perf-finding3-4-tests.log`.

Finding 4 — immutable match-state publication

Small field updates shallow-copy the root, detach/freeze replacement fields, and share existing immutable subtrees. Full replacement still detaches externally owned input. One publication emits one invalidation; objective version rejection and reset semantics are unchanged.

The 13,849-assertion suite includes retained observations, nested incoming dictionary/array aliases, replacement arrays, read-only nested containers, batched signal counts, rejected objective versions, full-state/objective ordering, build/prediction refresh and session reset. Tests assert the observation contract rather than object identity. Local log: `.tools/perf-finding3-4-tests.log`.

Finding 2 — ship pattern drawing

Cached local polygons now draw under a temporary canvas transform, restored before later hull details, shields and nameplates. `src/test/pattern_render_verifier.gd` renders the frozen legacy implementation and production implementation side by side at identical states, then alternates viewport ordering through a deterministic 240-frame angle replay.

All 16 capture sheets were pixel-identical (six patterns × four angles × both pilot roles × both contrast modes × normal/shield/cloak/effects). The effects/local/contrast capture was also visually inspected. Both viewports recorded 900 draw calls. Across 11,520 pattern callbacks per implementation, legacy mean/p95 was 23.28/64 µs and production was 17.45/43 µs (25% lower mean). These are instrumented callback timings, not a whole-game FPS claim. The full unit suite also passes.

Run: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy --resolution 1920x1080 --script res://src/test/pattern_render_verifier.gd`. Captures and machine-readable results are written to `.tools/performance-patterns/`; the tool exits nonzero on appearance differences beyond its small rasterization tolerance.
Finding 5 — performance coverage and timing scope

`tools/run-performance-benchmark.ps1` now runs the existing overload fixture without detailed profiling and a separate combined world/coordinator/event-drain/replication gate. `-IncludeAttribution` retains the detailed profiling run, explicitly labeled. Recovery ticks are detected from emitted packet kinds rather than assumed tick offsets; their p95/p99/max and counts over the physics budget are reported separately. Coverage requires 32 pilots, 1,024 projectiles before each step, six complete recoveries, and actual objective events. Defensive limits remain 20 ms p95, 24 ms p99, 30 ms max; recovery p95 has a separate 24 ms bound. `-StrictPhysicsBudget` additionally rejects any combined tick exceeding 60 Hz.

The final combined run measured 13.237 ms p95, 14.576 ms p99 and 15.094 ms maximum, with no over-budget ticks across 360 samples; all six full recoveries were below 16.667 ms. It exercised 24 coordinator events. An earlier run of this same gate had one over-budget tick (17.749 ms max). These are bounded fixture results, not a guarantee across all machines or match trajectories. The separate NPC overload and mixed-mine gates passed, including the explicitly profiled attribution run.

`tools/verify-frame-pacing.ps1 -ExpectedFps 58` now runs an empty-window control, deterministic dense ordnance/effect replay, and actual ClientMain plus ServerRuntime over ENet with a real audio driver. It prints direct control/workload comparisons. `-IncludeAttribution` retains the old instrumented world-view fixture separately. The misleading `over_16ms_percent` field is removed; all rendered reports use the supplied display cadence and include p99/max, late and severe counts.

The final production run used WASAPI with audio unmuted, reached 16 simultaneous SFX voices, and exercised lobby/draft/countdown/active/heat-result flow, 32 ships, 54 peak projectiles, 889 snapshots and 3,334 presentation events. Across 2,258 active frames, median/p95/p99 were 17.243/18.973/24.400 ms, with 6.47% late and 20 severe frames. Its paired empty-window control had p95 17.296 ms, 0.50% late and no severe frames. Other live runs varied (p95 17.467–19.640 ms); no release-wide FPS gain is claimed.

The dense replay renders all 1,024 mixed projectiles, 32 ships and 24 simultaneous mine effects, with fixed simulation steps and a fixed cosmetic animation clock. Its final-state checksum and 3,012 p95 draw calls reproduced across runs. The fixed-clock run measured 53.154 ms p95 and 59.610 ms maximum; all 600 frames exceeded the 58 FPS cadence. This newly exposed extreme presentation limit remains a follow-up profiling target. The rendered gates pass coverage/error checks, not frame-budget acceptance.

Reproduction (serial, without a competing benchmark):

```powershell
& tools/run-tests.ps1
& tools/run-performance-benchmark.ps1 -IncludeAttribution
& tools/verify-frame-pacing.ps1 -DurationSeconds 45 -ExpectedFps 58
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy --resolution 1920x1080 --script res://src/test/pattern_render_verifier.gd
```

[Retained machine-readable results](performance-acceptance-2026-09-18.json) include codec, pattern, combined-tick, control, production-audio and replay measurements. The final unit run passed 13,856 assertions, including tests showing how overall p95 misses periodic stalls while explicit recovery tails expose them. Local logs: `.tools/perf-final-tests.log`, `.tools/perf-new-gates.log`, `.tools/perf-combined-final.log`, `.tools/perf-frame-final.log`, `.tools/perf-dense-fixed-clock.log`. The known root-certificate-store warning occurred; accepted runs contained no other engine/script errors. No long soak, pure GPU/audio execution profile, newly packaged release, or native Linux/macOS run was performed.
