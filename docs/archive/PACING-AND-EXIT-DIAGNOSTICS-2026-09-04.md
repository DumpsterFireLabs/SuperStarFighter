# Frame pacing and exit diagnostics — 2026-09-04

An empty 1920×1080 window reproduces the remaining OpenGL pacing floor on this host: median 17.241 ms and p95 approximately 17.3 ms, with almost all of the interval inside drawing/presentation. It contains no game world, UI, audio or network. Disabling vsync at startup and requesting exclusive fullscreen did not remove this floor. This isolates a display-path limitation; it does not identify a particular driver setting or prove a universal hardware limit. Production renderer and user display settings are unchanged.

The ANGLE experiment emitted shader initialization errors and is rejected. Its fast empty-window numbers are not valid performance evidence for gameplay. Godot also documents that command-line vsync disabling cannot override driver enforcement; see the [official frame-pacing guidance](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html).

## Removed repeated work

Dead-ship snapshots restarted the elimination animation every time, and dead remote ships continued through interpolation and redraw requests. Elimination now starts on the alive-to-dead transition; remote motion work stops for dead ships. Authority, shield timing and living-ship interpolation are unchanged. Regression coverage confirms the pulse expires while dead snapshots continue.

Sequential 45-second visible-window runs used the same seed, fixture, 32 pilots, uncapped rendering and 1080p; the changed run preceded the baseline restoration run. Live packet scheduling still changes battle trajectories.

| Measurement | Baseline | Changed |
| --- | ---: | ---: |
| Client physics p95 | 1.456 ms | 1.149 ms |
| Snapshot p95 | 2.275 ms | 2.044 ms |
| Frame p95 | 17.497 ms | 17.570 ms |
| Frame p99 | 22.982 ms | 20.894 ms |

CPU callback measurements improved in this pair; frame p95 is effectively unchanged. **Subsequent user clarification: this workstation is hard-capped at 58 FPS**, so the 17.24 ms floor is expected and a 60 FPS comparison is inappropriate here. See [cap-aware follow-up](CAPPED-FRAME-PACING-2026-09-04.md). The result does not justify a renderer switch or hiding additional threats/shields.

## Windows termination report

The user supplied a native memory-write error dialog. An experimental empty-window probe reproduced exit code `0xC0000005` during shutdown. The revised control records through named render callbacks, disconnects them and finishes from the scene loop. It exits with code zero. The live verifier also leaves render-signal dispatch before teardown. Earlier failed probes remain in ignored local logs and are not acceptance passes.

The recent normal-game logs contain server-shutdown records without script errors or a crash trace; no matching Godot report was found in the queried Windows application events or WER archives. This does not establish the cause of every reported termination. The normal client now logs window-close requests, connection loss and scene exit with match state/tick. `tools/start-client.ps1` retains a unique Godot log plus its process exit code beside it, instead of relying solely on rotating default logs.

Validation: 7,251 assertions passed. `tools/verify-frame-pacing.ps1` runs the empty control and a visible live fixture sequentially with unique logs, completion/coverage checks and strict engine-error handling. It reports timing separately from passing coverage; it never calls a timing miss a 60 Hz pass. Selected measurements are retained in `pacing-exit-evidence-2026-09-04/`.
