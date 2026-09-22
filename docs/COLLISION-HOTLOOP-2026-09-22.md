# Collision hot loop — 2026-09-22

The retained obstacle geometry now includes a small, immutable dense occupancy grid. Short sweeps inside an empty cell can return before constructing cell keys or extracting narrow-phase geometry. The grid is built for each exact radius and cargo-cover revision, so destroying cover mid-tick still changes subsequent collision queries immediately. World-edge handling, exact collision tests and tie ordering are unchanged.

Profiling identified obstacle and ship sweeps as substantial recurring costs. Finer ship cells and an adjacent-cell union cache were tested but rejected: the extra indexing work outweighed their benefit in an alternating comparison. Ship indexing and NPC threat traversal retain their original behavior. This commit adopts only the smaller obstacle-query improvement.

`python tools/benchmark-collision-queries.py --baseline 2ca9ead` reproduces the controlled comparison against the local pre-round commit. It alternates old/new implementations within one process, takes six samples after two warmups, and performs 16,384 fixed sweeps per sample. The unchanged ship query runs as a control. The recorded median obstacle-query batch fell from **42.581 ms to 39.507 ms (7.2%)**, with identical hit counts. The control varied by 2.4%.

The five-mode mixed simulation matrix also passed, but its tick timings vary with scheduling and other phases; this change does **not** establish a meaningful whole-tick speedup. It should not be described as 7% faster simulation or translated into FPS. Structured query and full-matrix measurements are retained in `collision-hotloop-evidence-2026-09-22.json`.

Correctness coverage compares every dense occupancy cell against the sparse geometry across maps, radii and cargo revisions. Existing exhaustive sweep tests, cargo destruction within a tick and six frozen combat traces remain the behavioral checks. No combat behavior or physics frequency is intentionally changed.

An isolated archive of the three commits passed **14,713 assertions**, including all six frozen traces. Release metadata and shipping allowlists are current, and all six Python harness tests passed.
