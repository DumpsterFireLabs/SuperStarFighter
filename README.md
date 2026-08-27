# Super Star Fighter

Super Star Fighter is a Windows-first, server-authoritative, top-down multiplayer arena shooter built with Godot 4.7.2 and GDScript.

Up to 32 human and NPC pilots fight through last-ship-standing heats. Before each round, eligible pilots choose one upgrade from a private five-card draw. Cards stack without limit, their effects compound, and a sensible little starter ship can become a screen-filling mechanical disaster. The first pilot to win two heats wins the round; the first to reach the configured round target wins the match.

## Highlights

- Persistent Newtonian ship-facing or Relative screen-aligned flight, with keyboard/mouse and twin-stick controller/joystick profiles.
- Automatic weapons, directional energy shields, shield-ram melee builds, ricochets, piercing rounds, multi-shot arrays, and pulse beams.
- 125 unlimited-stack cards across seven increasingly scarce rarity tiers.
- 27 numeric build stats plus beam and auto-repair transformations.
- Two to 32 total participants with individually configurable NPC difficulty.
- Optional server-owned Rare-or-better arena powerups every 20 seconds.
- Persistent Random or colour-wheel ship appearance selection with non-colour identity patterns.
- One-click local hosting, LAN server discovery, and direct-IP joining.
- Ten authoritative arena layouts in a shuffled no-repeat rotation, changing between rounds while every heat stays on the same map.
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
4. In the lobby, choose the player limit and round target. Enable NPCs if desired. **Match Options & Ship Colour** contains the optional timed powerup rule and your personal Random/custom colour selection.
5. Every human selects **Ready for Launch**.
6. The lobby leader selects **Start Match**.

Other players on the same subnet can join from **LAN Servers**. **Direct Connect** accepts a hostname or IP address and gameplay port.

## Controls

Keyboard and mouse is the default profile. Open **Settings → Controls** to switch profiles, select Newtonian ship-facing or Relative screen-aligned flight, remap every gameplay/menu action, tune controller deadzone, or restore only the selected profile's defaults.

Display settings support persistent Windowed, Borderless Fullscreen, and Exclusive Fullscreen modes. Sixteen selectable resolutions cover common 16:9, 16:10, 3:2, 21:9, and 32:9 displays through 5120×2160, including 2880×1920 and 5120×1440 super-ultrawide.

## Windows Beta Build

The main menu identifies the current release as **Beta 1**, version `0.1.0-beta.1`. Build and verify the friend-ready Windows x64 client with:

```powershell
.\tools\build-beta.ps1
```

The script runs the complete foundation gate, exports a single embedded-PCK executable, launches that executable through its normal rendered startup path, verifies that its packaged menu/gameplay/victory music inventory matches the source, and creates the versioned friend ZIP with the Beta README and Godot third-party notice. Every tester-facing rebuild must increment the displayed game/build version before export so packages remain distinguishable. Generated builds remain ignored by Git.

### Keyboard and mouse

| Input | Action |
| --- | --- |
| `W` / `S` | Fly forward / backward relative to the ship's nose |
| `A` / `D` | Strafe left / right relative to the ship's nose |
| Mouse | Aim ship and weapon |
| Left mouse | Fire automatically while held |
| Right mouse | Hold the directional shield |
| `R` | Manually reload a partially used magazine |
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
| X / Square | Manually reload a partially used magazine |
| View / Back | Hold live scoreboard |
| Menu / Start | Open the non-pausing pilot menu |
| Left / right bumper while spectating | Cycle living pilots |
| D-pad | Navigate menus and draft cards |
| A / Cross | Confirm |
| B / Circle | Back |

Mapped Xbox-, PlayStation-, and similar controllers use these defaults. Flight sticks and other joysticks can bind any detected axis direction or button from the Controls tab.

Newtonian is the default flight mode: movement follows the ship's heading. Relative mode keeps movement aligned to the screen, so `W` or stick-up always moves upward regardless of aim. The local ship carries its own ammo/reload readout above the model.

## Documentation

- [Player and Host Manual](./docs/MANUAL.md) — complete instructions, match rules, card strategy, hosting, settings, and troubleshooting.
- [Development Guide](./docs/DEVELOPMENT.md) — repository architecture, setup, content authoring, testing, and contribution workflow.
- [Documentation Index](./docs/README.md) — the best document for each audience and task.
- [Authoritative Specification](./spec.md) — exact gameplay, networking, balance, and acceptance contract.
- [Product Plan](./plan.md) — product intent and scope.
- [Ten-Map Roster and Expansion Plan](./maps.md) — implemented static layouts and round rotation plus the advanced-mechanics roadmap.
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

The current gate passes 1,753 automated assertions and 81 project checks. Network, match-loop, NPC, local-host, presentation, hardening, smoke, export, and 32-client soak harnesses are also included under `tools/`; the [development guide](./docs/DEVELOPMENT.md#11-verification-matrix) explains when to use each one.

## Current Scope

Milestones 0–6 and the subsequent gameplay/presentation improvements are complete. The playable vertical slice includes the full lobby-to-victory-to-rematch loop, authored-audio discovery with safe fallbacks, local hosting and LAN discovery, configurable NPCs, timed arena card pickups, 125 cards, custom ship colours, and validated 32-client server behavior.

The Beta 1 Windows client export and packaging path is operational. Dedicated-server export, clean-machine friend testing, release-mode 32-client soak validation, code signing, and final release-candidate acceptance remain. Public matchmaking, accounts, progression, teams, chat, automatic NAT traversal, reconnect restoration during an active match, manual map selection/voting, and non-Windows exports are not part of the current slice.

## License and Assets

No project license has been declared in this repository yet. Treat the source and bundled assets as all-rights-reserved until a license file is added. Any replacement music or sound effects must be original or properly licensed for the project.
