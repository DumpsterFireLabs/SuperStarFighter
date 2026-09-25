# Movement replay fix — 2026-09-04

Under stalled input acknowledgements, authority continues stepping the last held input. The client previously restored that newer snapshot and then replayed every unacknowledged frame, counting the same elapsed time twice. In a latency trace, acknowledgement 12 remained unchanged while snapshots advanced from tick 84 to 114. Reconciliation repeatedly pushed the prediction forward by roughly 24 pixels, then snapped it back when acknowledgement 48 arrived.

The recipient correction now carries a bounded uint16 `input_age_ticks`. Replay subtracts the time already simulated by authority beyond the acknowledged frame. Covered input identities remain buffered until acknowledged; the server's sequence checks, 0.5-second input timeout, collision rules, resource authority and shield press semantics are unchanged. Overlapping small corrections also retain their remaining visual offset instead of introducing another display jump.

The correction trailer grows from 61 to 63 bytes: 1,193 bytes for a 32-player snapshot, still below the 1,200-byte packet budget. Application protocol is now **35**, binary packet version **15**; clients and servers need matching builds. No extra input traffic or reliable movement stream was added.

## Evidence

Before the fix, fresh single-seed latency and combined-fault probes measured maximum corrections of 232.19 and 269.48 pixels respectively, each with one hard snap. The final eight-profile, three-seed real-ENet proxy matrix passed **24/24**, preserving ability delivery, resource convergence and short shield-tap/volley checks.

| Profile | Final p95 correction across three seeds | Final maximum correction | Hard snaps across seeds |
| --- | --- | --- | ---: |
| Latency/jitter | 0.75–1.65 px | 32.02 px | 0 |
| Combined faults | 0.01–0.70 px | 184.01 px | 1 |
| Limited bandwidth | 1.50 px | 31.96 px | 0 |
| Baseline | 0.05 px | 1.77 px | 0 |

The remaining combined-fault snap is retained in the evidence. A blackout can still leave authority and local input histories different; this change removes duplicate simulation time, not the consequences of all lost input. Snap thresholds remain 128 pixels. The fixture now retains bounded large-correction traces with acknowledgement, client/server ticks, snapshot input age, replay depth and positions. Scheduling affects exact faults and trajectories, so these measurements are not guarantees for every connection.

Validation: **7,223 assertions passed** before the independent admission-test additions. New cases use production replication and codec round trips with 0/6/12-tick snapshot delay, held-input loss, resumed delivery, Afterburner, shield drain, precise Perfect Guard clocks, bounded input-age encoding and overlapping smoothing. Wire movement allows a small three-pixel error for quantized position/velocity/boost timers; the new replay fixtures produced no hard snaps.

The final matrix is retained in [movement-replay-evidence-2026-09-04](movement-replay-evidence-2026-09-04), with full local logs under `.tools/network-impairment/20260905T005451-8895b9d9`. Movement and codec code stayed fixed during that matrix; the independent admission follow-up was developed alongside it. These are controlled loopback impairments, not geographically distributed internet acceptance.
