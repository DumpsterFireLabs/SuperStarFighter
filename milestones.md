# Super Star Fighter — Implementation Milestones

**Source of truth:** [Vertical slice specification](./spec.md)  
**Product direction:** [Product plan](./plan.md)

These milestones are ordered by dependency. Work may be prototyped ahead, but a milestone is not complete until its exit gate passes. Each gate should be recorded in the commit or handoff that completes the milestone, including the commands run and any known deviations.

## Status Summary

| Milestone | Status | Evidence |
| --- | --- | --- |
| 0 — Repository and Toolchain | Complete | Godot 4.7.2 verified; 7 scripts parsed; 4 startup modes exercised; 29 tests passed; forced-failure exit verified. |
| 1 — Shared Rules, Cards, and Match Model | Complete | 16 card resources validated; deterministic stats, draft, and scoring/state-machine rules covered; 345 assertions passed; forced-failure exit verified. |
| 2 — Offline Combat Sandbox | Complete | Final-size arena and combat lab operational; 32 spawns validated; 15-minute accelerated lifecycle soak passed; 427 assertions and 43 project checks passed. |
| 2.1 — Ship-Relative Flight and Custom Crosshair | Complete | Transformed screen-relative WASD into aim-relative forward/reverse/strafe controls at every heading; replaced the system cursor during combat with a neon crosshair; movement-basis and input-contract regressions passed within the 427-assertion, 43-check foundation gate. |
| 3 — Authoritative Networking and Lobby | Complete | Real ENet clients verified across three channels; rejection, lobby authority, prediction/interpolation, snapshots, projectiles, leader transfer, late spectator, and clean shutdown passed; 602 assertions and 61 project checks passed. |
| 3.1 — Arena Edge, Overtime, and Reconnect Recovery | Complete | Prevented wall-adjacent muzzles from firing through collision, made overtime reset restore the full heat clock, and cleared prediction/session visuals while recentering disconnected clients; focused combat/network regressions passed within the 602-assertion, 61-check gate. |
| 4 — Complete Multiplayer Match Loop | Complete | Authoritative draft-to-rematch loop verified over real ENet; rendered five-card choice, last-survivor resolution, configurable 2–32 seats, server NPC fill, solo NPC-assisted start, timeout, ties, extended rounds, forfeit, reset, and second match covered; 730 assertions and 65 project checks passed. |
| 4.1 — Extreme Stacking and Playable Five-Card Drafts | Complete | Removed narrow balance caps in favor of compound build escalation, rendered private five-card choices, retained authoritative selection/timeout behavior, and covered the client presentation path; 704 assertions and 64 project checks passed. |
| 4.2 — Configurable NPC-Filled Lobbies | Complete | Added leader-owned 2–32 seat limits, optional server NPC fill, human seat replacement, NPC drafting/combat, solo NPC-assisted launch, and a real lobby verifier; 730 assertions and 65 project checks passed. |
| 4.3 — Heat Recenter and Interface Readability | Complete | Snapped the camera to the local ship at every heat start, enlarged lobby/game controls, increased draft-card opacity, and standardized the draft timer at 30 seconds; 744 assertions and 65 project checks passed. |
| 5 — Production UI, Neon Presentation, and Audio | Complete | Eight production screen states rendered at 1280×720 and 1920×1080; 32-player roster, neon identity/effects, off-screen threats, synchronized cues, optional MP3 pipeline, synthesized placeholders, and clean two-match reset verified; 780 assertions and 71 project checks passed. |
| 6 — Validation, Diagnostics, and 32-Client Hardening | Complete | Malformed/excessive peers isolated; bounded JSON metrics and configurable smoke/soak tooling verified; 794 assertions and 72 project checks passed; 32-client, 600-second soak completed 65 windows with 10.678 ms worst-window p95, zero orphan nodes, bounded entities, overtime, combat disconnect, late spectator, and clean shutdown. |
| 6.1 — Audio, Screen Flow, Card Expansion, and Draft Balance | Complete | Supplied menu/gameplay music discovered across WAV/OGG/MP3 names with smooth menu looping; persistent volume settings, animated splash, in-match Escape menu, aligned combat-focused menu copy, and victory screen rendered; catalog expanded to 36 rarity-weighted cards with authoritative beam weapons, rarity-colored cards, and round-winner draft byes; 980 assertions and 22 production-screen captures passed. |
| 6.2 — Five-Dozen Catalog and Viewport Reclamation | Complete | Catalog expanded to exactly 60 authoritative cards across seven steeply weighted rarity tiers; match state folded into a 430×148 upper-left combat HUD; selectable 720p, 900p, 1080p, and 1440p window resolutions persist alongside audio settings; 1,148 assertions and 22 production-screen captures passed. |
| 6.3 — Ultrawide and Victory Presentation | Complete | Added 2560×1080 and 3440×1440 expand-aspect modes; rebuilt victory as a champion plate with aligned, highlighted, scrollable standings rows and clean build wrapping; corrected the capture harness to assert real framebuffer dimensions; 1,154 assertions and 44 production-screen captures passed. |
| 6.4 — Intro and Round Pacing | Complete | Splash accepts any key immediately and retains a ten-second automatic fallback; authoritative round-result intermission shortened from four seconds to 2.5 seconds while heat results remain unchanged; 1,158 assertions passed. |
| 6.5 — Ready-Up Lobby and Renderer Re-entry | Complete | Added authoritative ready/not-ready state, leader-only ejection, contextual launch wording, individual 32-player roster controls, and a centered non-gameplay lobby; preserved local render identity when entering combat from the hidden lobby; 1,182 assertions passed. |
| 6.6 — Unlimited-Stack UX, Momentary Scoreboard, and Explicit Results Exit | Complete | Removed all remaining card stack caps and redundant no-limit labels, changed the live scoreboard to polished hold/release behavior, and replaced automatic result expiry with a leader-authorized Exit to Lobby transition; 1,150 assertions, 73 project checks, the two-match loop, and 44 production-screen captures passed. |
| 6.7 — Beam Rarity Balance and Thruster Particles | Complete | Raised every beam-conversion card to Epic or above, including two-tier jumps for the earliest beam unlocks; added bounded speed-responsive color-matched thruster particles for forward, reverse, and strafe motion; 1,159 assertions, 73 project checks, and 44 production-screen captures passed. |
| 6.8 — Per-NPC Difficulty Profiles | Complete | NPC fill now creates configurable waiting pilots immediately; each row exposes leader-only Passive, Easy, Neutral, Skilled, and Insane settings backed by authoritative monotonic reaction, aim, awareness, movement, firing, shielding, and target-leading profiles with no stat cheats; 1,193 assertions, 73 project checks, the real NPC lobby flow, and 52 production-screen captures passed. |
| 6.9 — Decisive Victory Flow and Build Inspection | Complete | Final rounds skip the redundant round-result cooldown; victory standings render every owned card as a rarity-colored hover target with exact per-stack and compounded statistics; 1,197 assertions, 73 project checks, the real two-match loop, and 52 production-screen captures passed. |
| 6.10 — One-Click Hosting and LAN Discovery | Complete | Added an isolated in-process authority with loopback join, bounded subnet discovery and a populated browser, direct-connect fallback, protocol compatibility and live occupancy/state details; 1,218 assertions, 76 project checks, a real host/admission/discovery lifecycle, and 56 production-screen captures passed. |
| 6.11 — Heat Pacing, Launch Alerts, and Rematch Rendering | Complete | Reduced heat-result and non-final round-result intermissions to two seconds; added centered READY/BEGIN alerts to every heat; separated match-visual cleanup from connection identity so same-lobby rematches recreate the local predicted ship correctly; 1,228 assertions, 76 project checks, the real two-match loop, and 64 production-screen captures passed. |
| 6.12 — Rematch Input Continuity and Twelve-Dozen Catalog | Complete | Preserved monotonic client input sequence/tick state through same-connection lobby resets so rematch movement remains server-accepted; tightened BEGIN to a 0.10-second pre-roll plus fading 0.10-second post-roll; audited and differentiated the prior catalog, expanded it to 120 unlimited-stack cards, and grew the numeric modifier surface from 18 to 24 stats; 1,509 assertions, 76 project checks, the real two-match/host loop, and 64 production-screen captures passed. |
| 6.13 — Overtime-Aware NPC Navigation | Complete | NPCs prioritize authoritative overtime safety, suppress fire through blocked sightlines, and deterministically break symmetric cover stalls with difficulty-scaled hold/flank roles; 1,515 assertions, 76 project checks, the real NPC lobby flow, and the two-match loop passed. |
| 6.14 — Configurable Controller and Joystick Input | Complete | Added persistent keyboard/mouse and controller profiles, complete per-action rebinding, analog twin-stick aim, arbitrary joystick-axis capture, controller menu/draft/spectator navigation, deadzone tuning, device status, and profile-specific defaults; 1,556 assertions, 78 project checks, and 68 production-screen captures passed. |
| 6.15 — Fullscreen and Super-Ultrawide Display Modes | Complete | Added persistent Windowed, desktop-native Borderless Fullscreen, and selected-resolution Exclusive Fullscreen modes; expanded the display list to fifteen 16:9, 16:10, 21:9, and 32:9 choices through 5120×2160; verified 5120×1440 gameplay and settings composition; 1,562 assertions, 78 project checks, and 90 production-screen captures passed. |
| 6.16 — Persistent NPC Cover-Loop Breakouts | Complete | Added per-NPC/target/obstacle blocked-engagement memory, three-second opposite-side breakouts, sub-second sightline-flicker tolerance, and sustained-clear reset behavior for both cover islands and the central obstacle; 1,569 assertions, 78 project checks, and the real NPC lobby/combat flow passed. |
| 6.17 — Multi-Shot Projectile Reconciliation | Complete | Reconciled every predicted pellet in a shared shot sequence instead of retaining collisionless extra visuals; verified Scatter Array creates three authoritative projectiles, removes the full predicted volley, and collides every pellet with arena barriers; 1,575 assertions, 78 project checks, and the real network/match flows passed. |
| 6.18 — Card Rarity Rebalance and Visual Build Inspection | Complete | Rebalanced all seven offer-slot weights, raising the five-card Epic-or-better chance to about 50.2%; audited all 120 cards and corrected five mismatched tiers; replaced scoreboard and victory stat text boxes with rarity-styled card previews showing exact per-stack and compounded effects; 1,585 assertions, 79 project checks, and 100 production-screen captures passed. |
| 6.19 — Full-Arena NPC Pursuit, Contact Recovery, and Flight UX | Complete | Extended every NPC profile to full-arena acquisition; added close-contact disengagement and deterministic authoritative ship separation; added an in-world ammo/reload display, authoritative remappable manual reload, and persistent Newtonian/Relative flight modes; protocol 8, 1,666 assertions, 79 project checks, real ENet/NPC flows, and 180 production captures passed. |
| 6.20 — Lobby Powerups, Shield-Ram Builds, and Ship Colours | Complete | Added a default-off leader option for authoritative twenty-second Rare-or-better arena card spawns with safe placement, collection, inventory, immediate stat application, late-join state, and NPC pickup support; added five audited Rare-through-Unobtanium shield-ram cards; added persistent per-human Random or HSV-wheel ship colours with lobby swatches; protocol 9, 1,740 assertions, 81 project checks, real ENet/NPC/match-loop flows, and 186 production captures passed. |
| 6.21 — Contact Escape, Full NPC Health, and Unified Card Hovers | Complete | Reworked authoritative ship separation to transfer wall/cover-blocked correction and apply stronger escape impulses through rapid shield/fire transitions; fixed remote health rings to use each pilot's derived maximum; removed reset heat wins from victory standings; reused the rarity-styled graphical build preview for draft choices; 1,753 assertions, 81 project checks, real ENet/NPC/match-loop flows, and 192 production captures passed. |
| 6.22 — Roster-Integrated Ship Colour Picker | Complete | Replaced the separate ship-colour option with clickable per-player roster swatches; each human can edit only their own swatch through an HSV wheel with pending preview, explicit Apply, Cancel, and Random actions; verified host/non-host ownership and all six display targets; 1,762 assertions, 81 project checks, and 198 production captures passed. |
| 6.23 — Whole-Volley Ricochet Fidelity | Complete | Replaced endpoint-only arena checks with swept wall, rectangle, and circle collision so fast and near-tangent projectiles cannot tunnel; applied the same immediate rebound simulation to every predicted and authoritative client visual, including beams that expire before the 5 Hz correction interval; synchronized all traversal budgets during corrections; 1,769 assertions, 81 project checks, real ENet/match-loop flows, and 198 production captures passed. |
| 6.24 — Match Rules, Active Cards, and Combat Records | Complete | Added a bulk NPC-difficulty selector; configurable 5–90 second arena-drop timing, heat-only/match-long drop ownership, and 30–120 second overtime; authoritative match-total kills on live/final standings; Afterburner special input and exhaust bloom; Ramming Shields, two knockback weapons with reduced shield push, and Nosferatu Shield healing; hid internal spawns and inactive ships during initial drafts; protocol 10, 1,853 assertions, 81 project checks, real network/match/NPC/hardening gates, and 198 production captures passed. |
| 6.25 — Reliable Contact Combat and Elite NPC Tactics | Complete | Made shield-up rams trigger at practical Ramming Shields speeds without an aim-arc dependency; preserved projectile travel after ricochets and pierces so same-tick rebound hits deal damage; added deterministic legal-position recovery for pinned pairs/clusters plus client-side contact exclusion; upgraded Skilled and Insane pilots with travel-time leading, incoming-projectile evasion, reactive shielding, pressure, and committed flanks; 1,869 assertions, 81 project checks, and real network/match/NPC/hardening flows passed. |
| 6.26 — Selectable Elimination and Objective Modes | Complete | Added lobby-selectable Death Match, Team Death Match, King of the Hill, Capture the Flag, and Team Capture the Flag; deterministic balanced Cyan/Magenta teams, opposing-side spawns, friendly-fire exclusion, team scoring/byes/results, 20-second uncontested hill control, map-safe neutral flag/extraction/base zones, carrier drop/reset/capture rules, objective-aware NPC steering, and live arena/HUD presentation; protocol 11, 1,947 assertions, 82 project checks, real network/match/NPC/hardening flows, and 198 production captures passed. |
| 6.27 — Configurable Multi-Team Lobbies | Complete | Expanded Team Death Match to 2–8 host-configured teams; added Auto or explicit per-row team dropdowns with host/self/NPC authority, deterministic least-populated balancing, populated-team launch validation, generalized scoring, and team-sector spawns; retained two-team Capture the Flag bases; protocol 13 and 2,018 assertions passed. |
| 7 — Export, Documentation, and Release Candidate | In Progress | Documentation and verified Beta 1, Beta 2, and Beta 3 Windows client packages are complete; dedicated-server export, clean-machine acceptance, release-mode soak, code signing, and final release-candidate validation remain. |
| 7.1 — Complete Documentation Suite | Complete | Rebuilt the repository README and added a full player/host manual, contributor/development guide, documentation index, architecture and network diagrams, hosting guidance, troubleshooting, card/audio authoring, and verification matrix. |
| 7.2 — Windows Beta 1 Client Package | Complete | Pinned and displayed version 0.1.0-beta.1; added 2880×1920 as the sixteenth display mode; rebuilt a 127,516,408-byte embedded-PCK Windows x64 client with protocol 8, verified version metadata, rendered startup, and all six authored music tracks discovered; packaged a 57,045,256-byte friend ZIP with instructions and Godot notices; 1,666 assertions, 79 project checks, and 180 production captures passed. |
| 7.3 — Windows Beta 2 Client Package | Complete | Advanced the visible/package identity to 0.1.0-beta.2 without replacing Beta 1, then reissued Beta 2 with the roster-integrated colour picker; exported a 127,556,096-byte embedded-PCK Windows x64 client with protocol 9 and verified 0.1.0.2 file/product metadata; packaged a 57,080,057-byte friend ZIP with updated instructions and notices; 1,762 assertions, 81 project checks, 198 production captures, rendered startup, and all six authored music tracks passed. |
| 7.4 — Windows Beta 3 Client Package | Complete | Advanced the visible/package identity to 0.1.0-beta.3 without replacing Beta 1 or Beta 2; exported a 127,585,272-byte embedded-PCK Windows x64 client with protocol 10 and verified 0.1.0.3 file/product metadata; packaged a 57,103,773-byte friend ZIP containing only the client, instructions, and notices; 1,853 assertions, 81 project checks, rendered startup, and all six authored music tracks passed. |
| 8 — Ten-Map Expansion | In Progress | The static ten-map roster and automatic round rotation are playable; advanced per-map mechanics, optional rotation controls, full-capacity map simulations, and the rotating-map soak remain. |
| 8.1 — Static Ten-Map Roster and Per-Round Rotation | Complete | Added ten visually distinct static topologies with 32 validated spawns each; a seeded shuffled deck changes maps only after a round is won and retains the same map through all heats and ties; authoritative collision, projectiles, overtime, NPC behavior, client reconstruction, HUD names, and protocol state are synchronized; 1,629 assertions, 79 project checks, real network/match-loop gates, and 150 production captures passed. |

## Completion Rules

- Implement against `spec.md`; do not silently resolve conflicts in code.
- Keep the project runnable at every milestone boundary.
- Add automated coverage with the behavior it protects, not in a later cleanup pass.
- Treat warnings, orphaned nodes, leaked ENet peers, parser errors, and unhandled runtime errors as failures.
- Do not begin presentation polish until the corresponding authoritative gameplay path works.
- Generated exports and local Godot binaries stay out of Git.
- Increment the visible build/release version before every tester-facing export; never replace a shared package under the same version label.
- A deliberate spec change updates `spec.md`, affected tests, and this milestone document in the same change.

## Major Delivery Ledger

This ledger maps the major delivered increments to their local commits. Small corrective commits are grouped with the feature whose acceptance contract they completed.

| Record | Major delivery | Local commit(s) |
| --- | --- | --- |
| 0–1 | Deterministic Godot foundation, shared card/stat rules, draft domain, and match state machine | `9be7c6a` |
| 2 | Final-size offline combat sandbox, arena collision, shields, projectiles, overtime, and lifecycle soak | `aff3a74` |
| 2.1 | Aim-relative flight controls and custom combat crosshair | `822f1c5` |
| 3 | Authoritative ENet networking, lobby authority, prediction, interpolation, and projectile replication | `96ae0da` |
| 3.1 | Wall-safe firing, full overtime reset, reconnect cleanup, and camera recentering | `e1d126a` |
| 4 | Full authoritative lobby-to-draft-to-victory-to-rematch match loop | `b10abaa` |
| 4.1 | Compound card escalation and rendered private five-card drafts | `27c3be6` |
| 4.2 | Configurable NPC-filled 2–32-player lobbies and solo NPC-assisted launch | `8dc41e0` |
| 4.3 | Heat-start camera centering, enlarged interface, opaque cards, and 30-second draft presentation | `f5ecfa6` |
| 5 | Production neon UI, combat effects, audio pipeline, spectator/results presentation, and capture harness | `3b11741` |
| 6 | Validation hardening, diagnostics, scripted clients, and successful 32-client soak | `75b5b39` |
| 6.1 | Music/settings/splash/Escape/victory flow, 36-card rarity catalog, beam weapons, menu language, smooth looping, rarity presentation, and winner draft byes | `184b57b`, `419df33`, `1885b75` |
| 6.2 | Sixty-card seven-tier catalog, compact combat HUD, and four standard resolution choices | `4435b98` |
| 6.3 | Ultrawide resolutions and rebuilt champion/standings victory presentation | `dc320ee` |
| 6.4 | Immediate key-driven splash advance with ten-second fallback and shorter round intermission | `5e88740` |
| 6.5 | Human ready-up, leader ejection, hidden waiting arena, contextual start controls, and lobby-to-game renderer recovery | `45955af`, `ee3f5b7` |
| 6.6 | Unlimited card stacks, cleaned card copy, momentary scoreboard, and explicit results exit | `b39d04d`, `4f194e1` |
| 6.7 | Higher beam rarities and speed-responsive thruster particles | `9d03673` |
| 6.8 | Passive/Easy/Neutral/Skilled/Insane per-NPC difficulty controls and authoritative behavior profiles | `c4b9e07` |
| 6.9 | Immediate final victory transition and hoverable final-build stat inspection | `5c0b8ab` |
| 6.10 | One-click in-process hosting, UDP LAN discovery, server browser, and direct-connect fallback | `af256d3` |
| 6.11 | Two-second heat pacing, READY/BEGIN plates, and same-lobby rematch rendering repair | `b1de340` |
| 6.12 | 0.10-second BEGIN timing, monotonic rematch input continuity, 120 differentiated cards, and 24 numeric modifier axes | `988589a` |
| 6.13 | Overtime-aware NPC safety, obstacle sightlines, and deterministic anti-stalemate flanking | `6afd085` |
| 6.14 | Persistent keyboard/mouse and controller profiles, complete input remapping, analog twin-stick controls, axis capture, and deadzone settings | `5ae6a6c` |
| 6.15 | Windowed, borderless, and exclusive fullscreen modes plus fifteen standard, ultrawide, and 32:9 resolution choices | `abff99e` |
| 6.16 | Persistent blocked-engagement detection and opposite-side NPC cover-loop breakouts | `4a38697` |
| 6.17 | Whole-volley predicted projectile reconciliation and barrier collision for every Scatter Array pellet | `5c53e38` |
| 6.18 | Seven-tier offer rebalance, complete 120-card rarity audit, five corrected tiers, and rarity-styled build-card previews | `701dcb8` |
| 7.1 | Complete repository README, player/host manual, contributor guide, documentation index, and troubleshooting/reference suite | `5833b04` |
| 7.2 | Beta 1 version identity, 2880×1920 mode, Windows client export preset, repeatable verified package pipeline, and friend ZIP | `c1a932a` |
| 8 plan | Ten-map roster, map-data architecture, dynamic mechanic boundaries, and 320-spawn acceptance contract | `5ea2fe9` |
| 8.1 | Ten static arenas, seeded no-repeat per-round rotation, authoritative geometry/state synchronization, map-aware NPCs, and full presentation coverage | `fbf7d27` |

## Milestone 0 — Repository and Toolchain

**Status:** Complete — 2026-08-23  
**Outcome:** A reproducible Godot project skeleton that can start in client, server, and test modes.

### Work

- Initialize Git and add a Godot-focused `.gitignore`, excluding `.godot/`, local tools, logs, and `builds/`.
- Bootstrap the official portable Godot 4.7.2 Standard executable and matching export templates outside tracked source.
- Create `project.godot`, the directory structure defined by the specification, the 60 Hz physics setting, display defaults, and named input actions.
- Add a startup dispatcher that recognizes client, `--server`, `--bot-client`, and `--run-tests` modes without loading client visuals in server mode.
- Add typed shared constants for protocol version, default port, maximum players, and gameplay tick rates.
- Add PowerShell entry scripts for launching the editor, running tests, starting a local server, and starting a client.
- Add a minimal headless test runner that aggregates failures and returns a nonzero process exit code.

### Verification

- Start the project normally and reach a placeholder client scene.
- Start with `--server` and reach a headless placeholder server loop without a window.
- Run `--run-tests` with one sample passing test and verify exit code 0; add a temporary failing assertion and verify a nonzero exit before removing it.
- Confirm Git status does not include Godot imports, local binaries, logs, or builds.

### Exit Gate

- Client, headless server, and test entry paths all run from documented commands on a clean checkout after tool bootstrap.
- No parser errors, missing-resource errors, or tracked generated artifacts remain.

## Milestone 1 — Shared Rules, Cards, and Match Model

**Status:** Complete — 2026-08-23  
**Outcome:** Gameplay values and match decisions exist as deterministic, UI-independent shared code.

### Work

- Implement typed `MatchConfig`, `PlayerInputFrame`, `CardDefinition`, derived combat stats, player match state, score state, and state-machine enums.
- Implement the canonical stat evaluation pipeline: flat additions, compound multipliers, special integer additions, then clamps.
- Create all 16 card resources with the exact IDs, effects, descriptions, categories, and caps from `spec.md`.
- Implement seeded card-offer generation, offer tokens, eligibility, timeout selection, simultaneous application, and build-complete behavior.
- Implement the match state machine as a server-oriented domain object independent of rendering and ENet.
- Cover the heat, round, match, tie, forfeit, draft, and reset rules with deterministic unit tests.

### Verification

- Run table-driven tests for every card at one stack and maximum stacks.
- Acquire the same card set in several orders and assert identical derived values.
- Simulate a multiplayer round in which three different players win early heats and a later player reaches two wins.
- Simulate draft timeout, unlimited repeat stacking beyond former caps, five-card uniqueness, and fixed-seed offer reproduction.

### Exit Gate

- All stat, card, scoring, draft, and state-transition tests pass headlessly.
- No gameplay constant used by these systems is duplicated in UI or networking code.

## Milestone 2 — Offline Combat Sandbox

**Status:** Complete — 2026-08-24
**Outcome:** One local player can move, aim, shoot, shield, take damage, die, and experience overtime in the final arena geometry.

### Work

- Build the 3200×1800 arena, symmetric obstacles, collision layers, 32 validated spawn anchors, and overtime boundary.
- Implement shared movement math and a server-compatible ship controller with acceleration, drag, collision slide, ship-relative forward/reverse/strafe input, independent mouse aim, and a custom combat crosshair.
- Implement ammunition, automatic reload, fire cadence, projectile lifetime, owner immunity, pierce, ricochet, and active-projectile limits.
- Implement directional shield angle testing, drain, block cost, depletion lockout, regeneration delay, and firing/acceleration restrictions.
- Implement damage ordering, Auto-Repair, death, projectile cleanup, spawn reset, and simultaneous-death reporting.
- Add the follow camera, arena clamping, local-player marker, and a debug combat HUD.
- Provide a local sandbox scene with controllable debug targets and keys to grant specific card stacks.

### Verification

- Unit-test movement normalization, cooldown/reload timing, shield boundary angles, shield depletion, pierce, ricochet, repair interruption, overtime damage, and projectile caps.
- Manually verify direct and diagonal movement, aiming at all angles, wall/ship collision, every projectile modifier, and every shield modifier.
- Run the sandbox for 15 minutes while repeatedly spawning and destroying projectiles; entity counts must return to baseline.

### Exit Gate

- Base combat and all 16 cards produce the specified observable effects in the local sandbox.
- Combat tests pass and the sandbox produces no orphan, leak, or runtime-error warnings.

## Milestone 3 — Authoritative Networking and Lobby

**Status:** Complete — 2026-08-24  
**Outcome:** Multiple clients can connect to a dedicated server, enter a lobby, and control server-owned ships with prediction and interpolation.

### Work

- Implement ENet server/client startup, bounded command-line parsing, binding errors, shutdown, and the three protocol channels.
- Implement handshake timeout, protocol version checks, display-name validation, capacity rejection, welcome/rejection messages, and disconnect cleanup.
- Implement authoritative lobby state, revisioning, leader assignment/transfer, ready/not-ready state, leader-only waiting-player ejection, round-target changes, minimum-player start validation, and late-spectator admission.
- Implement packed input and player-snapshot codecs with bounds checking, sequence wrap handling, input rate limiting, and sender-derived identity.
- Send inputs at 30 Hz and authoritative player snapshots at 20 Hz from the 60 Hz simulation.
- Implement local prediction/replay, reconciliation smoothing/snap thresholds, remote interpolation, limited extrapolation, and diagnostics counters.
- Implement authoritative projectile spawn/remove batches, predicted local shot matching, and 5 Hz projectile correction snapshots.
- Reject or ricochet wall-adjacent muzzle spawns, reset diagnostic overtime to a full heat clock, and clear stale prediction/session visuals while recentering disconnected clients.
- Add centered connection and lobby screens that keep the arena hidden until match start, including a 32-player scrollable roster, ready toggle, and leader-only eject controls.

### Verification

- Run protocol encode/decode, truncated-payload, non-finite input, oversized count, stale sequence, and authorization tests.
- Connect two clients to a headless server; verify unique identity, leader controls, synchronized movement, shooting, shield state, and projectile corrections.
- Disconnect the leader and verify deterministic transfer. Attempt joins with a bad version, invalid name, and full server and verify the expected reason codes.
- Compare server and client positions under repeated acceleration changes and verify prediction buffers are pruned by acknowledgements.

### Exit Gate

- Two clients can connect, move, aim, shoot, shield, disconnect, and reconnect to the lobby without the server trusting client-owned state.
- All protocol failures are handled without crashing or corrupting the session.

## Milestone 4 — Complete Multiplayer Match Loop

**Status:** Complete — 2026-08-24

**Outcome:** Human clients can play a networked match from lobby through draft, heats, rounds, results, and a clean second match.

### Work

- Connect the tested domain state machine to the authoritative server tick and reliable transition events.
- Implement private draft offers, selection validation, ready status, early completion, timeout auto-pick, simultaneous build application, and public post-draft builds.
- Implement authoritative heat spawning, countdown lock, survivor tracking, heat scoring, tie replay, round scoring, and configurable match victory.
- Add server-timed overtime boundary behavior and client synchronization.
- Implement death-to-spectator transition, target cycling, active disconnect elimination, between-state removal, forfeit victory, and late-join spectator behavior.
- Implement persistent match results, leader-authorized return to lobby, score/build reset, spectator promotion, and second-match startup.
- Add leader-owned total-player limits, optional server-owned NPC fill, human replacement of waiting NPC seats, NPC combat input/card selection, and a one-human NPC-assisted start path.
- Add the `--auto-start` behavior needed by integration tests.

### Verification

- Run one server and two scripted clients through a deterministic complete match and then a second match.
- Exercise a round longer than three heats, a simultaneous-death replay, a draft timeout, a combat disconnect, a mid-match late join, and a forfeit.
- Assert cards persist across heats/rounds but all cards and scores reset on lobby return.
- Verify client countdowns, scores, and state labels are derived from the same server tick and revision.
- Run the one-human NPC lobby verifier through four configured seats, a rendered human draft, active combat, world snapshots, and clean server shutdown.

### Exit Gate

- The complete loop is playable without debug intervention and matches every transition and edge case in sections 4–7 of `spec.md`.
- The two-client integration scenario is automated and consistently passes headlessly.

## Milestone 5 — Production UI, Neon Presentation, and Audio

**Status:** Complete — 2026-08-24
**Outcome:** The vertical slice communicates every state and combat event clearly at the target resolutions.

### Work

- Replace temporary screens with final connection, lobby, draft, combat HUD, spectator, scoreboard, results, pause/disconnect, and error states.
- Ensure card panels show exact effects, current/new stacks, category, selection lock, and accessible number-key hints.
- Add procedural neon ships, stable player palette, outline patterns, nameplates, local marker, projectile trails, shield arcs, impacts, elimination effects, and overtime boundary treatment.
- Add off-screen ship/projectile indicators using both shape and color.
- Add synthesized SFX for every event listed in the specification, optional drop-in menu/gameplay music, and prevent repeated network snapshots from replaying the same effect.
- Add UI scaling, minimum resolution handling, camera smoothing with heat-start recentering, restrained screen shake, and readable 32-player scoreboard behavior.
- Add clear messages and recovery navigation for all rejection and disconnect reason codes.

### Verification

- Manually inspect every screen at 1280×720 and 1920×1080, including a 32-player lobby/scoreboard and a full five-card unlimited-stack draft.
- Confirm local identity, shield state, shield break, damage direction, elimination, overtime, heat result, round result, and match result are distinguishable without relying only on color.
- Play two consecutive matches and confirm no stale panels, timers, effects, sounds, cards, or scores survive state resets.
- Render menu, 32-player lobby, draft, combat, spectator, pause, results, and error states at both target resolutions and fail on any runtime error or missing capture.
- Pass 780 headless assertions, 71 project checks, the real-ENet network/match-loop/NPC-lobby suites, and all 16 production-screen captures.

### Exit Gate

- A first-time tester can connect, identify themselves, choose cards, understand combat resources and scoring, spectate, and recognize the winner without developer explanation.
- All UI remains legible and interactive at both target resolutions.

## Milestone 6 — Validation, Diagnostics, and 32-Client Hardening

**Status:** Complete — 2026-08-24

**Outcome:** The authoritative server is observable, abuse-resistant within scope, and stable under the required local load.

### Work

- Complete request-state validation, rate limits, bounded arrays/strings, malformed packet handling, and safe peer removal.
- Add JSON-line server logging for startup, seed, connections, rejections, transitions, results, periodic metrics, fatal errors, and shutdown.
- Add the debug client network overlay and server counters for simulation duration, peers, entities, and outbound bytes.
- Implement the headless scripted test client using the real handshake, input, draft, and event protocol.
- Add configurable 2-client smoke and 32-client soak PowerShell scripts with process cleanup, log collection, assertions, and nonzero failure codes.
- Profile object counts, projectile batching, snapshot encoding, allocation hot spots, and server physics duration; optimize without changing specified behavior.
- Verify server shutdown closes ENet peers and child test clients without leaving processes behind.

### Verification

- Run malformed and excessive traffic tests and confirm only the offending peer is rejected.
- Run the required 10-minute, 32-client soak scenario, including overtime, one combat disconnect, one late spectator, and clean shutdown.
- Confirm 95th-percentile server simulation remains below 16.67 ms and entity collections do not grow without corresponding live entities.
- Review logs to ensure they contain required events and metrics but no per-frame spam or client IP addresses.
- Run `verify-milestone6.ps1` as the single full gate. The acceptance run completed 65 metric windows over at least 600 seconds with 32 initial clients, 25 heat results, 26 overtime activations, one combat disconnect, one late spectator, 97 peak projectiles, zero orphan nodes, and no unbounded object, node, memory, participant, or projectile trend.
- Record 794 passing assertions, 72 project checks, and a worst per-window simulation p95 of 10,678 µs against the 16,667 µs budget.

### Exit Gate

- The full automated protocol, integration, smoke, and soak suites pass from a single documented command.
- The performance and stability criteria in section 11.2 of `spec.md` are met and recorded.

### Post-completion competitive performance and architecture pass — 2026-08-27

- Replaced global projectile/ship and NPC-threat scans with deterministic arena-cell indexes, indexed projectile ownership/order, allocation-free hot-path views, and cached map collision geometry.
- Bounded every projectile transport message to 1,200 bytes without dropping spawn/removal records. Added rotating partial corrections, periodic complete recovery corrections, client-side full-chunk assembly, and protocol version 12.
- Moved replaceable hill/flag snapshots to their own unreliable ordered channel while retaining controller, pickup, drop, and reset transitions on reliable control delivery.
- Reused encoded player snapshot bodies and revision-cached roster, team, objective, score, standings, and UI data instead of rebuilding equivalent collections for every peer or frame.
- Extracted `CombatSpatialIndex`, `ProjectileCorrectionAssembler`, and `StandingsModel` from the authoritative world, network bridge, and client screen controller to give those responsibilities isolated APIs and tests.
- Added a repeatable overload benchmark for 32 Insane NPCs and the 1,024-projectile global ceiling. The final accepted run recorded 14,979 µs p50, 16,523 µs p95, 18,264 µs p99, and 18,716 µs maximum, down from an initial approximately 71.7 ms p95 implementation profile.
- Recorded 1,970 passing deterministic assertions plus passing real-ENet network, malicious-traffic hardening, NPC-lobby, and two-match/rematch verification. The existing ten-minute 32-client soak remains the release acceptance gate for ordinary-load p95 and long-duration stability.

## Milestone 7 — Export, Documentation, and Release Candidate

**Status:** In Progress — documentation completed 2026-08-25 and Windows Beta 1/Beta 2/Beta 3 client packages completed 2026-08-26; dedicated-server and final release-candidate work remains

**Outcome:** A clean checkout can produce and operate the deliverable Windows client and dedicated server.

### Delivered in 7.1–7.4

- Completed the repository README, player/host manual, contributor guide, documentation index, controls, architecture, local/LAN/internet hosting, troubleshooting, content authoring, tests, logs, limitations, and verification guidance.
- Pinned `0.1.0-beta.1` as the shared/project game version and displayed **BETA 1 · VERSION 0.1.0-beta.1** on the main connection screen.
- Added 2880×1920 as the sixteenth supported display resolution and extended visual acceptance to six resolutions and 180 captures.
- Added a Windows x64 client export preset with an embedded PCK and Windows product/file metadata.
- Added `build-beta.ps1`, which runs the full project gate, exports the client, launches the exported executable through its rendered startup path, rejects runtime errors or missing packaged music, calculates SHA-256 hashes, and creates the friend ZIP.
- Added friend-facing extraction, LAN/direct-connect, firewall/port-forwarding, unsigned-build, controls, and known-limitation guidance plus the Godot third-party license notice.
- Corrected exported music discovery to use Godot's remap-aware resource inventory, then verified the package finds one menu track, four gameplay tracks, and one victory track.
- Produced `SuperStarFighter-Beta1.exe` at 127,516,408 bytes and `SuperStarFighter-Beta1-Windows-x64.zip` at 57,045,256 bytes; both are generated under ignored `builds/beta-1/`.
- Advanced the shared, project, main-screen, Windows metadata, preset, executable, archive, and tester-guide identity to `0.1.0-beta.2` / **BETA 2** while preserving Beta 1 in its original folder.
- Reissued `SuperStarFighter-Beta2.exe` with the roster-integrated colour picker at 127,556,096 bytes and `SuperStarFighter-Beta2-Windows-x64.zip` at 57,080,057 bytes under ignored `builds/beta-2/`; SHA-256 values are `F4CE3B36CF2313F49D28D83A345BDB542445F355DD87F56385C93A37EA1AB8D1` and `77CA4BB4C865DCC1D43D6D0168A2A815DE62A974542343ACC385580E31EA0A13` respectively.
- Advanced the shared, project, main-screen, Windows metadata, preset, executable, archive, and tester-guide identity to `0.1.0-beta.3` / **BETA 3**, preserving both earlier beta folders.
- Produced `SuperStarFighter-Beta3.exe` at 127,585,272 bytes and `SuperStarFighter-Beta3-Windows-x64.zip` at 57,103,773 bytes under ignored `builds/beta-3/`; SHA-256 values are `84B2CFBAD047286D1A65CACFF204D4650514BF0AE572811F300EC4462B865616` and `A48616AC650449E91FFBC2DC000317355B124813134CDAF98B1E4117F838709C` respectively.

### Remaining Work

- Configure the Windows x64 dedicated-server export preset and strip client-only visual/audio resources while retaining shared collision/gameplay data.
- Extend release packaging to produce and validate `SuperStarFighterServer.exe` alongside the completed Beta 3 client.
- Add a release smoke script that starts the exported server, connects exported/headless clients, completes the minimum deterministic scenario, and shuts down cleanly.
- Maintain the completed documentation and add final dedicated-server/export instructions with the remaining packaging work.
- Audit repository contents for generated files, local paths, downloaded executables, secrets, and unlicensed assets.
- Run the complete manual acceptance matrix and record defects; fix every release-blocking defect before declaring the candidate complete.

### Verification

- Beta 1 client acceptance passed 1,666 deterministic assertions, 79 project checks, and 180 production captures across 1280×720, 1920×1080, 2560×1080, 2880×1920, 3440×1440, and 5120×1440.
- The exported executable passed embedded-resource creation, Windows metadata inspection, off-screen rendered startup, real Windows audio-driver startup, and packaged inventory validation for all six authored music tracks without runtime errors; the friend ZIP contains only the executable, Beta README, and third-party notice.
- Reissued Beta 2 client acceptance passed 1,762 deterministic assertions, 81 project checks, and 198 production captures; its embedded executable reported the expected client-ready marker and one menu, four gameplay, and one victory track without runtime errors. The ZIP contains only the Beta 2 executable, updated Beta README, and Godot third-party notice.
- Beta 3 client acceptance passed 1,853 deterministic assertions and 81 project checks; its embedded executable reported the expected client-ready marker and one menu, four gameplay, and one victory track without runtime errors. The ZIP contains only the Beta 3 executable, updated Beta README, and Godot third-party notice.

- Produce both release artifacts from a clean checkout using only the documented bootstrap and export commands.
- Connect two Windows clients to the exported server over localhost and LAN and complete two consecutive matches.
- Verify error handling for unreachable server, full server, version mismatch, leader disconnect, server shutdown, and invalid command-line values.
- Re-run the 32-client soak against the release-mode server export.

### Exit Gate

- Every automated and manual acceptance criterion in section 11 of `spec.md` passes.
- The two named Windows executables, test/soak/export tooling, and README are present and reproducible.
- No release-blocking issues, undocumented setup steps, secrets, or unlicensed assets remain.

## Milestone 8 — Ten-Map Expansion

**Status:** In Progress — static roster and automatic rotation completed 2026-08-26; advanced mechanics and full-capacity acceptance remain

**Outcome:** Core Arena is now the benchmark member of a playable ten-map roster. All ten maps provide distinct static topologies and remain fixed for every heat in a round, then advance through a deterministic shuffled rotation after the round is won. Advanced map-specific mechanics and the full 32-participant acceptance matrix remain future work.

### Delivered in 8.1

- Replaced the single hard-coded arena definition with dedicated-server-safe map IDs, names, palettes, rectangle/circle geometry, shared queries, and validation for Core Arena, Riftline, Prism Array, Twin Suns, Dead Freight, Longwave Array, Broken Orbit, Switchyard, Solar Tide, and Relay Zero.
- Added exactly 32 unique spawn anchors to every map, with a 96 px obstacle/boundary clearance disk and at least 160 px center separation.
- Added an independently seeded shuffled map deck. The authority selects once when a round's draft begins, preserves that map through countdown, every heat, tied replays, and the round result, then advances only when the next round begins.
- Published authoritative `map_id` and `map_name` state, now retained under protocol version 8 alongside manual reload, and rebuilt client visuals/collision from that identity.
- Made ship movement, projectile barriers and ricochets, spawn selection, overtime positioning, NPC sightlines, flanking, and anti-loop behavior query the active map.
- Added active-map names to countdown, combat HUD, and scoreboard presentation, plus distinct per-map floor, border, obstacle, and accent treatments.
- Expanded automated coverage for all ten geometry definitions, unique topology signatures, selected-map collision, authoritative round/heat cadence, client reconstruction, and HUD identity.
- Captured and visually inspected all ten maps at 1280×720, 1920×1080, 2560×1080, 3440×1440, and 5120×1440.
- Updated the specification, map plan, README, player manual, and development guide to match the implemented behavior and remaining boundaries.

### Remaining Work

- Implement and synchronize the advanced map mechanics described in the [Ten-Map Expansion Plan](./maps.md), including hazards or dynamic geometry, without weakening server authority or deterministic tests.
- Optionally add leader-controlled rotation pools or ordering while retaining automatic rotation as the default and one stable map per round.
- Add automated two-exit and overtime-reachability validation beyond the existing spawn clearance/separation checks.
- Run 2-, 8-, 16-, and 32-participant simulations on every map and a real-protocol 32-client rotating-map soak.
- Extend capture coverage to countdown, overtime, spectator, and victory contexts for each individual map when its advanced mechanics are added.

### Verification

- Validate exactly 32 unique anchors on every map, each with a 96 px obstacle-free disk, at least 160 px center separation, two clear exits, and an ordinary navigable route to overtime safety.
- Verify ship and weapon collision across every supported geometry primitive and synchronize every future dynamic mechanic through real server/client sessions.
- Run 2-, 8-, 16-, and 32-participant simulations on every map plus a real-protocol 32-client rotating-map soak.
- Complete consecutive matches on different maps through host, LAN, and direct-connect paths and verify clean lobby/rematch state rebuilding.
- Capture all ten maps in countdown, combat, overtime, spectator, and victory states at the supported 16:9 and ultrawide acceptance resolutions.

### Exit Gate

- All 320 authored spawn anchors pass the automated clearance, separation, egress, hazard, and reachability contract.
- All ten maps are selectable, synchronized, visually distinct, overtime-safe, and playable by humans and NPCs through the complete match lifecycle.
- The most expensive map remains inside the existing 60 Hz server tick budget with 32 participants and bounded mechanic/entity state.

## Vertical Slice Definition of Done

The vertical slice is done only when Milestones 0–7 are complete, the exported client and server pass the release smoke and 32-client soak tests, and the implemented behavior matches the authoritative specification without undocumented exceptions.
