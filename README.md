# Super Star Fighter

Super Star Fighter is a Windows-first, server-authoritative, top-down multiplayer arena shooter built with Godot 4.7.2 and GDScript.

Up to 32 human and NPC pilots fight through last-ship-standing heats. Before each round, eligible pilots choose one upgrade from a private five-card draw. Cards stack without limit, their effects compound, and a sensible little starter ship can become a screen-filling mechanical disaster. The first pilot to win two heats wins the round; the first to reach the configured round target wins the match.

## Highlights

- Ship-relative keyboard/mouse flight plus an optional twin-stick controller/joystick profile with independent analog aim.
- Automatic weapons, directional energy shields, ricochets, piercing rounds, multi-shot arrays, and pulse beams.
- 120 unlimited-stack cards across seven increasingly scarce rarity tiers.
- 24 numeric build stats plus beam and auto-repair transformations.
- Two to 32 total participants with individually configurable NPC difficulty.
- One-click local hosting, LAN server discovery, and direct-IP joining.
- Server-authoritative simulation with client prediction, reconciliation, and remote interpolation.
- Persistent display, audio, control-profile, deadzone, and per-action binding settings, plus ultrawide support, spectating, live standings, and rematches.

## Quick Start

The repository includes a pinned, self-contained Godot setup. From PowerShell in the repository root:

```powershell
.\tools\bootstrap.ps1
.\tools\start-client.ps1
```

`bootstrap.ps1` downloads Godot 4.7.2 and its Windows export templates into the ignored `.tools` directory, verifies the official SHA-512 checksums and executable signature, and installs nothing system-wide.

In the game:

1. Press any keyboard, mouse, or controller input on the splash screen.
2. Open **Host Game**.
3. Choose a server name and gameplay UDP port, then select **Host & Join**.
4. In the lobby, choose the player limit and round target. Enable NPCs if desired.
5. Every human selects **Ready for Launch**.
6. The lobby leader selects **Start Match**.

Other players on the same subnet can join from **LAN Servers**. **Direct Connect** accepts a hostname or IP address and gameplay port.

## Controls

Keyboard and mouse is the default profile. Open **Settings → Controls** to switch profiles, remap every gameplay/menu action, tune controller deadzone, or restore only the selected profile's defaults.

### Keyboard and mouse

| Input | Action |
| --- | --- |
| `W` / `S` | Fly forward / backward relative to the ship's nose |
| `A` / `D` | Strafe left / right relative to the ship's nose |
| Mouse | Aim ship and weapon |
| Left mouse | Fire automatically while held |
| Right mouse | Hold the directional shield |
| `1`–`5` or click | Choose a draft card |
| Hold `Tab` | Show live standings and public builds |
| `Escape` | Open the non-pausing pilot menu |
| `F3` | Toggle network diagnostics |
| `A` / `D` or mouse buttons while spectating | Cycle living pilots |

### Controller / joystick defaults

| Input | Action |
| --- | --- |
| Left stick | Forward/backward thrust and strafe |
| Right stick | Aim ship and weapon |
| Right / left trigger | Fire / shield |
| View / Back | Hold live scoreboard |
| Menu / Start | Open the non-pausing pilot menu |
| Left / right bumper while spectating | Cycle living pilots |
| D-pad | Navigate menus and draft cards |
| A / Cross | Confirm |
| B / Circle | Back |

Mapped Xbox-, PlayStation-, and similar controllers use these defaults. Flight sticks and other joysticks can bind any detected axis direction or button from the Controls tab.

## Documentation

- [Player and Host Manual](./docs/MANUAL.md) — complete instructions, match rules, card strategy, hosting, settings, and troubleshooting.
- [Development Guide](./docs/DEVELOPMENT.md) — repository architecture, setup, content authoring, testing, and contribution workflow.
- [Documentation Index](./docs/README.md) — the best document for each audience and task.
- [Authoritative Specification](./spec.md) — exact gameplay, networking, balance, and acceptance contract.
- [Product Plan](./plan.md) — product intent and scope.
- [Ten-Map Expansion Plan](./maps.md) — nine additional arena designs, map-system architecture, 32-spawn guarantees, and staged acceptance gates.
- [Implementation Milestones](./milestones.md) — delivered work and verification evidence.
- [Audio Drop-in Contract](./assets/audio/README.md) — accepted music and sound-effect filenames.

## Dedicated Server

Start a headless authoritative server with:

```powershell
.\tools\start-server.ps1 -Port 7000 -ServerName "Friday Fight Night" -MaxPlayers 32 -RoundsToWin 3
```

Super Star Fighter uses ENet over UDP. LAN discovery uses UDP `7359`; gameplay uses the selected UDP port, `7000` by default. Discovery is local-subnet convenience rather than public matchmaking. Internet hosting currently requires direct IP/hostname access and manual router/firewall configuration; UPnP traversal is not implemented.

See the [hosting chapter](./docs/MANUAL.md#4-hosting-and-joining) for practical LAN and internet setup.

## Development

Open the project editor:

```powershell
.\tools\run-editor.ps1
```

Run the fast test suite:

```powershell
.\tools\run-tests.ps1
```

Run the complete foundation gate:

```powershell
.\tools\verify-foundation.ps1
```

The current gate passes 1,556 automated assertions and 78 project checks. Network, match-loop, NPC, local-host, presentation, hardening, smoke, and 32-client soak harnesses are also included under `tools/`; the [development guide](./docs/DEVELOPMENT.md#11-verification-matrix) explains when to use each one.

## Current Scope

Milestones 0–6 and the subsequent gameplay/presentation improvements are complete. The playable vertical slice includes the full lobby-to-victory-to-rematch loop, authored-audio discovery with safe fallbacks, local hosting and LAN discovery, configurable NPCs, 120 cards, and validated 32-client server behavior.

The next release milestone is packaging and release-candidate validation. Public matchmaking, accounts, progression, teams, chat, automatic NAT traversal, reconnect restoration during an active match, map selection, and non-Windows exports are not part of the current slice.

## License and Assets

No project license has been declared in this repository yet. Treat the source and bundled assets as all-rights-reserved until a license file is added. Any replacement music or sound effects must be original or properly licensed for the project.
