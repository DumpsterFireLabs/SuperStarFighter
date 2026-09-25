# Cached projectile meshes — 2026-09-22

Dense projectile drawing now combines each projectile's static primitives into an immutable textured mesh. Ordinary shots, beams, missile bodies/trails and mine bodies/spokes reuse their geometry; mine pulses and team markers retain their existing draw paths. Batching stays within each projectile, preserving registry order and transparency order between projectiles. Sparse scenes, compact friendly effects and stationary non-mine projectiles retain the original path.

Meshes include color, radius, weapon family and mine armed state in their identity. The cache is capped at 128 entries so changing builds cannot grow it indefinitely. The existing radial texture supplies both disc edges and opaque solid geometry. Missile outlines use three explicit stroke quads; their corner rasterization can differ slightly from the old polyline join.

Same-machine A/B results, with no competing benchmark, for 600 measured frames after 60 warmup frames:

| CPU draw callback | Before p95 | After p95 |
| --- | ---: | ---: |
| Projectile layer | 9.031 ms | 6.270 ms |
| Sum of ship/projectile/effect callbacks | 14.093 ms | 11.597 ms |

Projectile callback p95 fell **30.6%**. Both runs drew all 1,024 projectiles and retained SHA-256 `a0d148c29c2bc069806415ef4cb50755b8eef7eafc1a04b85ce6caa127a33094`. Captured frames were visually inspected for weapon identity, directional trails and mine rings. Geometry tests cover cache reuse, color/radius separation, arming, trail dimensions and the cache bound; existing team readability tests also pass.

These numbers measure CPU command submission only, including warm-cache lookup. They exclude engine traversal, GPU execution, presentation waits, simulation and networking, and do not predict FPS on this capped machine. The first appearance of a new style still builds a mesh. The original rendering path remains available to the attribution fixture with `-- --legacy-projectiles` for repeatable comparisons. Structured measurements are in `projectile-mesh-evidence-2026-09-22.json`.
