# Frame pacing fix — 2026-09-04

Snapshot identity lookups eagerly fetched the bridge's defensive lobby copy even when the match payload already contained the requested player. With 32 players, three identity lookups per snapshot entry repeatedly copied the complete nested lobby. The lookup now checks match identities first and fetches the lobby only for a missing peer. Late lobby identities, match precedence and defensive isolation remain intact; existing behavioral tests cover those cases.

A temporary function-timing probe measured snapshot handling at approximately 8.9 ms per snapshot on average before the fix. The retained verifier now records client snapshot/physics timings, engine monitors, drawing intervals and draw calls. It supports an uncapped run and a diagnostic hidden-world control. No production frame cap or graphics-driver settings changed.

Two sequential visible-window runs used the same instrumented fixture, 45 seconds each, 1920×1080, 32 pilots, the same match seed, vsync disabled and no FPS cap. Only the identity lookup differed. Full logs are in `.tools/frame-matched-before.log` and `.tools/frame-matched-after.log`.

| Measurement | Before | After |
| --- | ---: | ---: |
| Client snapshot p95 | 10.977 ms | 2.453 ms |
| Client physics callback p95 | 1.716 ms | 1.502 ms |
| Frame interval p95 | 27.922 ms | 19.347 ms |
| Frame interval p99 | 40.721 ms | 26.606 ms |
| Frame interval median | 17.256 ms | 17.243 ms |

Snapshot p95 fell approximately 78%, and frame p95 approximately 31%, in this pair. Live ENet scheduling changes the precise battle trajectory, so this is a measured improvement on this host, not a universal percentage guarantee. The follow-up included more draw calls at p95 (488 vs 386), rather than reducing threat or shield detail.

The 60 Hz target remains unmet. A separate uncapped hidden-world control still measured a 17.242 ms median and 17.464 ms p95 with only ten draw calls. This points to an additional rendering/presentation scheduling floor on this Windows/OpenGL setup; it does not establish the exact driver/compositor cause. Shader work, authoritative simulation, shield timing and network rates are unchanged. Engine timing categories overlap and their percentiles must not be summed.

Validation: 6,441 assertions passed with strict engine-error checks. Both matched live runs passed snapshot/ship/projectile/sample coverage. Numerical results are retained in [frame-pacing-evidence-2026-09-04](frame-pacing-evidence-2026-09-04).
