# Super Star Fighter

Super Star Fighter is a Windows-first, server-authoritative, top-down multiplayer arena shooter built with Godot 4.7.2 and GDScript.

The project is currently implementing the vertical slice described in:

- [Product plan](./plan.md)
- [Authoritative specification](./spec.md)
- [Implementation milestones](./milestones.md)

## Development Commands

From PowerShell in the repository root:

```powershell
.\tools\bootstrap.ps1
.\tools\run-editor.ps1
.\tools\run-tests.ps1
.\tools\verify-foundation.ps1
.\tools\verify-network.ps1
.\tools\verify-match-loop.ps1
.\tools\verify-npc-lobby.ps1
.\tools\verify-presentation.ps1
.\tools\verify-hardening.ps1
.\tools\verify-smoke.ps1
.\tools\verify-soak.ps1
.\tools\verify-milestone6.ps1
.\tools\start-server.ps1
.\tools\start-client.ps1
```

The bootstrap script downloads the pinned portable Godot release and export templates into the ignored `.tools` directory. Nothing is installed system-wide.

## Current Status

Milestones 0–6 are complete. Human clients can play the authoritative online loop from lobby through rendered 30-second five-card drafts, countdowns, heats, rounds, overtime, match results, spectator mode, lobby reset, and rematch. Every connected human must ready up before launch; lobby leaders can eject other waiting humans, cap a match at 2–32 total participants, enable server-owned NPC fill, configure every NPC independently from Passive through Insane, and start alone with NPC fill after readying. Waiting NPCs yield their seats as humans join. The connection and lobby screens use centered non-gameplay menus and keep the arena hidden until the match begins. The production interface includes an animated splash that accepts any key immediately and auto-advances after ten seconds, responsive neon menu/lobby screens, persistent audio and standard/ultrawide resolution settings, a compact upper-left combat HUD, readable rarity-colored card panels, a polished hold-to-view live scoreboard, spectator guidance, an in-match Escape menu, a structured champion-and-standings victory screen with hoverable rarity-colored final-build cards and a leader-controlled Exit to Lobby action, and recoverable error screens. Completed non-final rounds use a short 2.5-second authoritative result intermission; a decisive final round skips it and proceeds to victory. The 60-card catalog spans Common, Uncommon, Rare, Epic, Legendary, Mythical, and Unobtanium tiers and includes authoritative pulse-beam weapons at Epic rarity or above; modifiers and unlimited card stacks deliberately compound into extreme builds. Tier weights fall steeply from 60% Common to 0.05% Unobtanium. Everyone drafts before round one, while each later round winner keeps their build and sits out the next draft so losing players receive the comeback upgrades. Named ships use stable color plus shape patterns, speed-responsive light thruster particles, trails, shields, impacts, damage direction, elimination pulses, overtime treatment, off-screen threats, and local-only camera feedback. ENet networking uses server-owned simulation, bounded binary input/snapshot/projectile packets, 30 Hz input, 20 Hz player snapshots, 5 Hz projectile corrections, local prediction/reconciliation, and remote interpolation. Malformed inputs and sustained control/input floods isolate only their sender; bounded JSON-line logs report match events and ten-second p95 timing/entity/memory windows without client addresses. The expanded foundation gate passes 1,197 automated assertions and 73 project checks; the completed Milestone 6 acceptance record remains 794 assertions, 72 project checks, and a 600-second 32-client soak whose worst timing-window p95 was 10.678 ms.

Milestone 7 (export, documentation, and release candidate) is next.

## Local Multiplayer

Start the authoritative server in one PowerShell window:

```powershell
.\tools\start-server.ps1 -Port 7000 -MaxPlayers 32 -RoundsToWin 3
```

Start one or more clients with `.\tools\start-client.ps1`, enter the server host and UDP port, and connect. The first admitted player is lobby leader. Every human must select **Ready for Launch** before the leader can start; changing lobby settings clears readiness. The leader can eject other waiting humans, choose the round target, and set a total player limit up to the server capacity (maximum 32). Enable NPCs to immediately fill every empty seat, then set each NPC independently to Passive, Easy, Neutral, Skilled, or Insane from its roster dropdown. Neutral is the default, and difficulty changes decision quality without bonus stats. One readied human may start with NPC fill; leave NPCs disabled to require at least two humans.

`verify-network.ps1` launches isolated protocol clients and verifies handshake acceptance/rejection, authoritative inputs and snapshots, projectile traffic, leader transfer, late-spectator admission, and clean shutdown.

`verify-match-loop.ps1` launches one server and two protocol clients through deterministic full matches, including a private card choice, timeout auto-pick, scoring, reset, rematch, and clean shutdown.

`verify-npc-lobby.ps1` launches one human protocol client, configures four total seats, enables NPC fill, starts with three server-owned NPCs, and verifies drafting, combat input, snapshots, and clean shutdown.

`verify-presentation.ps1` renders splash, menu, settings, 32-player lobby, draft, winner draft bye, combat, live scoreboard, spectator, pause, structured victory, and error screens at 1280×720, 1920×1080, 2560×1080, and 3440×1440. It asserts the real framebuffer dimensions and fails on parser/runtime errors or missing captures; images are written beneath the ignored `.tools/presentation-verification` directory.

`verify-hardening.ps1` proves malformed and sustained excessive traffic disconnect only the offending peer while healthy clients continue. `verify-smoke.ps1` accepts 2–32 real ENet clients. `verify-soak.ps1` defaults to the acceptance configuration of 32 clients for 600 seconds and records an ignored JSON summary beneath `.tools/soak-verification/`.

`verify-milestone6.ps1` is the single full gate: unit/project checks, protocol integration, two complete matches, NPC lobby, hostile traffic, smoke, and configurable soak. Its default invocation runs the required ten-minute 32-client scenario.

## Audio Assets

The game is fully operational before authored audio arrives. It generates short placeholder SFX and victory music at runtime, while safely skipping absent menu/gameplay tracks.

- Put the singular menu track at `assets/audio/music/main_menu.mp3` (or `.wav`/`.ogg`; compound names such as `main_menu.mp3.wav` work).
- Put any number of `.mp3`, `.wav`, or `.ogg` gameplay tracks in `assets/audio/music/gameplay/`; they play in filename order as a playlist.
- Put authored victory music at `assets/audio/music/win.mp3` (recommended exact filename), or use `win.wav` / `win.ogg`. The generated victory theme remains the fallback.
- Replace placeholder SFX by following [the audio drop-in contract](./assets/audio/README.md). No code changes are required.

## Online Match Controls

- `W` / `S`: forward/back relative to ship aim; `A` / `D`: strafe left/right; mouse: aim; left mouse: fire; right mouse: shield.
- Draft cards: click a card or press `1`–`5`.
- Hold `Tab` to inspect scores and public card builds.
- After elimination, use `A` / `D` or the left/right mouse buttons to cycle living ships.
- `Escape`: open the non-pausing pilot menu; `F3`: toggle network diagnostics.

## Offline Sandbox Controls

- `W` / `S`: move forward/back relative to ship aim; `A` / `D`: strafe left/right; mouse: aim with the custom crosshair; left mouse: automatic fire; right mouse: directional shield.
- `Q` / `E`: select a card; `G`: grant one stack; `C`: clear the current build.
- `T`: toggle target shields; `B`: toggle target fire; `Y`: reset the heat.
- `O`: start overtime or reset an active/warning overtime to a full 90-second heat clock; `Shift+O`: cycle diagnostic overtime stages.
- `F1`: toggle the on-screen help.
