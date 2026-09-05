# Reliable thrust transitions — 2026-09-04

The remaining correction traces included lost thrust releases: local prediction stopped accelerating while authority continued applying the last movement sample until its input timeout. Thrust start and stop now use the existing reliable action-input path. Held thrust, direction changes and aim retain ordinary unreliable sampling. Simultaneous movement, shield and ability edges share one frame; no new RPC or wire layout is introduced.

The authority's existing sequence checks reject a late start after a newer stop. Input blocking and death produce neutral movement, and heat/session resets clear the previous movement state. Shield press identity, ability acknowledgement, authoritative resource rules, input timeout, smoothing and snap thresholds are unchanged. Protocol remains 35 and snapshot layout remains 15.

## Focused comparison

Sequential three-seed combined-fault runs used the existing real ENet proxy fixture, with latency, jitter, packet loss, duplication, reordering and a brief blackout. Scheduling still varies across live runs, so this is evidence of the mechanism rather than a deterministic benchmark.

| Seed | Baseline max correction / snaps | Reliable start and stop max / snaps |
| --- | --- | --- |
| 230926 | 176.28 px / 1 | 36.92 px / 0 |
| 230927 | 136.06 px / 1 | 58.35 px / 0 |
| 230928 | 127.73 px / 0 | 107.14 px / 0 |

The stop-only experiment still snapped in one seed; the selected start-and-stop implementation passed all three without a hard snap. This does not remove correction risk during long outages or delayed authoritative snapshots.

Focused regression coverage drops every ordinary input sample and verifies reliable start/stop, held-input traffic, direction changes, stale sequence rejection, simultaneous shield input, input blocking, death and a fresh heat. The suite passed 7,263 assertions before the separate UI refactor.

## Full impairment matrix

`python tools/verify-network-impairment.py --profile all --seeds 3` passed **24/24** existing acceptance gates: resource convergence, shield release and short-tap protection, guarded volleys and ability delivery. Acceptance does not require zero movement snaps; correction measurements are reported separately.

| Profile (three seeds each) | Largest correction | Total hard snaps |
| --- | ---: | ---: |
| Baseline | 0.07 px | 0 |
| Latency/jitter | 24.06 px | 0 |
| Loss | 0.11 px | 0 |
| Reorder/duplication | 71.99 px | 0 |
| Brief blackout | 0.07 px | 0 |
| Combined faults | 241.41 px | 1 |
| Tail loss | 0.07 px | 0 |
| Limited bandwidth | 92.98 px | 0 |

The combined seed 230926 tail retained input acknowledgement 10 while the client reached tick 96; the snapshot reported 76 ticks of input age. That roughly 1.3-second stale interval still caused a 241 px snap. The broader run therefore **does not prove all correction spikes fixed or a lower worst-case bound**. Reliable delivery cannot undo prediction accumulated while communication is unavailable. This residual remains a follow-up requiring an explicit outage/recovery policy, without weakening shield authority or silently relaxing snap thresholds.

Raw focused comparisons, full matrix measurements and the unit result are retained in `movement-edge-evidence-2026-09-04/`. These are local proxy tests of internet impairments, not a claim of remote-host playtest coverage.
