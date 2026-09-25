# Shared-address admission fix — 2026-09-04

The intermittent 31/32-client soak failure was an admission throttle, not insufficient player capacity. The rejected client's Godot log reported `AUTH_RATE_LIMITED`: a third connection from the same source arrived while two password challenges remained active. The same condition can affect LAN cohorts or internet players behind one NAT.

Additional connections now wait in arrival order while retaining the two-active-challenge budget per source. Queue promotion preserves the original ten-second handshake deadline. The existing ENet capacity, eight reserved authentication slots, connection-attempt throttle, failed-proof cooldown and source bans remain in force. A queued peer cannot authenticate before receiving its fresh challenge. Expiration and teardown clear both queued and active records.

The repeated burst fixture also exposed sends to closing transports during mass disconnects. Server-only routing now disables unused peer-to-peer relay announcements, and lobby/gameplay broadcasts filter for admitted, connected recipients. During steady play the bridge retains a single broadcast serialization. Queueing alone and either disconnect fix alone admitted the cohort but still emitted engine errors; those intermediate runs were rejected by the strict verification gate.

## Verification

- The old implementation reproduced the false rejection before its first delayed challenge response.
- Three real-ENet cycles with a 150 ms challenge-transmission delay admitted all **96 initial clients and three late spectators**, with zero rejections or unexpected engine errors. Each cycle also readied 32 peers, started combat, replaced one peer with a spectator and disconnected the whole cohort cleanly.
- Repeating all three cycles with a **300 ms** challenge delay through the committed wrapper admitted another **96 initial clients and three late spectators**, again with zero rejections or unexpected engine errors.
- **7,238 assertions passed**, including FIFO promotion, independent source progress, unchanged active-challenge limits, original deadlines, premature-proof rejection, source bans and teardown.
- Hardening passed: malformed/excessive peers were isolated while healthy clients continued.
- Match-loop verification passed: private picks, timeout selection, two matches, reset/rematch and clean shutdown.
- A separate 32-process, 60-second-configured soak passed all initial admissions, 11 metric windows, overtime, combat disconnect, late spectator admission, bounded entities and clean shutdown. Its highest window server-callback p95 was **7.52 ms** (active-combat-only p95: **9.83 ms**). This short source-build check does not establish long-session memory stability or end-to-end frame latency.
- Shipping resource allowlists remain current.

The repeatable command is `tools/verify-admission-burst.ps1`; `-ChallengeDelayMs` accepts 0–300. These are real loopback ENet connections with controlled challenge delay, not a claim of geographically distributed internet acceptance. The ten-second total deadline intentionally remains bounded; sufficiently slow cohorts can still expire. Full WAN movement, shield and resource checks are recorded separately in [movement replay evidence](MOVEMENT-REPLAY-FIX-2026-09-04.md).

Selected machine-readable results and validation output are retained in [admission-fix-evidence-2026-09-04](admission-fix-evidence-2026-09-04).
