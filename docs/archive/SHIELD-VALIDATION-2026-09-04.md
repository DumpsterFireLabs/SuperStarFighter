# Shield timing validation — 4 September 2026

The implementation preserves sampled taps and release/re-press transitions, sends shield changes reliably, and retains the latest press identity in ordinary input for 15 sampled ticks. Authority consumes each identity once; recipient corrections preserve that identity during replay. Old input cannot override a newer sequence. A recovered released tap gets one authoritative tick, while duplicates cannot extend it or reopen a consumed Perfect Guard.

Local activation and the guard-window highlight follow prediction immediately. Block/break confirmation remains authoritative. Floating-point residue and snapshot rounding no longer add a guard tick at the 250 ms deadline. The guard timer uses 1/60000-second packet units, sufficient to preserve the 60 Hz timing steps.

Base balance is unchanged: 120-degree coverage, 100 energy, 20 energy/second held drain, 25 energy per ordinary block, and a first-hit Perfect Guard cost of 5. The depleting impact still blocks; recovery requires the existing delay and unlock threshold. Only the first impact of a three-shot volley receives the discount.

## Validation

- Final unit suite: **6,292 assertions passed**. Includes production input sampling, codecs, sequence wrap, authority/replay agreement, exact guard deadlines, coalesced re-presses, duplicate suppression, depletion lock, three simultaneous hits, and seeded input-fault schedules.
- Shield-only real ENet matrix: **21/21 passed**, seven profiles across seeds 230926–230928. All 42 delivered tap probes blocked their three-shot volleys for exactly 55 energy, followed by shield-state convergence. Evidence: `.tools/network-impairment/20260904T231154-9f9de11b/`.
- After the final guard-timer encoding adjustment, combined faults were repeated successfully on seed 230927: `.tools/network-impairment/20260904T231608-82718f39/`.
- Network handshake/lobby/replication and hardening gates passed. The hardening bot exercises malformed and excessive traffic on both reliable shield input and ordinary input. Match-loop verification also passed during the change.

Commands: `tools/run-tests.ps1`, `tools/verify-network.ps1`, `tools/verify-hardening.ps1`, `tools/verify-match-loop.ps1`, and `python tools/verify-network-impairment.py --shield-only --seeds 3`.

## Limits and remaining issue

The shield-only matrix is explicitly scoped and does not replace general gameplay/network acceptance. A general combined-fault run on seed 230927 missed the mine activation in phase 4 before reaching shield probes; this remains a separate ability-delivery issue. Its failed log is retained at `.tools/network-impairment/20260904T230626-bd141c8d/seed-230927/combined.log`.

Measured tap-to-authority delivery in the shield matrix was 13–28 ms on unmodified loopback, 76–151 ms with injected latency/jitter, and 55–752 ms under combined faults including a blackout (six taps per listed profile). These are fixture observations, not LAN hardware or human reaction acceptance. The 250 ms retention bounds redundant client input; reliable transport can deliver later during an outage unless newer input has superseded it. There is no collision rewind or lag compensation. Human LAN playtesting, controller hardware timing, and shield-versus-multishot balance remain separate work.

Both endpoints require compatibility version **33**, binary packet version **14**. Input packets are 25 bytes; a full 32-player snapshot is 1,191 bytes, below the existing 1,200-byte budget.
