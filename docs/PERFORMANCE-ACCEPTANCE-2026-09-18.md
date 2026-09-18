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
