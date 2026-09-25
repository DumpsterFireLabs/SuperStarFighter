# Dedicated server readiness — September 8, 2026

This pass keeps the authoritative simulation at 60 Hz and the supported capacity at 32 players. It addresses operational failures found by testing both the checkout and the Windows release package.

## Changes

- Health reports now rotate every ten wall-clock seconds, including idle and paused sessions. Previously a pause froze the metric boundary while timing samples continued accumulating.
- Admin status includes uptime, the latest health window and its age. Callback rate and maximum scheduling gap expose stalls beyond the measured simulation work; replication payload bytes/sec provide a bandwidth baseline.
- The server launcher accepts unattended credentials and explicit log paths. The packaged Windows executable is launched with a retained process handle, so its lifetime and exit code are preserved. This matters because PowerShell can return immediately from direct invocation of the GUI-subsystem export.
- Dedicated exports flush logs immediately. The release template otherwise buffered idle health until shutdown. The setting was verified in the installed engine and against [Godot's file logger](https://github.com/godotengine/godot/blob/master/core/io/logger.cpp).
- Tick logs are batched and sent through a worker with a 262,144-character producer queue. Slow output does not directly block the simulation thread; overflow is counted and reported, and graceful shutdown drains queued records. Logging timing fields measure main-thread submission; worker I/O is outside callback timing. Queue pressure and wall-clock callback cadence remain visible.
- Admin commands support unattended operation, bounded connect/read/write timeouts, and an explicit successful exit code.
- Packages include the launcher and admin tool. The build's operations gate exercises paths with spaces, fresh idle logs, authenticated status, and graceful shutdown outside the checkout.
- The load gate now rejects full windows below 57 callbacks/sec or with more than 1% of callbacks over 16.67 ms, and has a wall-clock deadline.

## Validation

- Final unit suite: **9,491 passed, 0 failed**, including paused/idle health rotation, detached status data, partial-window flush, batched record ordering, worker bounds and shutdown draining.
- Foundation: **193 checks passed**, including import, script parsing, startup, and the deliberately failing test-exit path.
- Malformed/excessive traffic: isolated while healthy clients continued; clean shutdown passed.
- Unattended missing credentials: failed without prompting. An admin endpoint that accepted TCP but sent no challenge timed out.
- Packaged operations: passed. The adjacent-executable launch path also propagated the expected startup failure code **3** for the reserved discovery port.
- Final export audit: **453 entries**, **549,023 bytes** of server resources. The engine binary remains the official template.

The pre-change 32-client, 180-second localhost baseline passed with worst-window p95 **4.707 ms** and p99 **6.428 ms**. See [baseline evidence](server-readiness-evidence-2026-09-08/baseline-soak.json) and [packaged idle health](server-readiness-evidence-2026-09-08/packaged-idle-status.json).

The first 600-second packaged run failed the newly introduced tail gate: one ten-second window had **7/600 callbacks (1.167%)** over budget. Worst-window p95 was **7.932 ms**, p99 **18.704 ms**, and the largest individual callback was **384.505 ms**. This led to batching output and moving dedicated log writes off the simulation thread; it does not by itself prove every stall came from logging. The limits were retained for the subsequent run. See [the preserved failure evidence](server-readiness-evidence-2026-09-08/pre-log-worker-soak.json).

**The final 32-client, 600-second packaged soak passed all gates.** It captured 65 health windows with active combat in each, 26 heat results, overtime, combat disconnect removal, late-spectator admission and a clean shutdown.

| Measurement | Final result |
| --- | ---: |
| Lowest full-window callback rate | 59.934 Hz |
| Worst-window callback p95 / p99 | 6.187 / 7.642 ms |
| Worst active-combat p95 | 6.322 ms |
| Worst full-window over-budget rate | 0.333% (limit: 1%) |
| Main-thread log submission mean / max | 1.38 / 1,214 microseconds |
| Dropped log batches | 0 |
| Peak OS private memory | 58.38 MiB |
| Post-warmup private-memory growth | 3.58 MiB |
| Peak replication payload rate | 1.11 MB/sec |

See [final soak evidence](server-readiness-evidence-2026-09-08/packaged-soak.json). The largest individual callback was still **69.989 ms**, and the largest callback scheduling gap was **120.934 ms**; passing these distribution-based gates is not a claim of hitch-free operation. The before/after runs have the same harness settings but are not identical input replays.

A separate deliberately blocked output sink confirmed that 100 producer submissions completed in **56 microseconds** while the writer could not make progress. The small test queue stayed at its 1,024-character cap and explicitly accounted for 92 rejected batches. See [blocked-sink evidence](server-readiness-evidence-2026-09-08/blocked-sink.txt).

The defensive overload fixture passed at **32 NPCs / 1,024 projectiles**: p95 **15.510 ms**, p99 **17.186 ms**, max **21.397 ms**. The mixed **512-mine / 1,024-projectile** fixture passed at p95 **9.869 ms**. These measure NPC/world simulation, excluding replication and rendering; their overload budgets are separate from the ordinary full-server 16.67 ms target. See [overload evidence](server-readiness-evidence-2026-09-08/overload.txt).

## Running a candidate

Follow [SERVER_README.txt](../SERVER_README.txt) for unattended launch, authenticated status and graceful shutdown. Reproduce the package checks from the checkout:

```powershell
.\tools\build-server.ps1
.\tools\verify-soak.ps1 -ClientCount 32 -DurationSeconds 600 -ServerExecutable .\builds\server\SuperStarFighter-Server.exe
```

All measurements here use a local Windows development host, with the server and source-based bot clients on the same machine. They do not establish WAN latency, deployment-host capacity, or multi-day stability. Release-template static-memory telemetry reports zero; use OS private bytes/working set instead. Replication payload rates exclude transport overhead and other control RPCs. Host service installation, restart policy, firewall configuration and WAN acceptance remain deployment work.
