# Performance and stability follow-up — 2026-09-04

Performance acceptance covers local play, LAN and internet connections. This change adds repeatable measurements and retains their evidence; it does not claim a production speedup or close the remaining frame-pacing work.

## Tooling

- `verify-soak.ps1` retains each run in a unique directory, samples the actual Godot server process's OS private bytes and working set every five seconds, and requires active combat in every third of extended runs. The Windows console executable is a launcher, so source-server memory sampling uses the engine executable. The growth alarm compares six-sample means after a 60-second warmup and allows the larger of 64 MiB or 25%; this is a coarse leak alarm.
- `live_render_verifier.gd` runs a production ENet server, 31 NPCs and a rendered client at 1920×1080. It measures post-draw wall-clock intervals in active heats after warmup, with vsync disabled and a 120 FPS cap. Combat feedback is applied through the production world-view path. Coverage gates require snapshots, 32 visible ships, projectiles and sufficient active samples; frame percentiles are reported rather than silently treated as a 60 Hz pass.
- `verify-network-impairment.py` adds a 4 KiB/s-per-direction profile with 50 ms one-way delay and ±20 ms jitter. It serializes datagrams against a separate link timeline in each direction and records bytes and queueing. The sum of bandwidth waits is across datagrams, not a latency percentile.
- The overload wrapper uses a unique Godot log and rejects unexpected engine errors even when result markers are present. The only tolerated environment error is failure to read the Windows root certificate store.

## Recorded results

Windows, Godot 4.7.2, Intel Core i7-10700K, RTX 2080 Ti, OpenGL compatibility renderer. These are development-checkout measurements on this host, not minimum hardware specifications. Runs crossed midnight UTC on September 5 while still September 4 locally.

| Check | Result |
| --- | --- |
| 32 NPC / 1,024 projectile overload | p50 13.182 ms, p95 14.544 ms, p99 16.304 ms, maximum 19.254 ms. Mixed-mine p95 8.907 ms. Isolated run; excludes replication and rendering. |
| Extended 32-client ENet soak | 65 metric windows, all with combat; 624.8 simulated combat seconds, 24 heat results and 25 overtime events. Worst active-window p95 6.694 ms, p99 10.124 ms. Combat disconnect, late spectator, entity bounds, orphan checks and clean shutdown passed. |
| Server OS memory | 124 samples; peak private bytes 72.34 MiB, peak working set 119.62 MiB. Post-warmup private growth 4.39 MiB, below the coarse alarm. |
| Seven baseline/fault profiles, three seeds each | 21/21 passed, including 100 ms one-way delay with ±35 ms jitter, loss, reordering/duplication, blackout, combined faults and final-neutral loss/retry. Authoritative resources converged. |
| Added bandwidth profile, three seeds | 3/3 passed, with byte serialization exercised both ways. Approximately 12.5–12.8 KB upstream and 50–52 KB downstream per run; this small fixture is not a 32-player bandwidth requirement. |
| Live rendering, isolated 90-second run | 4,460 active samples, 1,689 snapshots, 32 ships and up to 58 projectiles. Frame p50 17.247 ms, p95 22.353 ms, p99 31.867 ms; 98.70% of intervals exceeded 16.667 ms. Coverage passed; the 60 Hz frame target did not. |

The live-render window was positioned offscreen for automated capture. Compositor/driver scheduling can influence intervals even with vsync disabled. The same process includes server and client work. A preceding run concurrent with other checks measured p95 27.221 ms; it is not an optimization baseline. Profile visible client rendering and engine frame scheduling separately before attributing the isolated tail to drawing or simulation.

Convergence does not mean seamless internet play. The latency profile recorded one hard movement correction per seed; combined faults recorded two, with a maximum correction of 410.5 pixels across the seeds. Those tails merit further reconciliation and input-age investigation. The soak's maximum ten-second payload window was 10,659,488 bytes across all peers, excluding transport overhead; it is not a per-client connection recommendation.

## Failed attempts and scope

An initial soak was deliberately interrupted after discovering that memory readings belonged to the console launcher. The first native-engine retry then admitted 31/32 clients and failed its admission gate. Its cause is unconfirmed; subsequent successful admission must not erase that intermittent failure.

The completed ten-minute run passed all runtime/lifecycle gates, then failed while aggregating memory dictionaries with PowerShell's `Measure-Object`. Samples are now stored as property-bearing objects. Its summary was regenerated from the retained raw data using the corrected summary block; the memory calculation passed. A subsequent 180-second configuration passed end to end: 32 clients, 23 metric windows, worst simulation p95 6.461 ms, memory aggregation, lifecycle checks and clean shutdown. Its independent summary is retained as `soak-wrapper-validation.json`.

The UDP fault proxy uses real ENet datagrams over loopback, with controlled synthetic impairments. It does not establish actual internet routing, NAT traversal, geographically distributed 32-player performance, multi-hour stability, physical input-to-display latency, or human shield timing/fairness. The new evidence supports continued investigation, not release-wide performance sign-off.

## Reproduce

```powershell
& ./tools/run-performance-benchmark.ps1
& ./tools/verify-soak.ps1 -ClientCount 32 -DurationSeconds 600
python tools/verify-network-impairment.py --profile all --seeds 3
. ./tools/common.ps1
$log = New-SsfVerificationLogPath -Name live-render
$output = & (Get-SsfGodotExecutable) --path . --audio-driver Dummy --resolution 1920x1080 --log-file $log --script res://src/test/live_render_verifier.gd -- --duration=90 2>&1 | Out-String
$exitCode = $LASTEXITCODE
Assert-SsfGodotResult -Output $output -ExitCode $exitCode -ExpectedPattern 'SSF_LIVE_RENDER_RESULT='
```

Durable numerical evidence is in [performance-evidence-2026-09-04](performance-evidence-2026-09-04/). The 21-case matrix preceded byte-counter instrumentation; its absence of byte counts is not zero traffic. Local full logs, including interrupted/failed attempts, remain in `.tools/soak-verification/20260905T000126-609b354c`, `20260905T000659-1d900831` and `20260905T000835-d5ce0463`. The isolated rendering log is `.tools/live-render-isolated.log`.
