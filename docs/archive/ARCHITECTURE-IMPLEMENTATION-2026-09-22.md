# Architecture follow-up implementation — 2026-09-22

Eight independently committed follow-ups to the performance/architecture review. R01–R08 remain the earlier corrective series; A01–A08 are the architectural series on `codex/architecture-followups`.

| Item | Implementation | Commit |
| --- | --- | --- |
| A01 | Incremental draft preparation, atomic offer publication, full decision deadlines, bounded transition timing counters | `7c92dc5` |
| A02 | Typed lobby/match command service after RPC authorization and payload validation; weak owner reference | `7d68408` |
| A03 | Projectile integration, targeting, mines and hit resolution extracted from the world; world retains authoritative state and damage queues | `18fed0a` |
| A04 | Dedicated audio preparation/cache/worker owner and pure procedural synthesis service; director retains playback, mixing and music control | `ef48255` |
| A05 | Full recovery paced at four chunks per tick, one bounded pending batch, categorized payload estimates, real 32-client UDP measurement | `094c226` |
| A06 | Shared radial masks for ordnance and effects, batched mine spokes, permanent CPU draw-attribution fixture | `7099120` |
| A07 | Four-seat human-only semi-competitive team preset and explicit camera, pause, NPC, pickup and effect policies | `7f61691` |
| A08 | Windows/Linux/macOS CI definition, negative gates, mixed mode/map/build fixtures, repeated lifecycle memory checks, optional long soak | This document's commit |

## Validation and measurements

The machine is limited below 60 FPS. No result here treats its displayed frame rate as a measure of achievable performance. CPU execution time, deterministic state, delivery completeness and memory ownership are measured separately. Machine: Windows, Intel i7-10700K, RTX 2080 Ti, Godot [4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable).

- Isolated committed-code suite: **14,514 passed, 0 failed**; working-tree suite including unrelated local edits: **14,653 passed, 0 failed**. Portable CI additionally checks that an intentional assertion fails and that an engine error cannot hide behind exit code zero.
- Projectile extraction: **six frozen pre-extraction traces match exactly**, covering two seeds across Core Arena, Riftline and Prism Array; 205 combat/trace assertions passed. No projectile phase or tie ordering was deliberately changed.
- Audio/presentation: **528 focused assertions passed**, including copied-profile ownership, queue/cache bounds and joining an active worker during teardown.
- Lobby/competitive setup: **81 focused assertions passed**, including shrinking an eight-team NPC lobby, preserving humans, removing NPC entities and restoring balanced teams.
- Draft preparation: the empty-build 32-human fixture enters draft in approximately **0.32 ms**, then prepares across 16 slices (maximum approximately **2.54 ms**, aggregate approximately **36.5 ms**). The 2 ms slice target is checked between pilots; one pilot's work can exceed it. Offers publish together after preparation, with the full configured decision time.
- Network regression: **8/8 real ENet impairment profiles pass**: baseline, latency/jitter, loss, reordering/duplication, blackout, combined faults, final-input loss, and limited bandwidth.
- Dense delivery: **all 32 real ENet clients receive all 1,024 projectiles**. A complete recovery contains 27 chunks and drains over seven simulation ticks. At most 4 × 1,200 × 32 = **153,600 application bytes of recovery fan-out** are scheduled per tick; snapshots and other traffic are additional. Actual transport can coalesce or retransmit packets, so this is not a wire-rate limit.
- Dense proxy example: **17,812,095 downstream UDP payload bytes** across admission plus a five-second, 300-tick measurement. The five-second scheduler window estimated **9,779,840 application bytes**. These windows/scopes differ and must not be subtracted to claim protocol overhead. UDP counts include ENet/RPC traffic and retransmission, but exclude IP/UDP headers. Admission, challenges, private offers, rejections, lobby and objective broadcasts now contribute to control-payload accounting; protocol framing remains outside the estimate.
- Render replay: same final workload checksum, 600 measured frames after 60 warmup frames, and all 1,024 projectiles drawn. Effects draw-callback p95 **4.534 → 1.918 ms** (58% lower); total callback sum p95 **16.195 → 13.716 ms** (15% lower). Projectile callback p95 **8.611 → 8.533 ms**, effectively unchanged. An inspected screenshot retains mine rings, projectile identities and explosion cues. These timings exclude renderer traversal, GPU work, presentation wait, simulation and networking.
- Mixed acceptance: **five modes/maps**, 16 humans plus 16 NPCs, stacked card-derived stats, 1,024-projectile refill, objective transitions, cargo/solar/door effects, real coordination and packet scheduling. Functional invariants pass. Representative CPU p95 values are **15.71–17.73 ms**; maxima **18.78–31.50 ms**. Some cases exceed a 16.67 ms tick budget. This is useful stress coverage, not a strict 60 Hz certification.
- Strict combined CPU check: final 32-human/1,024-projectile run passed with **13.642 ms p95, 15.897 ms maximum and zero overruns** across 360 measured ticks. An earlier run had five overruns. A controlled extraction comparison identified repeated world-property lookups; call-local references recovered most of that cost without retaining state or changing the six traces. Both failed and passing measurements are preserved in the evidence; timing tails vary.
- Lifecycle memory: **80 measured cycles after ten warmups**, no retained-object growth and approximately **183 KB tracked-memory growth**. This includes repeatedly releasing drafts, worlds, coordinators, schedulers and active audio workers; sample storage and warmed caches contribute to measured memory. It is not an OS-RSS or long-session certificate.

Machine-readable results: [architecture-evidence-2026-09-22.json](architecture-evidence-2026-09-22.json). Rules: [SEMI-COMPETITIVE-RULES.md](../SEMI-COMPETITIVE-RULES.md).

## Repeatable acceptance

- `python tools/ci-acceptance.py --godot <verified-engine-path>` runs native import/startup, metadata/export checks, unit and negative gates, dense ENet fan-out, the mixed matrix and lifecycle memory checks.
- `python tools/verify-architecture-matrix.py --godot <engine>` reports CPU distributions without gating shared-runner timing. Add `--strict-physics-budget` on a named target machine to require zero overruns.
- `python tools/verify-dense-replication.py --godot <engine>` records actual loopback UDP payload counts and confirms complete delivery to 32 clients.
- `godot --path . --script res://src/test/draw_attribution_verifier.gd` records CPU drawing time and writes `.tools/draw-attribution.png`.
- `godot --headless --path . --script res://src/test/architecture_memory_verifier.gd -- --cycles=300` extends lifecycle retention checks.
- `.github/workflows/acceptance.yml` runs functional acceptance on Windows, Linux and macOS. The manually selected extended job adds all impairment profiles and a **30-minute, 32-client Windows soak**. It retains evidence on failure. Workflow syntax and artifact behavior follow the [GitHub workflow reference](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) and [official artifact action](https://github.com/actions/upload-artifact).

## Remaining qualification

Native Linux/macOS jobs and the new 30-minute CI soak have been configured, not executed from this machine. Minimum-spec GPU/driver acceptance, long-session OS-RSS behavior, WAN congestion and latency under dense traffic remain hardware/environment qualification work. The mixed worst-case fixture still exposes CPU overruns, and countdown/heat-result work remains synchronous and measured. Further optimization should target those observed tails rather than infer a bottleneck from capped FPS.

The semi-competitive preset is editable and uses host-controlled pauses. Normal clients enforce the camera restrictions; the server does not filter all observer snapshots against modified clients. This work does not claim tournament anti-cheat or spectator confidentiality.

## Subsequent automated follow-ups

The following reports update the A08 qualification checkpoint above:

- [Mixed-workload CPU follow-up](CPU-FOLLOWUP-2026-09-22.md): lazy threat-index construction reduces measured p95 across the five-mode matrix; peaks still exceed the tick budget.
- [Dense impaired transport](DENSE-NETWORK-FOLLOWUP-2026-09-22.md): 32-client/1,024-projectile recovery passes loss/jitter and the documented shaped-link envelope. Lower bandwidth and shallow queues expose retained, reproducible failures.
- [Extended automated acceptance](AUTOMATED-ACCEPTANCE-2026-09-22.md): clean-checkout tests, 1,000 lifecycle cycles, fresh Windows package audits, native headless startup, packaged interoperability and the local long-soak evidence. This does not claim the remote Linux/macOS CI jobs have run.
