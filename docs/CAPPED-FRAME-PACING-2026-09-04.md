# Frame pacing at the configured 58 FPS cap

The user confirmed this workstation is externally capped at **58 FPS**. Its expected frame interval is **17.241 ms**, matching the earlier empty-window measurements. The earlier comparison against 16.667 ms did not establish a game performance defect: it asked this capped system to exceed its configured limit. Historical measurements remain valid; that interpretation is corrected here.

The cap, driver configuration, renderer, shield rules, input sampling and 60 Hz authoritative simulation are unchanged. Verification now accepts `-ExpectedFps 58` as measurement context independently of the engine cap. It reports frames more than 1 ms above that interval, frames exceeding 1.5 intervals, maximum interval and the longest chronological late-frame streak. These thresholds describe overruns, not an automatic performance sign-off. The legacy over-16.667-ms field remains for historical comparisons and is not the acceptance metric on this system.

## CPU changes

1. A snapshot builds one peer-identity lookup from the current match roster. Missing peers use at most one detached lobby observation. Each ship resolves its name, colour and pattern once. The lookup lasts for one synchronous snapshot, so later reliable lobby updates remain observable and match identities retain precedence.
2. Remote interpolation retains only position, velocity and aim. Resource/correction fields were deep-copied into every sample despite never being interpolated. The time-order check also replaces a redundant comparison of entire sample dictionaries. Interpolation delay, sample selection, extrapolation limit and authoritative resources are unchanged.
3. Remote shot sound profiles reuse the ship's already-derived build stats. Each event still gets a private stats copy for authoritative projectile overrides. Shots arriving before their ship retain the derivation fallback; local shots use prediction's current stats. No sound events or visible threats are suppressed.

## Fixed workload comparison

The same committed benchmark script exercised baseline production files from `89313bd` and changed production files in **baseline / changed / changed / baseline** order. Each run measured 300 identical 32-pilot snapshot batches and 32-shot profile batches after 40 warmups. Every run retained 32 ships and emitted all 10,880 shot events. This isolates CPU costs from different live battle trajectories and the frame limiter.

| CPU measurement | Baseline runs | Changed runs |
| --- | ---: | ---: |
| 32-pilot snapshot p50 | 1.543 / 1.545 ms | 0.794 / 0.800 ms |
| 32-pilot snapshot p95 | 1.961 / 1.856 ms | 0.990 / 1.067 ms |
| 32-shot sound-profile batch p50 | 5.955 / 5.946 ms | 1.005 / 1.002 ms |
| 32-shot sound-profile batch p95 | 6.592 / 6.536 ms | 1.186 / 1.372 ms |

Snapshot p95 decreased approximately **45–50%**, and the sound-profile batch approximately **79–82%**. These are headless CPU callback measurements; they exclude audio mixing, rendering, transport and physical input/display latency. They must not be presented as equivalent FPS gains.

## Live pacing and validation

The initial 60-second visible 1080p fixture used real loopback ENet, one client and 31 NPCs. At 58 FPS, p50 was 17.241 ms, p95 17.550 ms and p99 22.102 ms; 2.84% of measured frames were late by more than 1 ms, with ten severe frames. Its empty control measured 0.50% late frames.

An intermediate identity/interpolation-only run had cheaper snapshot callbacks (p95 2.286 → 1.812 ms) but worse overall pacing: 5.43% late frames and p99 27.265 ms. Its empty control also had more late frames (2.01%), and its live draw-call p95 was 400 versus 329. Live battle scheduling and host presentation noise vary. This run is retained rather than discarded; one pair cannot prove a lower worst-case frame bound.

With all three optimizations, the final live run measured **p50 17.241 ms, p95 17.680 ms, p99 26.138 ms**. Snapshot callback p95 was 1.663 ms. Of 2,858 active samples, 119 (4.16%) exceeded the 18.241 ms late threshold, 29 exceeded 25.862 ms, and the maximum interval was 65.073 ms. Coverage and strict error checks passed. This supports the CPU optimization and the corrected 58 FPS baseline, **not a claim that worst-case stalls are solved or overall frame pacing improved**. Further stall attribution needs correlated frame/CPU/presentation traces rather than subtracting overlapping aggregate percentiles.

The full suite passed **7,301 assertions**, covering roster precedence, late updates, interpolation values detached from mutable input, sound families/power before and after build changes, projectile overrides without modifying combat stats, and cap-aware frame classification. Shipping resource allowlists are current. Only the repository's exact Windows certificate-store diagnostic is tolerated; unexpected engine errors and failed exit/completion checks reject a run.

The real-ENet combined impairment fixture also passed **3/3 seeds**, retaining shield/ability coverage and final resource/replay convergence. No wire protocol or shield timing changes were needed.

Reproduce with `tools/verify-frame-pacing.ps1 -ExpectedFps 58 -DurationSeconds 60` and `tools/measure-client-presentation.ps1`. Per-operation profiling is confined to the live verification fixture. Production gameplay does not collect these timing arrays. Raw baseline/intermediate/final controls and live measurements, the CPU comparison and validation markers are retained in `capped-pacing-evidence-2026-09-04/`. The standalone benchmark wrapper passed; its run overlapped a fault test and is not used for the isolated CPU comparison.
