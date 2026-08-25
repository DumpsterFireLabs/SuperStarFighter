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
.\tools\start-server.ps1
.\tools\start-client.ps1
```

The bootstrap script downloads the pinned portable Godot release and export templates into the ignored `.tools` directory. Nothing is installed system-wide.

## Current Status

Milestones 0–4 are complete. Human clients can now play the authoritative online loop from lobby through rendered five-card drafts, countdowns, heats, rounds, overtime, match results, spectator mode, lobby reset, and rematch. Lobby leaders can cap a match at 2–32 total participants, enable server-owned NPC fill, and force-start alone; waiting NPCs yield their seats as humans join. Card modifiers deliberately compound into extreme builds; many cards are pure upgrades, while technical guardrails protect networking and physics without acting as narrow balance ceilings. ENet networking uses server-owned simulation, bounded binary input/snapshot/projectile packets, 30 Hz input, 20 Hz player snapshots, 5 Hz projectile corrections, local prediction/reconciliation, and remote interpolation. The project verifier passes 65 checks; the headless suite passes 730 assertions and verifies that an intentional failure returns a nonzero exit code.

Milestone 5 (production UI, neon presentation, and audio) is next.

## Local Multiplayer

Start the authoritative server in one PowerShell window:

```powershell
.\tools\start-server.ps1 -Port 7000 -MaxPlayers 32 -RoundsToWin 3
```

Start one or more clients with `.\tools\start-client.ps1`, enter the server host and UDP port, and connect. The first admitted player is lobby leader. The leader can choose the round target and a total player limit up to the server capacity (maximum 32). Enable NPCs to fill every empty seat when **Force Start Match** is pressed, including when only one human is connected; leave NPCs disabled to require at least two humans.

`verify-network.ps1` launches isolated protocol clients and verifies handshake acceptance/rejection, authoritative inputs and snapshots, projectile traffic, leader transfer, late-spectator admission, and clean shutdown.

`verify-match-loop.ps1` launches one server and two protocol clients through deterministic full matches, including a private card choice, timeout auto-pick, scoring, reset, rematch, and clean shutdown.

`verify-npc-lobby.ps1` launches one human protocol client, configures four total seats, enables NPC fill, force-starts with three server-owned NPCs, and verifies drafting, combat input, snapshots, and clean shutdown.

## Online Match Controls

- `W` / `S`: forward/back relative to ship aim; `A` / `D`: strafe left/right; mouse: aim; left mouse: fire; right mouse: shield.
- Draft cards: click a card or press `1`–`5`.
- Hold `Tab` to inspect scores and public card builds.
- After elimination, use `A` / `D` or the left/right mouse buttons to cycle living ships.

## Offline Sandbox Controls

- `W` / `S`: move forward/back relative to ship aim; `A` / `D`: strafe left/right; mouse: aim with the custom crosshair; left mouse: automatic fire; right mouse: directional shield.
- `Q` / `E`: select a card; `G`: grant one stack; `C`: clear the current build.
- `T`: toggle target shields; `B`: toggle target fire; `Y`: reset the heat.
- `O`: start overtime or reset an active/warning overtime to a full 90-second heat clock; `Shift+O`: cycle diagnostic overtime stages.
- `F1`: toggle the on-screen help.
