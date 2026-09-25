# Super Star Fighter

Super Star Fighter is a Windows-first, server-authoritative, top-down multiplayer arena shooter built with Godot 4.7.2 and GDScript.

Up to 32 human and NPC pilots fight through solo or team heats. Before each round, eligible pilots choose one upgrade from a private five-card draw. Cards stack without limit, their effects compound, and a sensible little starter ship can become a screen-filling mechanical disaster. The first pilot or team to win two heats wins the round; the first to reach the configured round target wins the match.

## Highlights

- Persistent Newtonian ship-facing or Relative screen-aligned flight, with keyboard/mouse and twin-stick controller/joystick profiles.
- Automatic weapons, directional energy shields, shield-ram melee builds, knockback rounds, ricochets, piercing rounds, multi-shot arrays, and pulse beams.
- 136 unlimited-stack cards across seven increasingly scarce rarity tiers, including Afterburner, Cloak!, Kinetic Vent, Breakaway Thrusters, Star Mines, Hunter Missiles, and Rebound Shields.
- 41 numeric build stats plus beam, auto-repair, Afterburner, Cloak!, Kinetic Vent, Breakaway Thrusters, rebound shields, active mines, and forward-tracking missiles.
- Two to 32 total participants with individual and bulk NPC difficulty controls.
- Five selectable authoritative modes: Death Match, Team Death Match, King of the Hill, Capture the Flag, and Team Capture the Flag, with configurable two-to-eight-team Death Match lobbies, per-player/NPC team assignment, friendly-fire protection, five-second objective-mode respawns, round-rotating hills, home-base flag scoring, objective-aware NPCs, live objective HUD state, and team scoring.
- Optional server-owned Rare-or-better arena powerups with a configurable 5–90 second interval and heat-only or match-long inventory rules.
- Persistent Random or colour-wheel ship appearance selection with non-colour identity patterns.
- One-click local hosting, LAN server discovery, and direct-IP joining.
- Host-controlled global pause for breaks and intermissions, freezing combat and match timers for everyone.
- Ten authoritative arena layouts in a shuffled no-repeat rotation, changing between rounds while every heat stays on the same map.
- Server-authoritative simulation with client prediction, reconciliation, and remote interpolation.
- Independent active-ability selection, confirmed hull-hit and shield-block feedback, and authoritative death explanations.
- A searchable offline build lab with presets, configurable targets, and measured combat results using the server's simulation.
- A guided combat introduction and mechanic icons with effective build changes on draft cards.
- Persistent display, audio, control-profile, deadzone, and per-action binding settings, plus HUD scaling, reduced shake/flashes, an ultrawide HUD safe area, spectating, live standings, and rematches.

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
3. Choose a server name, gameplay UDP port, and required lobby password, then select **Host & Join**.
4. Open **Match Setup** in the lobby. **Match** contains presets, game mode, teams, and rounds to win; **Pilots** contains the player limit and NPC settings; **Arena Rules** contains overtime, powerups, and competitive view. Changes apply immediately. Click your appearance swatch beside your roster name to combine a custom colour with Solid, Zebra, Leopard, Checkerboard, Racing Stripe, or Chevron hull graphics, then apply the appearance or choose a random colour.
5. Every human selects **Ready for Launch**.
6. The lobby leader selects **Start Match**.

Other players on the same subnet can join from **LAN Servers**. **Direct Connect** accepts a hostname or IP address, gameplay port, and lobby password. Guests may remember an accepted password locally for that exact host-and-port endpoint.

## Controls

Keyboard and mouse is the default profile. Open **Settings → Controls** to switch profiles, select Newtonian ship-facing or Relative screen-aligned flight, remap every gameplay/menu action, tune controller deadzone, or restore only the selected profile's defaults.

Select an owned active ability with **Q/E** or **D-pad left/right**, then activate it with **Shift** or **left-stick click**. In the offline lab, **F2** switches between the paused build editor and the firing range. **Settings → Accessibility** adjusts HUD scale, shake, flashes, and the centered HUD safe area.

Choose **Learn to play** on the main menu for a short interactive lesson covering movement, firing, reloads, directional shields, Perfect Guard, abilities, and drafting. Each step advances when you perform its action; retry or skip at any time.

Display settings support persistent Windowed, Borderless Fullscreen, and Exclusive Fullscreen modes. Sixteen selectable resolutions cover common 16:9, 16:10, 3:2, 21:9, and 32:9 displays through 5120×2160, including 2880×1920 and 5120×1440 super-ultrawide.

## Beta Builds

The main menu identifies the current release as **Beta 12**, version `0.1.0-beta.12`. Build and verify the friend-ready Windows x64 client first:

```powershell
.\tools\build-beta.ps1
```

Then cross-build the Linux x64 client:

```powershell
.\tools\build-linux-beta.ps1 -SkipFoundationGate
```

Build the Linux ARM64 client for 64-bit Raspberry Pi and other AArch64 systems:

```powershell
.\tools\build-linux-beta.ps1 -Architecture arm64 -SkipFoundationGate
```

Finally, cross-build the universal macOS client for Apple Silicon and Intel Macs:

```powershell
.\tools\build-macos-beta.ps1 -SkipFoundationGate
```

The Windows script runs the complete foundation gate, exports a single embedded-PCK executable, launches it through its normal rendered startup path, verifies the packaged music inventory, and creates the versioned friend ZIP. The Linux script validates its embedded-PCK ELF architecture and packaged identity for either x64 or ARM64. The macOS script validates the `.app` layout, metadata, embedded identity, and both `arm64` and `x86_64` Mach-O slices. Omit `-SkipFoundationGate` when building any cross-platform package independently. Every tester-facing rebuild must increment the displayed game/build version before export so packages remain distinguishable. Generated builds remain ignored by Git.

The macOS beta is not yet signed or notarized. If Gatekeeper reports that `Super Star Fighter.app` is damaged even after using Control-click → Open, verify the supplied ZIP SHA-256, open Terminal in the extracted folder, run `xattr -cr "Super Star Fighter.app"`, and then use Control-click → Open again. A signed and notarized release will not require this workaround.

### Building without PowerShell

`tools/build.py` performs the same bootstrap, project gate, exports, and package checks with only Python 3.11+ (standard library), on Windows, Linux x64/ARM64, or macOS. Every host cross-builds all seven packages:

```bash
python3 tools/build.py bootstrap   # Godot 4.7.2 + export templates for this OS, SHA-512 verified, into .tools/
python3 tools/build.py build       # project gate, then every client and dedicated-server package
```

Pick targets to build only some packages. Targets: `windows`, `linux-x64`, `linux-arm64`, `macos`, `server-windows`, `server-linux-x64`, `server-linux-arm64`. Groups: `clients`, `servers`, and `all` (the default).

```bash
python3 tools/build.py build clients                    # all four clients
python3 tools/build.py build linux-arm64 server-linux-arm64 --skip-gate
python3 tools/build.py verify                           # project gate only
```

Packages, per-package audits, and a combined `SHA256SUMS.txt` are written to the release directory under `builds/`, or to `--output DIR`. Launch smoke tests run only for binaries the host can execute (Linux clients also need a display); other targets still receive their static header, version, archive, and resource-audit checks. On Windows, use `python` instead of `python3`.

### Linux graphics fallbacks

Linux normally uses the project's Compatibility renderer through desktop OpenGL 3.3. On Mesa systems that expose native OpenGL ES 3.0 but not desktop OpenGL 3.3, try:

```bash
./SuperStarFighter-Beta12.arm64 --rendering-method gl_compatibility --rendering-driver opengl3_es --verbose
```

On a Raspberry Pi or other ARM64 machine with a working Vulkan driver, the Mobile renderer is another possible fallback:

```bash
./SuperStarFighter-Beta12.arm64 --rendering-method mobile --rendering-driver vulkan --verbose
```

As a slow last resort with Mesa software rendering:

```bash
LIBGL_ALWAYS_SOFTWARE=1 ./SuperStarFighter-Beta12.arm64 --rendering-method gl_compatibility --rendering-driver opengl3 --verbose
```

Use the `.x86_64` filename for Linux x64. These overrides are compatibility suggestions rather than native acceptance-tested configurations. Godot 4 requires at least OpenGL ES 3.0 for Compatibility; GLES 2-only systems are unsupported. Keep `--verbose` during diagnosis to confirm the selected API, renderer, and GPU.

### Keyboard and mouse

| Input | Action |
| --- | --- |
| `W` / `S` | Fly forward / backward relative to the ship's nose |
| `A` / `D` | Strafe left / right relative to the ship's nose |
| Mouse | Aim ship and weapon |
| Left mouse | Fire automatically while held |
| Right mouse | Hold the directional shield |
| `R` | Manually reload a partially used magazine |
| `Shift` | Activate Afterburner, Cloak!, or Star Mines when its card is owned |
| `1`–`5` or click, then confirm | Choose and lock in a draft card |
| Hold `Tab` | Show live standings and public builds |
| `Escape` | Open the non-pausing pilot menu |
| `F2` | Return to the main menu; active sessions require confirmation |
| `F3` | Toggle network diagnostics |
| `F10` (host only) | Pause or resume the match for everyone |
| `A` / `D` or mouse buttons while spectating | Cycle living pilots |

### Controller / joystick defaults

| Input | Action |
| --- | --- |
| Left stick | Forward/backward thrust and strafe |
| Right stick | Aim ship and weapon |
| Right / left trigger | Fire / shield |
| X / Square | Manually reload a partially used magazine |
| Left Stick Click | Activate Afterburner, Cloak!, or Star Mines when its card is owned |
| View / Back | Hold live scoreboard |
| Menu / Start | Open the non-pausing pilot menu |
| Left / right bumper while spectating | Cycle living pilots |
| D-pad | Navigate menus and draft cards |
| A / Cross | Confirm |
| B / Circle | Back |

Mapped Xbox-, PlayStation-, and similar controllers use these defaults. Flight sticks and other joysticks can bind any detected axis direction or button from the Controls tab.

Relative is the default flight mode: movement stays aligned to the screen, so `W` or stick-up always moves upward regardless of aim. Newtonian mode instead follows the ship's heading. The local ship carries its own ammo/reload readout above the model.

## Documentation

- [Player and Host Manual](./docs/MANUAL.md) — complete instructions, match rules, card strategy, hosting, settings, and troubleshooting.
- [Development Guide](./docs/DEVELOPMENT.md) — repository architecture, setup, content authoring, testing, and contribution workflow.
- [Documentation Index](./docs/README.md) — the best document for each audience and task.
- [Authoritative Specification](./docs/design/spec.md) — exact gameplay, networking, balance, and acceptance contract.
- [Product Plan](./docs/design/plan.md) — product intent and scope.
- [Ten-Map Roster and Expansion Plan](./docs/design/maps.md) — implemented static layouts and round rotation plus the advanced-mechanics roadmap.
- [Implementation Milestones](./docs/design/milestones.md) — delivered work and verification evidence.
- [Audio Drop-in Contract](./assets/audio/README.md) — accepted music and sound-effect filenames.

## Dedicated Server

The Beta 12 friend ZIPs are client packages and do not yet include a standalone stripped server executable. The supported dedicated-server workflow currently requires a source checkout and its bootstrapped tools.

Start a headless authoritative server with:

```powershell
.\tools\start-server.ps1 -Port 7000 -ServerName "Friday Fight Night" -AdminPort 7001 -MaxPlayers 32 -RoundsToWin 3
```

The launcher prompts securely for the lobby password and, when administration is enabled, a distinct admin password of at least 12 characters. A dedicated server never remembers or writes either password. For unattended service startup, `-PasswordFile` and `-AdminPasswordFile` are read-only startup sources supplied by the operator; keep them ACL-protected and outside the repository. An admin password enables in-game administration through the existing gameplay connection, even with `-AdminPort 0`. The optional TCP command listener binds only to `127.0.0.1`; use an SSH tunnel for remote command-line access. Failed admin authentication and gameplay connection churn are throttled across reconnects, requests and responses are size-bounded, and the bounded address-block file is replaced atomically.

An unattended launch can provide protected one-line password files and a persistent ban file:

```powershell
.\tools\start-server.ps1 -Port 7000 -ServerName "Friday Fight Night" -AdminPort 7001 -MaxPlayers 32 -RoundsToWin 3 -PasswordFile "C:\ServerSecrets\ssf-lobby.txt" -AdminPasswordFile "C:\ServerSecrets\ssf-admin.txt" -BanFile "C:\ServerData\ssf-bans.json"
```

For in-game administration alone, omit `-AdminPort` and keep `-AdminPasswordFile`. The server then opens only its gameplay UDP port.

Common management commands are:

```powershell
.\tools\admin.ps1 -Port 7001 -Command status
.\tools\admin.ps1 -Port 7001 -Command players
.\tools\admin.ps1 -Port 7001 -Command kick -PeerId 4
.\tools\admin.ps1 -Port 7001 -Command ban -PeerId 7
.\tools\admin.ps1 -Port 7001 -Command unblock -Source 203.0.113.8
.\tools\admin.ps1 -Port 7001 -Command set -Setting rounds_to_win -Value 5
.\tools\admin.ps1 -Port 7001 -Command set-password
.\tools\admin.ps1 -Port 7001 -Command restart-match
.\tools\admin.ps1 -Port 7001 -Command shutdown
```

For remote command-line administration, forward a local port through SSH—`ssh -N -L 7001:127.0.0.1:7001 operator@example-server`—then run `admin.ps1` locally against port `7001`. Runtime setting/password changes last only for the current process; persistent values belong in the launch configuration and protected password sources. Address blocks are persisted immediately to the configured ban file. Monitor the JSON-line `simulation_metrics`, especially p95/max latency and `over_budget_ticks`.

Once connected, open **Admin** in the online lobby or **Server Admin** in the pause menu and enter the separate admin password. The panel uses the existing game connection; players need no SSH access or admin port. It shows server status and players and supports moderation, live settings, match restart, and graceful shutdown. Restart begins a fresh match at round one and resets scores and builds. Because gameplay ENet traffic is not encrypted, use a long random admin password; the panel does not offer password rotation over that connection.

The Windows dedicated package includes unattended launch and administration scripts. Health reports continue while idle or paused; admin status includes uptime, recent metrics and their age. See the [dedicated server runbook](./docs/SERVER_README.txt) and [readiness validation](./docs/archive/SERVER-READINESS-2026-09-08.md) for launch commands, capacity gates and measured limits.

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

The test and foundation commands report their actual assertion and check counts. See the [dated review and implementation evidence](./docs/archive/REVIEW-2026-09-03.md) for recorded results and their limits. Network, match-loop, NPC, local-host, presentation, hardening, smoke, export, and 32-client soak harnesses are also included under `tools/`; the [development guide](./docs/DEVELOPMENT.md#11-verification-matrix) explains when to use each one.

## Current Scope

Milestones 0–6 and the subsequent gameplay/presentation improvements are complete. The playable vertical slice includes the full lobby-to-victory-to-rematch loop, five solo/team elimination and objective modes, authored-audio discovery with safe fallbacks, local hosting and LAN discovery, configurable objective-aware NPCs, timed arena card pickups, 136 cards, custom ship colours and hull patterns, and validated 32-client server behavior.

Beta 12 targets Windows x64, Linux x64, Linux ARM64/Raspberry Pi, and universal macOS, with outputs under `builds/beta-12/`. Beta 1 through Beta 11 remain archived separately. A stripped Windows dedicated-server build is available through `tools/build-server.ps1`, with resource auditing, standalone startup and a short packaged-server 32-client soak verified. Clean-machine testing, native distribution acceptance, longer representative-hardware performance testing, signing/notarization and final release acceptance remain. Public matchmaking, accounts, progression, chat, automatic NAT traversal, reconnect restoration during an active match, and manual map selection/voting are not part of the current slice.

## License and Assets

The source code, scenes, data, tests, tools, and documentation are released under the [MIT License](./LICENSE). The bundled music and the Dumpster Fire Labs logo are **not** covered by it; they remain all rights reserved, and forks should replace them and use a different name. See [asset licensing](./assets/LICENSE.md) for the full breakdown. Any replacement music or sound effects must be original or properly licensed for the project.

The [attribution inventory](./docs/ATTRIBUTION.md) records source/dependency coverage and exact asset hashes, including unresolved provenance. Packages include Godot and bundled-component notices.

### Linux dedicated server packages

Build with `tools/build-linux-server.ps1 -Architecture x86_64` or `-Architecture arm64`. Beta 12 server archives are written under `builds/beta-12/server-linux-x86_64/` and `builds/beta-12/server-linux-arm64/`. Each includes a headless shell launcher, Python 3 administration tool, and the [dedicated server operations guide](docs/SERVER_README.txt), including Linux setup and a systemd example. Both tar.gz and ZIP archives are verified for architecture, embedded resources and contents; native Linux launch/load acceptance remains separate.
