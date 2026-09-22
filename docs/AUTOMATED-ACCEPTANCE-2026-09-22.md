# Extended automated acceptance

The third follow-up adds repeatable Windows package qualification:

```powershell
./tools/verify-windows-packages.ps1 -SoakSeconds 1800
```

This exports private client/server artifacts, audits their embedded resource
lists, starts the native client headlessly, mounts the client's actual PCK in
the pinned Godot runtime, connects its production client scene to the standalone
exported server, and then runs the 32-client soak against that server. Runtime
checks execute outside the source directory. Failures include unexpected engine
errors even when a process exits successfully. Artifact SHA-256 hashes and
interoperability results are retained. Without `-SoakSeconds`, it runs only the
package checks. `tools/verify-packaged-interop.py` can check existing artifacts.

Extended Windows CI now runs those package checks and the 30-minute packaged
server soak, plus 1,000 match/audio teardown cycles. It retains export audits,
runtime logs, soak memory samples, lifecycle results and dense-network evidence.

## Local qualification

Game artifacts were exported from an isolated archive of `c847beb`, including
all production changes in these three follow-ups. Later commits change tests,
tools, CI and documentation only. The archive excluded unrelated working-tree
edits and staged audio deletions. The long soak used the existing working-tree
client bots and soak harness against that clean exported server; this distinction
is separate from the clean packaged-client interoperability check.

- Clean-checkout unit suite: **14,522 assertions, zero failures**. The working
  tree's suite passed 14,661, including the owner's additional tests.
- Client/server resource audits passed: **613 / 467 embedded entries**.
- Native client headless startup and packaged interoperability passed with
  shipping features, **protocol 40 / packet 17**, **343 snapshots** and **18 full
  recoveries**. Both processes exited cleanly; the server reported graceful
  shutdown. The editor runtime is used only to run the external test driver
  against the exported client PCK; shipping templates cannot run that driver.
- **1,000 lifecycle cycles** after ten warmups passed: **zero retained-object
  growth**, **754,320 bytes** of tracked-memory growth. Stored measurement rows
  contribute to that growth. This is tracked engine memory, not client OS RSS.
- **30-minute, 32-client packaged-server soak passed**: 185 health windows,
  1,793.45 seconds of active simulation, 74 completed heats and 75 overtime
  events. Combat disconnect, late spectator admission, bounded collections,
  child-process exit and graceful server shutdown passed.

| Soak measurement | Result |
| --- | ---: |
| Worst-window active CPU p95 / p99 | 6.486 / 8.695 ms |
| Minimum callback rate in full windows | 59.941 Hz |
| Maximum over-budget callbacks in a window | 0.167% |
| Largest callback scheduling gap | 68.428 ms |
| Dropped log batches / orphan nodes | 0 / 0 |
| Peak active projectiles | 163 |
| Server OS private-memory peak | 79.11 MiB |
| Post-warmup private-memory growth | 10.90 MiB |
| OS memory samples | 361 |

Memory growth compares six-sample means after a 60-second warmup. It is below
the harness's coarse `max(64 MiB, 25%)` alarm, but remains a reason to check
longer-run growth/plateau behavior. Passing does not establish zero leaks.
The shipping build's tracked-memory counter is unavailable (reported as zero);
the OS private-memory and working-set samples are the relevant measurements.
The 68.428 ms scheduling gap is also retained rather than hidden by CPU p95.

Summary, artifact hashes, per-window health and OS memory samples are retained
in [automated-acceptance-evidence-2026-09-22.json](automated-acceptance-evidence-2026-09-22.json).

## Limits

These are private qualification artifacts, not a published release. Release
build scripts retain their separate attribution/sign-off gates. The archived
checkout's attribution verifier reported a crosshair hash mismatch, so this
report does not claim provenance approval. No assets or provenance records were
changed by this work.

Linux/macOS/ARM native runs, rendering on representative GPUs, human fairness
testing and long client OS-memory qualification remain outside this run. The
soak's randomized workload and the static 1,024-projectile transport fixture
have different scopes; neither substitutes for the combined mixed-mode CPU
matrix. Other validation processes ran during the first part of the soak on
the same host. Its CPU and memory data are environment-specific and are not
inferred from display FPS.
