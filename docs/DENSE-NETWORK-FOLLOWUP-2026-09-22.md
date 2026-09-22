# Dense transport under impairment

`python tools/verify-dense-replication.py --profile all` now runs 32 production
ENet clients with 1,024 projectiles through baseline, loss/jitter and shaped
per-client links. The extended CI job runs this matrix. The default invocation
retains the short baseline check for native functional CI.

The proxy models each client's two directions independently, counts actual UDP
payload bytes, bounds queued serialization time and datagrams, and records
random-loss and tail-drop counts separately. Its seeded scheduling, byte
accounting, independent links and overflow behavior have three Python tests.

The fixture waits for both server admission and client identity before creating
ships. It verifies all 32 full snapshots by exact projectile IDs, then removes
one projectile and introduces a replacement without publishing their delta.
Every client must recover both missing and obsolete membership. Continued player
snapshots, retained connections and bounded application recovery queues are
required. Faults persist during the first 24 seconds of replication; the final
six seconds use healthy delivery to test settlement. Admission is also impaired.

## Results

| Link profile | Result |
| --- | --- |
| Baseline | 32/32 recovered; passed seeds 230926 and 230927 |
| 50 ms one-way delay, ±20 ms jitter, 5% independent loss | 32/32 recovered; passed both seeds |
| 96 KiB/s per client/direction, same delay/jitter, 200 ms serialization queue | 32/32 recovered; passed both seeds despite 4,613 and 4,798 downstream tail drops |
| 96 KiB/s, 100 ms queue | **Failed**; 4/32 recovered by the end and the server had lost peers |
| 64 KiB/s, 200 ms queue | **Failed**; final corrected fixture recovered 9/32 and detected disconnections |

The two failing configurations remain explicitly selectable as `--profile
shallow_queue` and `--profile undersupplied`. They return a failing exit status;
they are capacity diagnostics, excluded from the documented passing `all`
acceptance set. `dense-network-evidence-2026-09-22.json` retains both successes
and failures, including each configuration and seed. The shallow-queue run
predated the final explicit server peer-count check, but already failed recovery
and its server log confirmed peer loss.

These failures are outstanding findings, not resolved transport defects. The
next transport change should address reliable recovery bursts/backlog and
per-client bandwidth adaptation; increasing average bandwidth alone did not
make the shallow queue pass. Application pacing bounds the scheduler's own
queue, not ENet's internal retransmission backlog.

This is a static dense replication test. It does not establish moving-combat
fairness, sustained arbitrary-WAN capacity, client render performance or
reconnect restoration. UDP totals include admission, framing and retransmission;
application totals cover only the replication interval, so their difference is
not a transport-overhead measurement. Some validation ran alongside the long
soak; no CPU capacity claim is made from these networking runs.
