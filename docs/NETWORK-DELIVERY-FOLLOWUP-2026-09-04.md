# F5 follow-up: ability input delivery

The retained failed shield-audit run missed a mine activation under combined faults. New diagnostics distinguish the sampled press/slot, remaining retries, consumed identity and server acknowledgment. Three diagnostic retries passed, but seed 230927 still showed sampled mine and missile presses unconsumed after one second. The original failure is intermittent; these observations support delivery vulnerability under throttling, not a claim that every run with that seed fails.

Ability edges now share the reliable input RPC with shield edges. Ordinary 30 Hz samples retain the existing bounded retry identity; consumption corrections stop retries. A simultaneous ability/shield change produces one packet. Both RPC paths share admission, codec, rate and sequence validation, and authoritative identities prevent double spending. Compatibility version 34 requires matching endpoints; the binary packet layout stays at version 14.

Validation:

- 6,308 unit assertions passed, including sampled activation of all four abilities with all ordinary packets discarded, codec round trips and duplicate suppression.
- Full real ENet fault matrix: **21/21 passed**, seven profiles across three seeds. Each run requires all selected abilities to spend exactly one charge where applicable, shield tap/volley coverage and final resource/replay convergence. Evidence: `.tools/network-impairment/20260904T232608-1ca308e1/`.
- Hardening passed with malformed/excessive traffic exercising both input paths and healthy peers continuing.
- Diagnostic pre-change evidence: `.tools/network-impairment/20260904T232353-d8361339/`. The original failed log remains in `.tools/network-impairment/20260904T230626-bd141c8d/seed-230927/combined.log`.

This closes the observed acceptance gap for the exercised fault matrix. A client retry deadline cannot cancel a reliable datagram already in transit; a long outage can delay an action unless newer input supersedes it. No lag compensation, extended soak or physical-LAN latency sign-off is claimed.
