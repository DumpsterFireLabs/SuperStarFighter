# Mixed-load CPU acceptance

The architecture matrix has two separate jobs: portable functional acceptance and opt-in CPU regression checks on named hardware. Neither uses rendered FPS. The client's 59 FPS cap is independent of the 60 Hz simulation's 16,666.67 microsecond tick budget.

## Workload and coverage

`tests/fixtures/architecture_matrix_cases.json` is shared by the Godot fixture and Python runner. It covers the original five map/mode pairs plus Solar Tide, Wormhole, and Solar Crucible in Hill mode. The three new cases start ships inside their movement fields. Field influence must occur during measurement; Twin Suns and Solar Crucible must also produce active pulse ticks. The manifest preserves coverage of all five game modes.

Each case runs 60 warmup ticks and 480 measured ticks, with 16 simulated humans, 16 NPCs, stacked builds, and 1,024 projectiles before each simulation step. The timed interval includes input submission, NPC decisions, world simulation, match coordination/event draining, and replication scheduling/encoding. Every tick must remain in an active heat. The runner independently rejects missing cases, reduced pilot/projectile load, incomplete samples, inactive required mechanics, engine errors, and nonzero exits.

Projectile refill, pilot refill, periodic flag reset, coverage checks, startup, sockets/RPC transport, and rendering are excluded from the CPU samples. Hazard deaths execute normally; the fixture immediately respawns eliminated pilots before the next measured tick so deaths cannot silently reduce load. This deliberately bypasses the normal respawn delay and is reported as `pilot_refills`. Flag cases return the flag once per second, reporting `flag_resets`, so pickup/carry/navigation execute without captures ending the heat and substituting cheaper idle ticks. Complete captures and match transitions remain covered by separate match-loop acceptance. These are defensive overload measurements, not ordinary-match latency or WAN acceptance.

## Portable functional lane

```powershell
python tools/verify-architecture-matrix.py
python -m unittest discover -s tools -p 'test_*.py'
```

The existing cross-platform CI acceptance command runs the complete manifest automatically. Functional acceptance does not fail merely because CPU timings exceed a budget on a shared runner. Evidence under `.tools/architecture-matrix/<timestamp>/` includes engine logs, summaries, hardware/engine identity, source revision/dirty state, manifest hash, and phase timings.

## Named-hardware CPU lane

The checked-in reference is `tests/fixtures/performance/graphite-i7-10700k-windows.json`. It applies to the named Windows workstation with an Intel Core i7-10700K, 16 logical processors, and the exact Godot version recorded in the file. Close other heavy work and keep power/thermal settings consistent. Run CPU benchmarks sequentially, without concurrent tests or profiling.

```powershell
python tools/verify-architecture-matrix.py --hardware-label graphite-i7-10700k-windows --baseline tests/fixtures/performance/graphite-i7-10700k-windows.json
```

This runs each case three times and compares the median of the three per-run p95 and p99 CPU times. A regression fails when either exceeds the reference by more than 15% or 250 microseconds, whichever allowance is larger. Maximum tick time and ticks above the physics budget remain visible in raw evidence. Passing this relative regression check does not establish zero-overrun 60 Hz operation.

Hardware label, CPU model, logical processor count, OS family, engine version, case manifest, repetition count, and workload signature must match. The signature hashes the fixture and its benchmark helpers, with normalized line endings; changing the workload requires new reviewed evidence. Instrumented or partial runs cannot record or satisfy a baseline. The baseline is never overwritten or loosened automatically.

To establish a reference for another machine or a changed workload, record a new candidate, inspect the evidence, then commit the accepted reference explicitly:

```powershell
python tools/verify-architecture-matrix.py --hardware-label my-test-rig --record-baseline .tools/my-test-rig-candidate.json
```

The stricter `--strict-physics-budget --hardware-label <name>` option requires every measured tick to stay within the 60 Hz budget. This is a separate claim from relative CPU regression acceptance and is not enabled in shared-runner CI.

## Profile before optimizing

```powershell
python tools/verify-architecture-matrix.py --profile --case 6
```

This profiles Wormhole and reports input/NPC/world/coordinator/replication timings, world subphase totals, and projectile/collision attribution. Instrumentation adds overhead; compare its phase proportions, not its elapsed times against the unprofiled reference. Omitting `--case` profiles all cases. No replication or terrain implementation changes are implied by this acceptance work; changes to those systems still need real-client network and impairment checks.

`tools/test_architecture_matrix.py` protects the roster, mechanic activity requirements, full load, error gate, timing/functional separation, repeated baseline capture, hardware/workload matching, regression thresholds, and rejection of profiled or incomplete baseline runs.

## Initial evidence, 2026-10-22

The reference records three passing repetitions of all eight cases on the named i7-10700K workstation. Median per-run p95 CPU times range from 15.63 ms (Dead Freight) to 20.37 ms (Wormhole); Solar Crucible is 20.13 ms. These overload results still exceed the 16.67 ms simulation budget in some cases. They are a reference for detecting regressions, not approval to add more mechanics without measuring their cost.

An independent three-repetition comparison on the same code passed all 24 functional cases but failed the CPU gate for Core Arena, Dead Freight, Switchyard, and Prism Array. For example, Dead Freight's median p99 increased from 17.16 to 20.80 ms, beyond its 19.73 ms limit. The original reference and policy were retained. This is measured local timing variance, not evidence of a code regression or a speedup. The workstation reference is initial evidence; a controlled, idle hardware run is still needed before treating it as a stable release gate. Shared-runner CI remains functional-only.

A separate instrumented Wormhole run attributed about 92% of measured world time to projectile processing (15.19 ms per measured tick on average, including instrumentation). Movement averaged 0.99 ms and overlap handling 0.39 ms. All 480 measured ticks included ships within the gravity field; 56 fixture respawns kept 32 pilots present before every step. Projectile processing remains the next profiling/optimization target. This change makes no simulation optimization or speedup claim.
