Performance review acceptance — 18 September 2026

Finding 1 — projectile encoding

Pre-sized native writes preserve the protocol layout and original chunk planner. A frozen reference encoder checks all counts 0–1,024 for delta, partial and full correction packets, mixed flags, reflected ownership, clamping, signed velocities, and zero/wrapped sequences. The full suite passed 13,609 assertions, including existing correction/delta interleaving tests. All eight real ENet fault profiles passed (baseline, latency, loss, reorder, blackout, combined, tail loss, limited bandwidth).

The serial review probe completed with `PERF_REVIEW_VALID=true`. Production encoding of 1,024 records averaged 1.811 ms (p95 1.932 ms), versus the original review's 4.762 ms mean. The combined world/scheduler repeat measured recovery mean 14.965 ms and max 17.033 ms across six recovery ticks; overall p95 13.909 ms, max 19.582 ms, four of 360 ticks over 16.667 ms. This reduces the periodic cost but does not establish a complete server budget. Finding 5 adds production composition and explicit recovery-tail reporting.

Local raw logs: `.tools/perf-finding1-tests.log`, `.tools/perf-finding1-enet.log`, `.tools/perf-post-probe.log`. Measurements use the review's machine and engine; no frame or physics rate was changed.
