# Connection and lobby ownership — 2026-09-04

This addresses the remaining connection/lobby architecture item from the [comprehensive review](COMPREHENSIVE-REVIEW-2026-09-04.md), following the settings/standings cleanup. The client root no longer supplies itself to the connection controller or manipulates its lobby controls. The connection UI receives the bridge and theme, publishes navigation signals, and exposes methods for visibility, focus, recovery and session transitions.

Ownership is now divided by responsibility:

| Owner | Responsibility |
| --- | --- |
| `client_main.gd` | Cross-screen navigation, gameplay activation and match presentation |
| `connection_controller.gd` | Join/host forms, LAN browser, connection validation and recovery |
| `lobby_screen_controller.gd` | Roster, readiness, match rules, appearance and modal focus |
| `hosted_session.gd` | Embedded server subtree, isolated multiplayer registration, startup and teardown |
| `connection_preferences.gd` | Existing credential/appearance persistence boundary |
| `match_preset_controls.gd` | Shared preset picker and explanatory text for both forms |

The connection controller drops from 1,441 lines to approximately 600. Lobby controls move to their actual owner, with production callers and fixtures migrated instead of retaining forwarding properties. The shared canvas remains an explicit integration point for settings, draft, standings and other overlays. This completes this connection/lobby boundary; broader client-root match orchestration remains its own responsibility.

Two lifecycle defects are covered alongside the extraction. A roster update now preserves an open appearance/options modal and keeps the roster beneath it hidden, including pending appearance edits. Hiding or resetting the session closes both modals before they can restore lobby visibility. Embedded-host shutdown now removes the custom multiplayer registration as well as stopping the server and freeing its nodes; startup failure retains the diagnostic and cleans up its partial runtime. Repeated shutdown and freeing an active host are covered.

The host retains the `Main/NetworkBridge` RPC path beneath its isolated multiplayer root. Direct connections continue to pass the selected address and port to the existing transport. Combat simulation, shield timing, network protocol, the system's 58 FPS cap and intended screen layouts are unchanged. The Beta 10 artifacts already delivered remain the earlier build; this source change needs a subsequent build to be distributed.

Validation: **7,329 assertions passed**, including 28 new independent connection/lobby and host-lifecycle assertions. The full foundation gate passed **190 checks**, including all script parses, startup paths, the expected failing-test exit path and nine verification-gate acceptance cases. The exact Windows certificate-store diagnostic remains the existing allowed environment error; no unexpected engine errors were accepted.

`tools/verify-local-host.ps1` passed admission, LAN discovery, authoritative Ready/round-setting updates, teardown and reconnect on the same client. It also verifies that the custom multiplayer registration disappears after disconnect. The production presentation sequence completed at **1280×720 and 5120×1440** with strict exit/error/completion checks. The 720p host form, 32-pilot lobby and appearance picker, plus ultrawide match options, were visually inspected. These are local integration checks, not a new real-internet latency or performance benchmark.

The shipping resource allowlists include all three new production scripts. [Validation markers](connection-lobby-evidence-2026-09-04/validation.txt) and selected captures are retained in [connection-lobby-evidence-2026-09-04](connection-lobby-evidence-2026-09-04).
