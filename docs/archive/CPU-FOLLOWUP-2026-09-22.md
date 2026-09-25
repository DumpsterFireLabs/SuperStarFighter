# Mixed-workload CPU follow-up

The projectile threat index now rebuilds on its first query after motion or
membership changes. Previously the world built it at the end of every active
tick, including ticks without an NPC decision; spawning before the next query
could invalidate that work. Cell membership and maximum speed still refresh
together. Callers no longer need to predict whether threats will be queried.

The five-mode matrix now reports input, NPC, world, coordination and replication
CPU percentiles. `python tools/verify-architecture-matrix.py --profile` adds
projectile collision attribution, with additional profiling overhead.

Sequential before/after measurements on this host (480 measured ticks per case):

| Mode / map | Before p95 ms | After p95 ms | Ticks >16.667 ms, before → after |
| --- | ---: | ---: | ---: |
| Death Match / core_arena | 16.309 | 15.158 | 18 → 2 |
| Team Death Match / dead_freight | 15.174 | 14.595 | 6 → 3 |
| King of the Hill / twin_suns | 15.819 | 14.297 | 11 → 1 |
| Capture the Flag / switchyard | 14.870 | 13.916 | 5 → 3 |
| Team Capture the Flag / prism_array | 16.526 | 15.055 | 24 → 6 |

These are CPU execution samples, independent of the host's display cap. The
fixed seed, builds, population and refill workload are unchanged. Draft slicing
uses wall time, so preparation can take one extra tick and shift later combat;
these are comparative runs, not bit-identical five-mode replay traces. The six
frozen combat traces pass unchanged. Before/after phase data and scope are in
`cpu-followup-evidence-2026-09-22.json`.

Validation: all five functional cases passed; 14,661 working-tree assertions
passed, including motion without membership changes, inter-query spawn/removal,
speed bounds and existing deterministic combat traces. The working tree also
contains the owner's unrelated changes; those are excluded from this commit.

Limits: peaks still reach 21.757 ms; countdown/result work remains synchronous.
This is an improvement, not zero-overrun 60 Hz certification. Detailed profiling
continues to identify projectile collision/movement work and replication bursts
as further targets. No balance, simulation ordering or network protocol change.
