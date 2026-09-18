Performance review — Super Star Fighter — 17 September 2026

There is measurable room to improve CPU headroom and frame consistency without changing gameplay, reducing simulation frequency, or removing visual features. The strongest confirmed opportunities are projectile packet encoding, repeated collision-geometry lookup, and copying unchanged match data. Ship pattern drawing is a promising rendering target, with further controlled visual validation needed.

The user's 58 FPS limit is accounted for throughout. A displayed frame has approximately **17.241 ms**, while the authoritative **60 Hz physics tick still has 16.667 ms**. An empty window measured 17.241 ms median even with engine frame limiting and VSync disabled. Consequently, the old `over_16ms_percent` field is misleading on this machine: nearly all frames exceed 16.667 ms simply because of the external cap. Do not change the physics tick rate to 58 or interpret an unchanged FPS counter as an unsuccessful optimization.

| Finding | Status | Priority and next action |
| --- | --- | --- |
| 1. Full projectile recovery creates a periodic encoding spike | **Fixed — protocol and ENet acceptance passed** | High under heavy ordnance. Pre-size packets and use native integer writes while preserving bytes and chunk boundaries. |
| 2. Ship patterns rebuild transformed vertex arrays during drawing | **Open — exploratory prototype measured** | High for client presentation. Retain local geometry and apply a draw transform; validate appearance and batching. |
| 3. Client projectile sweeps repeatedly resolve cached geometry | **Fixed — dynamic geometry acceptance passed** | Medium; straightforward CPU saving. Retain geometry by map, radius, and cover revision. |
| 4. Small match updates copy and recursively freeze unrelated data | **Open — prototype measured** | Medium, especially large builds/objective modes. Share unchanged immutable subtrees. |
| 5. Existing performance gates omit important work and include profiling overhead | **Open — measured coverage gap** | Improve the gate alongside the optimizations: combined simulation/replication tails, production composition, and cap-aware cadence. |

These statuses refer to production implementation. Original measurements below remain historical review evidence. Implementation and acceptance results are recorded in [the follow-up](PERFORMANCE-ACCEPTANCE-2026-09-18.md); findings are marked **Fixed** after their checks pass.

Scope and environment

Reviewed HEAD `3070442150c2766d59a9ebed90cfe2d6a211c408`, including the existing working-tree changes. This includes the newer arena effects added after the architectural review. Measurements ran serially on an Intel i7-10700K (16 logical processors), NVIDIA RTX 2080 Ti, driver 596.21, Godot 4.7.2, OpenGL compatibility renderer, Windows, at 1920×1080. No driver/display settings were changed. The rendered fixtures disable their own VSync/engine cap and use the reported external 58 FPS limit for interpretation. Rendered tests use Dummy audio; audio mixing is outside these measurements.

Source inspection covered authoritative stepping and collision indexes, NPC decisions, replication and packet codecs, client prediction/interpolation, match-state publication, HUD updates, and procedural ship drawing. Execution covered the existing overload and mixed-mine fixtures, fixed client CPU batches, an empty rendered window, live ENet gameplay, a hidden-world control, instrumented ships, and isolated paired experiments. This is not a native-platform, every-map/effect combination, long-session memory, or remote-network acceptance run.

Baseline evidence

| Workload | Measured result | Interpretation |
| --- | --- | --- |
| Empty window, 399 frames | Median 17.241 ms; p95 17.318 ms; 1.00% late; no severe frames | Confirms external pacing near 58 FPS. |
| Live server + 31 NPCs + client, 1,999 active frames | Median 17.242 ms; p95 18.884 ms; p99 25.695 ms; 5.95% late; 18 severe frames | Additional frame-time variation exists beyond the cap. Peak 62 projectiles, 32 ships. |
| Same fixture with world hidden, 2,031 frames | Median 17.241 ms; p95 17.367 ms; p99 17.883 ms; 0.30% late; 1 severe frame | Rendering/presentation work deserves attention; not a byte-identical replay or a direct GPU-time measurement. |
| Existing 32-NPC / 1,024-projectile overload | p95 15.298 ms; max 21.863 ms | Passes the existing defensive overload gate. Includes detailed profiling; excludes refill, replication and rendering. |
| Existing 512-mine / 1,024-projectile fixture | p95 9.570 ms; max 11.950 ms | Passes its gate. This fixture has no combatants; it does not measure clustered ship-triggered chain explosions. |
| Fixed 32-player snapshot reception | p50 0.855 ms; p95 0.967 ms | Headless client callback cost; no rendered frame. |
| Fixed batch of 32 weapon-shot presentation events | p50 1.035 ms; p95 1.105 ms | Sound-profile/event work; no audio mixing. |

“Late” means above 18.241 ms (58 FPS budget plus 1 ms); “severe” means above 25.862 ms. These diagnostic thresholds are intentionally separate from the 60 Hz server budget. Live samples cover active heats after startup warmup. The hidden-world run retains simulation, network and callbacks but suppresses most drawing (p95 draw calls fell from 474 to 13). Runs differ in simulation/network timing; do not subtract their percentiles to claim an exact rendering cost.

In the ordinary visible run, server callback active p95 ranged from 1.008–2.887 ms across ten-second windows, with no callbacks over 16.667 ms. Client physics p95 was 1.427 ms and snapshot reception p95 was 1.411 ms. This does **not** look like continuous server overload in the sampled match. Engine process/physics monitors, draw intervals, and callback timers overlap and can include scheduling/presentation effects; their percentiles must not be added. No pure GPU execution timer was collected.

1. **Full projectile recovery creates a periodic encoding spike.**

   **Status: Fixed — pre-sized native writes; protocol and ENet acceptance passed on 18 September 2026.**

   [ProjectilePacketCodec](../src/shared/network/projectile_packet_codec.gd) builds records through many GDScript helper calls and byte appends. [NetworkReplicationScheduler](../src/shared/network/network_replication_scheduler.gd) periodically encodes every active projectile in one tick. The normal rotating partial corrections already reduce average work; the complete recovery remains a burst.

   For 1,024 projectiles, 120 alternating paired samples measured mean full-recovery encoding at **4.762 ms currently versus 1.822 ms** with pre-sized buffers and native integer writes: about **62% less encoding CPU**, or 2.94 ms saved per recovery in this isolated workload. p95 was 5.274 versus 1.931 ms. All paired packet arrays matched byte for byte. Additional mixed flag, signed velocity, clamping, wrap, mine and removal vectors matched too. This is not yet comprehensive protocol regression acceptance.

   A separate combined test ran the real world step plus the real scheduler with 32 stationary human combatants and 1,024 moving projectiles, profiling disabled. Across 360 measured ticks, overall p95 was 13.003 ms, yet **all six complete-recovery ticks exceeded 16.667 ms**; their mean was 17.371 ms and maximum 17.839 ms. This demonstrates why average/p95 alone misses a once-per-second problem. That test excludes inputs, the coordinator, sockets, and rendering, and is a defensive load rather than ordinary gameplay.

   Scheduler-only steady-state payload volume at that ceiling was 61,124 bytes/s per recipient: approximately **1.956 MB/s total (15.65 Mbit/s)** at 32 recipients, before RPC/ENet/IP overhead and active spawn/removal churn. Ordinary visible-run payload rates were approximately 24–33 KB/s with one recipient. Encoding improvements save CPU, not bandwidth.

   Recommended implementation: start with fixed buffer sizing and native writes, preserving the protocol layout, quantization, flags, ordering, and chunk metadata. Keep the shared public player-snapshot body already present. If recovery bursts remain a problem afterward, evaluate spreading delivery of one captured immutable recovery snapshot; mixed-tick chunks must never accidentally delete newer projectiles. Do not begin by lowering correction rates or culling authoritative membership.

   Acceptance: full protocol suite plus byte equality over mixed/random/clamped records, all chunk boundaries, zero/wrapped sequences, reflected ownership, complete recovery interleaved with newer deltas, and real ENet impairment convergence. Repeat combined world/replication timing with the optimized codec.

2. **Ship patterns rebuild transformed vertex arrays during drawing.**

   **Status: Open — instrumented and exploratory prototype measured.**

   [CombatShipView._draw_pattern_polygons](../src/client/presentation/combat_ship_view.gd) loops through each point, calls `_ship_local()`, and appends to a new packed array on every redraw. [ShipPatternGeometry](../src/client/presentation/ship_pattern_geometry.gd) already caches the clipped local shapes; repeatedly regenerating those shapes is not the issue. Their per-frame transformation and submission remain avoidable work.

   The instrumented visible run recorded 46,152 ship draw callbacks costing 4.974 s in aggregate. Pattern drawing accounted for 2.031 s across 42,968 calls: about **47.3 µs per pattern callback**, or **1.02 ms per measured frame** across ships. Pattern time is included in ship draw time; do not add them. CPU time spent submitting draw commands is not GPU execution time.

   A review-only variant draws the cached local polygons under a temporary rotation transform and restores the transform afterward. Its later live run averaged 37.4 µs per pattern callback (about 21% lower). Frame p95 was 17.935 ms versus 19.620 ms in the instrumented baseline, while both medians remained near 17.24 ms. However, draw counts and match trajectories differed, and the tests ran sequentially: this is promising evidence, **not a confirmed whole-game speedup**. The ordinary uninstrumented baseline remains the first table's 18.884 ms p95.

   Recommended implementation: retain local pattern geometry and transform its draw commands or a dedicated child canvas item. Preserve hull clipping, world-space nameplates/markers, shield direction and animation. Consider retained mesh geometry only after measuring whether triangulation/submission remains substantial. Thruster updates and nameplates were much smaller CPU contributors in this run; they are lower-priority targets.

   Acceptance: fixed-replay alternating comparisons and rendered captures of all six patterns across aim angles, local/remote pilots, shields, cloak, high-contrast mode and effects. Check draw-call/batching changes as well as callback CPU. The prototype has not received that visual acceptance.

3. **Client projectile sweeps repeatedly resolve cached geometry.**

   **Status: Fixed — retained per-radius references with map/cover invalidation; acceptance passed on 18 September 2026.**

   [NetworkReplicatedVisuals._step_projectile_visuals](../src/client/network/network_replicated_visuals.gd) supplies an empty geometry override for every collision sweep. [ArenaCollisionSystem._projectile_geometry](../src/shared/arena/arena_collision_system.gd) then normalizes the map, formats a map/radius/hidden-cover key, and looks up an already cached dictionary. The ordinary authoritative path already keeps direct geometry references; the client can use the same principle.

   Across 60 alternating paired batches of 1,024 fixed short sweeps, mean cost was **5.776 ms with lookup versus 2.845 ms with a retained geometry reference**, about 51% less. This is the sweep microbenchmark, not a 51% game speedup. Both paths reported the same hit count. Full per-hit equivalence across dynamic geometry remains an implementation acceptance requirement. The live run had tens of projectiles, not the 1,024 used here, so normal-match savings will be smaller.

   Recommended implementation: cache references by actual projectile radius and current map/cover state outside the per-projectile loop. Invalidate on map changes, destroyed cargo, opening/closing blast doors and session reset. Check the cargo-enabled authoritative branch too: it deliberately reacquires geometry within the loop to handle cover destroyed earlier in the same tick. Preserve that correctness when making its lookup cheaper.

   Acceptance: ricochets and multiple impacts in a tick, each projectile radius/type, map changes, cargo destroyed mid-tick, doors changing state, prediction/recovery, and exact hit fraction/normal comparisons.

4. **Small match-state updates copy unrelated immutable data.**

   **Status: Open — prototype measured.**

   [ClientMatchState.update_fields](../src/client/network/client_match_state.gd) deep-copies the full payload, merges the changed fields, and recursively freezes everything again. This preserves ownership correctly but makes a small objective/status change scale with every player's roster/build data. It is an optimization opportunity in the architecture follow-up, not a reason to abandon immutable observations.

   A 32-player, 16-card-per-player observation occupied 26,944 serialized bytes. Across 600 alternating samples, one objective update averaged **434.5 µs currently versus 13.0 µs** with structural sharing: a shallow root copy plus detached/frozen replacement fields. Median was 402 versus 12 µs. The prototype checked matching resulting values, immunity to later incoming-field mutation, immutable nested builds, and unchanged older observations. No UI subscribers were attached, so this measures publication cost rather than the whole event handler.

   Recommended implementation: reuse unchanged read-only dictionaries/arrays, deep-copy and freeze incoming replacements, then freeze the new root. Batch adjacent updates from one event where possible. Preserve event signals, reset behavior and version rejection. A full `replace()` must still detach externally owned input.

   Acceptance: retained old observations, deep incoming aliases, replaced arrays/dictionaries, objective ordering, nested mutability attempts, build refresh/respawn, and UI invalidation. Keep tests independent of any particular internal copy strategy.

5. **Performance gates need better coverage and separation of timing costs.**

   **Status: Open — measurement gap confirmed.**

   The existing overload gate enables detailed timers inside projectile loops and measures NPC/world work only. Three alternating paired trials measured **13.325 ms mean with profiling off versus 14.471 ms on**, an 8.6% instrumentation overhead in this workload. Ship snapshots matched every tick. The profile is useful for attribution, but its elapsed time should not be presented as uninstrumented shipping cost.

   The full-recovery test above also shows that passing world-only p95 does not establish a complete 60 Hz server budget. The existing live fixture uses a direct bridge rather than `ServerRuntime`, and a standalone world view rather than `ClientMain`; it omits real audio, much of the screen flow, and several production event handlers. The instrumented review variant uses the shared server runtime but still has those client limitations.

   Recommended gate: keep the current overload fixture, add an unprofiled combined simulation/coordination/replication workload, and separately retain detailed attribution runs. Measure full-recovery ticks explicitly, p99/max, and counts over the physics budget. For presentation, record expected FPS and compare against an empty-window control at the same settings. Add deterministic dense-ordnance/effect replays plus an actual ClientMain run with real audio before drawing release-wide conclusions.

Implementation order and limits

Start with packet encoding, client geometry references, and immutable structural sharing: they have narrow boundaries and paired CPU evidence. Then address pattern drawing with visual acceptance. Improve combined timing coverage in the same series so gains are judged against the complete affected operation. Remote interpolation (p95 about 0.77 ms for all remote motion in the visible run) and per-frame UI string rebuilding merit later profiling; the current data does not justify prioritizing them above these findings.

There is no evidence from this review that changing language, rendering backend, reducing NPC intelligence, dropping physics frequency, or replacing the architecture is necessary. No long soak, pure GPU profile, live audio profile, newly packaged release, or native Linux/macOS run was performed. The known root-certificate-store warning occurred; completed measurement scripts reported no unexpected script/engine errors.

Reproduction and retained evidence

Run from the repository root, one workload at a time, with the same external FPS limit and without a competing benchmark. `.tools/godot/Godot_v4.7.2-stable_win64_console.exe` is the local engine used here.

```powershell
& tools/run-performance-benchmark.ps1
& tools/verify-frame-pacing.ps1 -DurationSeconds 45 -ExpectedFps 58
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://src/test/client_presentation_benchmark.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://docs/performance-evidence-2026-09-17/review_probe.gd
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy --resolution 1920x1080 --script res://src/test/live_render_verifier.gd -- --duration=45 --frame-cap=0 --expected-fps=58 --hide-world
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --audio-driver Dummy --resolution 1920x1080 --script res://docs/performance-evidence-2026-09-17/live_profile.gd -- --duration=45 --frame-cap=0 --expected-fps=58
# Repeat the preceding command with --pattern-transform to enable the drawing prototype.
```

[Evidence directory](performance-evidence-2026-09-17/) contains raw results, environment metadata, [aggregated JSON](performance-evidence-2026-09-17/results.json), [server timing windows](performance-evidence-2026-09-17/server-metrics-visible.json), the [paired probe](performance-evidence-2026-09-17/review_probe.gd), [packet prototype](performance-evidence-2026-09-17/packed_codec_prototype.gd), and [instrumented rendered fixture](performance-evidence-2026-09-17/live_profile.gd). The final paired probe completed with `PERF_REVIEW_VALID=true`. These review fixtures are outside the shipping resource roots.
