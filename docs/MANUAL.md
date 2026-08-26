# Super Star Fighter — Player and Host Manual

**Applies to:** current Windows vertical slice  
**Engine:** Godot 4.7.2  
**Players:** 2–32 total human/NPC participants; one human may start when NPC fill is enabled

This manual explains how to launch, host, join, play, troubleshoot, and run a good Super Star Fighter session. Exact implementation values live in the [authoritative specification](../spec.md).

## Contents

1. [What Kind of Game Is This?](#1-what-kind-of-game-is-this)
2. [Running the Game From This Repository](#2-running-the-game-from-this-repository)
3. [Main Menu](#3-main-menu)
4. [Hosting and Joining](#4-hosting-and-joining)
5. [Lobby Manual](#5-lobby-manual)
6. [Match Flow](#6-match-flow)
7. [Flight and Combat](#7-flight-and-combat)
8. [Cards and Builds](#8-cards-and-builds)
9. [HUD, Scoreboard, Spectating, and Menus](#9-hud-scoreboard-spectating-and-menus)
10. [Settings, Controls, and Audio](#10-settings-controls-and-audio)
11. [Offline Combat Lab](#11-offline-combat-lab)
12. [Disconnects and Rejoining](#12-disconnects-and-rejoining)
13. [Troubleshooting](#13-troubleshooting)
14. [Hosting Checklist](#14-hosting-checklist)
15. [Current Limitations](#15-current-limitations)

## 1. What Kind of Game Is This?

Super Star Fighter is a free-for-all top-down space shooter about mechanical skill and increasingly unreasonable upgrades.

Every match is made of rounds. Every round is made of last-ship-standing heats. Before round one, every pilot receives a private draw of five cards and chooses one. Before later rounds, everyone except the previous round winner drafts another card. The cards permanently modify that pilot's build for the remainder of the match.

There are no card stack limits. Flat bonuses add, multipliers compound, and complementary cards interact. A build can become extremely fast, extremely durable, flood the arena with projectiles, fire long-lived ricochets, repair itself, or convert its weapon into pulse beams. This escalation is intentional.

The victory structure is:

```text
Win 2 heats → win the round
Win the configured number of rounds → win the match
```

With three or more pilots, a round can take more than three heats because several pilots may each hold one heat win.

## 2. Running the Game From This Repository

### Requirements

- Windows x64.
- PowerShell 7 or a compatible modern PowerShell.
- Internet access for the first bootstrap only.
- Keyboard and mouse, or a Godot-recognized controller/joystick after selecting that profile in Settings.
- A GPU/driver capable of Godot's OpenGL compatibility renderer.

No separate Godot installation is necessary.

### First launch

Open PowerShell in the repository root and run:

```powershell
.\tools\bootstrap.ps1
.\tools\start-client.ps1
```

The bootstrap process downloads the pinned Godot 4.7.2 engine and Windows export templates to `.tools/`. It validates official checksums and the Windows executable signature. The download is self-contained and ignored by Git.

On later launches, only run:

```powershell
.\tools\start-client.ps1
```

If the bootstrap is incomplete or damaged, rerun it with:

```powershell
.\tools\bootstrap.ps1 -Force
```

This replaces only the repository's local `.tools` engine/template files.

## 3. Main Menu

The main screen displays **BETA 1 · VERSION 0.1.0-beta.1** so players can confirm they are using the same build before joining one another.

The splash screen accepts a keyboard, mouse, or controller press immediately and otherwise advances after ten seconds.

The connection screen has three online paths:

- **LAN Servers** discovers compatible sessions on the local subnet.
- **Direct Connect** joins a known hostname or IP address and UDP port.
- **Host Game** starts an authoritative server locally and joins it through the normal network protocol.

The same screen also offers:

- **Offline Combat Lab** for solo movement, combat, card, shield, and overtime experimentation.
- **Settings** for display mode, resolution, audio, and controls.
- **Quit** to close the game.

Display names may contain 1–16 printable characters. When names collide, the server adds suffixes such as `#2` for display clarity.

## 4. Hosting and Joining

### 4.1 One-click local hosting

For most playtests, use **Host Game**:

1. Enter your display name.
2. Open the **Host Game** tab.
3. Enter a server name. This is what nearby players see in the LAN list.
4. Choose a gameplay UDP port from `1024` through `65535`. Port `7359` is reserved for discovery and cannot be used for gameplay.
5. Select **Host & Join**.

The game starts an authoritative server inside an isolated multiplayer subtree, then connects your playable client to it over loopback. The host's player does not receive special simulation authority or gameplay advantages.

Closing or disconnecting the hosting client shuts down its in-process server, so use the dedicated server path when the authority should outlive any particular player's window.

### 4.2 Joining from the LAN browser

1. Enter your display name.
2. Open **LAN Servers**.
3. Select **Refresh** if the desired host has not appeared.
4. Review the server name, occupancy, player limit, match state, compatibility, and ping.
5. Join a compatible row.

LAN discovery uses UDP port `7359` and works within one broadcast domain. Guest Wi-Fi isolation, VLAN boundaries, VPN routing, or operating-system firewall rules may prevent discovery even when direct connection works.

An incompatible protocol server remains visible but cannot be joined. All players and the server must run compatible builds.

### 4.3 Direct connection

Use **Direct Connect** when you know the server address:

1. Enter a hostname or IPv4/IPv6 address in **Server host or IP**.
2. Enter the server's gameplay UDP port.
3. Select **Connect to Server**.

For the same computer, use `127.0.0.1`. For another computer on the LAN, use that computer's private address, such as `192.168.1.50`. For an internet server, use its public hostname or public IP.

### 4.4 Dedicated server

From the repository root:

```powershell
.\tools\start-server.ps1 `
    -Port 7000 `
    -ServerName "Friday Fight Night" `
    -MaxPlayers 32 `
    -RoundsToWin 3
```

Parameters:

| Parameter | Range | Default | Meaning |
| --- | ---: | ---: | --- |
| `Port` | 1024–65535 | 7000 | ENet gameplay UDP port |
| `ServerName` | 1–40 printable characters | Super Star Fighter Server | LAN browser name |
| `MaxPlayers` | 2–32 | 32 | Maximum server/lobby participant capacity |
| `RoundsToWin` | 1–5 | 3 | Initial lobby round target |

The dedicated process runs headlessly and prints bounded JSON-line events and metrics to standard output. Stop it with `Ctrl+C` when the session is over.

### 4.5 Internet hosting and firewalls

Super Star Fighter uses ENet over UDP, not TCP.

For internet play, the host normally needs to:

1. Allow the Godot/server executable through the host firewall for the chosen UDP gameplay port.
2. Forward that UDP port from the router to the server computer when behind NAT.
3. Give players the public hostname/IP and gameplay port.

UPnP, NAT punch-through, relay hosting, and a public server directory are not implemented. UDP `7359` is only for local discovery and should not be exposed as a public matchmaking service.

## 5. Lobby Manual

The first admitted human is the lobby leader. If that player disconnects, leadership passes to the earliest remaining human. NPCs never become leader.

### Every human player

- Reviews the roster and lobby rules.
- Selects **Ready for Launch** when prepared.
- Becomes not ready whenever the leader changes a lobby setting.
- May disconnect voluntarily before or during a match.

### Lobby leader

- Sets **Rounds to win** from 1 through 5.
- Sets the **Player limit** from 2 through server capacity, never above 32 or below the number of connected humans.
- Enables or disables NPC fill.
- Selects each NPC's difficulty.
- Ejects other waiting human players.
- Starts the match once the launch conditions are satisfied.
- Selects **Exit to Lobby** from final results after the match.

The leader cannot eject players during an active match and cannot eject themselves. Ejected players return to the connection screen with a clear reason.

### Launch conditions

- Every connected human must be ready.
- With NPCs disabled, at least two humans are required.
- With NPCs enabled, one ready human may start with the configured NPC roster.

The start button explains whichever requirement is missing. When a normal human lobby is ready it reads **Start Match**; a solo NPC-assisted launch reads **Start Match with NPCs**.

### NPC fill

Enabling NPCs fills all open configured seats immediately. Each waiting NPC appears in the roster and can be configured before launch. If a human joins a full waiting lobby, that human replaces one NPC rather than being rejected. Disabling NPCs removes all waiting NPCs.

NPC difficulty changes behavior, not stats:

| Difficulty | Intended experience |
| --- | --- |
| Passive | Movement target; never fires or shields |
| Easy | Slow reactions, broad aim error, conservative firing |
| Neutral | General-purpose opponent with moderate leading and pressure |
| Skilled | Fast reactions, accurate leading, strong movement and shield use |
| Insane | Near-immediate reactions, extremely accurate aim, relentless pressure |

Every NPC uses the same cards, health, weapon rules, movement limits, collision, and damage model as a human.

NPCs respect arena cover and overtime. They do not deliberately fire through blocking geometry. When two NPCs lose line of sight behind the same object, one initially holds while the other commits to a deterministic flank. If the obstruction persists for three seconds, the holder takes the opposite route; brief sightline flickers do not restart that clock, while a sustained clear lane resets it. This keeps fights progressing before overtime without turning normal cover use into constant motion. During overtime, moving inside the shrinking safe circle takes priority over ordinary pursuit—even for Passive NPCs.

## 6. Match Flow

### Draft

Every participant drafts before round one. Before later rounds, the pilot who just won the round receives no card; everyone else receives a comeback draft. This prevents the leader from automatically snowballing through extra upgrades.

Human players see five private cards and have 30 seconds to choose. Click a card or press `1` through `5`. If the timer expires, the server chooses one of the offered cards. NPC choices are server-owned. When every eligible choice is locked, the draft ends immediately.

The cards apply simultaneously. Builds become public after the draft and can be inspected while holding `Tab`.

### Countdown and BEGIN

Ships spawn at full derived health, full shield energy, and a full magazine. Controls remain locked during the three-second countdown. The center plate shows **READY**, changes to **BEGIN** with `0.10` seconds remaining, and fades through the first `0.10` seconds of active combat.

The camera snaps to your ship at the start of every heat.

### Active heat

Fight until one ship remains. That survivor gains one heat win. Two heat wins award the round.

If every remaining ship dies during the same authoritative tick, the heat is a tie: nobody receives a heat win and the heat is replayed after the result screen.

### Round and match results

After a non-final round, heat-win counters clear and the next comeback draft begins. The first pilot to reach the configured round target wins the match.

The final victory screen stays open. Hover any card in a final build to inspect its per-stack and compounded effects. The lobby leader selects **Exit to Lobby** when the group is ready. Everyone returns to the same connected lobby with builds, scores, and readiness cleared.

## 7. Flight and Combat

### 7.1 Controls

Keyboard and mouse is the first-launch default:

| Input | During combat |
| --- | --- |
| `W` | Accelerate forward along the ship's nose |
| `S` | Accelerate backward |
| `A` | Strafe left |
| `D` | Strafe right |
| Mouse | Point ship and weapon |
| Hold left mouse | Automatic fire |
| Hold right mouse | Directional shield |
| Hold `Tab` | Live standings and public builds |
| `Escape` | Pilot menu; online combat continues |
| `F3` | Network diagnostic overlay |

The controller/joystick profile defaults to:

| Input | During combat and menus |
| --- | --- |
| Left stick | Forward/backward thrust and strafe |
| Right stick | Point ship and weapon |
| Hold right trigger | Automatic fire |
| Hold left trigger | Directional shield |
| Hold View / Back | Live standings and public builds |
| Menu / Start | Pilot menu; online combat continues |
| Y / Triangle | Network diagnostic overlay |
| Left / right bumper while spectating | Cycle living pilots |
| D-pad | Navigate menus and draft cards |
| A / Cross | Confirm |
| B / Circle | Back |

Movement is ship-relative, not screen-relative. If the ship faces down, forward input moves down. A useful mental model is that the mouse or aim stick steers the nose while the movement controls command forward, reverse, and lateral thrusters.

Diagonal input is normalized, so combining directions does not increase top speed.

Every listed gameplay and menu action can be rebound independently under **Settings → Controls**. The keyboard/mouse and controller profiles are stored separately, so changing one does not erase the other. A flight stick, rudder, arcade stick, or other joystick can bind any detected button or positive/negative axis direction; hardware still needs enough independent axes or buttons to provide both movement and aim.

### 7.2 Weapons

The base weapon deals 25 damage, fires four shots per second, holds eight rounds, reloads automatically in 1.5 seconds, and launches projectiles at 900 pixels per second for 2.5 seconds.

There is no manual reload. When the magazine empties, reload begins automatically. Firing is disabled during reload and while shielding.

Cards can alter damage, cadence, magazine size, reload, projectile count, spread, speed, lifetime, pierces, and ricochets. Beam cards transform shots into fast, short-lived pulse beams while retaining authoritative collision and damage.

### 7.3 Directional shields

The base shield covers a 120-degree arc centered on the ship's aim. It starts with 100 energy, drains 20 energy per second while held, and spends 25 energy for each blocked projectile.

A projectile is blocked only if it strikes inside the visible forward arc. Rear and side shots outside the arc continue to the hull. A blocked projectile is consumed even if it had pierces or ricochets remaining.

After shield activity, regeneration waits 1.25 seconds, then restores 30 energy per second. Fully depleting the shield locks it until it reaches the recovery threshold. Cards can modify capacity, drain, regeneration, delay, block cost, recovery threshold, arc, and acceleration while shielding.

Shielding prevents firing and normally reduces acceleration, so timing matters: turn the arc into danger, absorb the burst, then release to shoot and recover maneuverability.

### 7.4 Collision and cover

Ships slide against arena walls, map obstacles, and other ships. Ship collisions do no damage. Projectiles collide authoritatively with the selected map geometry, so cover can stop normal shots and redirect ricochet builds.

Shots cannot spawn through a wall when the ship's nose is pressed against it.

The built-in rotation contains Core Arena, Riftline, Prism Array, Twin Suns, Dead Freight, Longwave Array, Broken Orbit, Switchyard, Solar Tide, and Relay Zero. The server shuffles all ten from the match seed without repeats. Every heat—including tied replays—stays on the round's current map. Winning the round advances the next round to the next map in that deck.

The active map appears in the countdown banner, combat HUD, and live scoreboard. Its synchronized ID controls server collision, projectiles, NPC sightlines/flanking, spawn assignment, overtime navigation, and client presentation.

### 7.5 Overtime

After 90 seconds of active combat, a circular safe zone begins shrinking. The HUD warns five seconds before activation. Ships outside the boundary take continuous damage; once the boundary reaches its minimum size, the damage escalates over time.

Overtime exists to force a conclusion. Watch the boundary, reposition before it cuts off your route, and avoid relying on passive repair to outlast it.

NPC pilots also react to the warning and shrinking radius. An NPC near or outside the boundary prioritizes an inward route over its preferred engagement distance; when cover blocks an engagement, its flank behavior continues to seek a viable firing lane rather than waiting for circle damage to decide the heat.

## 8. Cards and Builds

### Categories

- **Ship** cards modify hull, speed, acceleration, braking, shielded movement, and repair behavior.
- **Shield** cards modify shield economy, coverage, recovery, and mobility.
- **Weapon** cards modify firing, ammunition, damage, projectile behavior, and beam transformations.

Category is a navigation hint, not an isolation rule. Some cards deliberately touch another system to create hybrid builds.

### Rarity

| Tier | Offer-tier weight | Card color |
| --- | ---: | --- |
| Common | 45% | Pale steel |
| Uncommon | 27% | Green |
| Rare | 15% | Cyan |
| Epic | 8% | Violet |
| Legendary | 3.3% | Gold |
| Mythical | 1.2% | Magenta |
| Unobtanium | 0.5% | Hot red |

The displayed percentage is the chance to select that rarity tier for an offer slot when all tiers are eligible. After the tier is chosen, the server selects uniformly among eligible cards in that tier. It is not the exact probability of one named card.

Five offered cards are always distinct. A card may return in a later draft and stacks have no limit.

### How stacking works

For every derived numeric stat:

1. Flat additions from all owned stacks are summed.
2. Multipliers from all owned stacks compound.
3. Integer additions such as extra projectiles, pierces, and ricochets are applied.
4. Broad technical guardrails prevent broken network encoding, physics, or entity budgets.

Acquisition order does not change the result. `×1.20` taken three times means `1.20³`, not a one-time 60% flat bonus.

Auto-repair and beam cards enable behaviors. Other cards can improve repair delay/rate before repair is enabled, creating deliberate setup-and-payoff combinations.

### Reading a card

Each draft card shows:

- Its input number and title.
- Ship, Shield, or Weapon category.
- Exact per-stack effect.
- Current stack transition, such as `STACK 2 → 3`.
- Rarity and rarity-tier weight in smaller text at the bottom.

Cards do not always contain a downside. Higher rarity means scarcity, not a guarantee that the card is correct for the current build.

### Build advice

- Pair projectile count with spread control or pierces instead of evaluating each stat alone.
- Magazine, fire rate, and reload form one sustained-damage economy. Improving only cadence can empty the magazine faster than expected.
- Projectile lifetime and speed both affect practical range; ricochets benefit especially from added lifetime.
- Shield block cost matters more against high projectile counts, while continuous drain matters more during long holds.
- Recovery threshold and regeneration delay solve different depletion problems.
- Repair-rate cards do nothing until a card enables auto-repair, but their stacks remain ready for that future unlock.
- Extreme speed needs acceleration and braking support if the ship is expected to remain controllable.

The complete 120-card reference is in [section 7.3 of the specification](../spec.md#73-catalog).

## 9. HUD, Scoreboard, Spectating, and Menus

The compact upper-left HUD carries match state, round/heat number, countdown or elapsed time, health, shield, and ammunition without taking over the center of the arena.

Hold the configured scoreboard action (`Tab` or View / Back by default) to show live standings. The overlay explicitly identifies the active round map and currently playing gameplay song; menu and victory tracks are not reported there. The overlay is momentary and closes as soon as the action is released. Builds are public after every draft.

When eliminated, you immediately spectate. Use the configured previous/next-target actions (`A`/`D` or the controller bumpers by default) to move among living ships. Late joiners also spectate until the current match returns to the lobby.

Press the configured pilot-menu action (`Escape` or Menu / Start by default) to open the pilot menu. Online combat does not pause: the overlay blocks only your local controls. From it you may resume, open settings, disconnect to the main menu, or quit.

The configured diagnostics action (`F3` or Y / Triangle by default) shows network information such as frame rate, round-trip time, input acknowledgment, prediction error, snapshot count, player count, and projectile count. It is primarily a playtest and troubleshooting tool.

## 10. Settings, Controls, and Audio

Settings are available from the main menu and the in-match pilot menu. They are divided into **Display & Audio** and **Controls** tabs.

Display mode choices:

- **Windowed** uses the selected client-area resolution and is the default.
- **Borderless Fullscreen** uses the desktop's current native resolution; the resolution selector is disabled while this mode is active.
- **Exclusive Fullscreen** requests the selected resolution from the monitor and graphics driver. Unsupported hardware modes may be rejected or scaled by the platform.

Supported selectable resolutions:

- 1280×720
- 1366×768
- 1440×900
- 1600×900
- 1920×1080
- 1920×1200
- 2560×1080 ultrawide
- 2560×1440
- 2560×1600
- 2880×1920
- 3440×1440 ultrawide
- 3840×1080 super-ultrawide
- 3840×1600 ultrawide
- 3840×2160
- 5120×1440 super-ultrawide
- 5120×2160 ultrawide

Wider modes reveal additional horizontal arena space without stretching ships or UI nonuniformly. A 5120×1440 display is supported at 32:9; use Borderless Fullscreen when the desktop already runs at that resolution, or Exclusive Fullscreen to request it directly.

Audio controls include master, music, and effects volume plus a mute toggle.

The Controls tab provides:

- An explicit **Keyboard & Mouse** or **Controller / Joystick** profile selector. Keyboard and mouse is the default until another selection is saved.
- Live connected-controller names. Bindings can also be prepared before a device is connected.
- A controller stick-deadzone slider, defaulting to 22%.
- One binding button for every movement, aim, combat, spectator, draft, and menu-navigation action available to the selected profile.
- **Restore This Profile's Defaults**, which does not overwrite the other profile.

To remap an action, select its binding button and press the replacement key, mouse button, controller button, or joystick axis direction. Axis capture requires a deliberate movement past 65%, which avoids binding ordinary stick drift. Capture times out after eight seconds without changing the binding.

All display, audio, profile, deadzone, and binding settings save automatically to Godot's per-user `super_star_fighter_settings.cfg` and persist between launches.

The game safely runs without authored audio: combat effects are synthesized, victory has a generated fallback, and absent music is skipped. Repository maintainers can add real music and sound effects without code changes by following the [audio drop-in contract](../assets/audio/README.md).

## 11. Offline Combat Lab

The lab is a local sandbox for learning controls and testing card interactions without a server.

| Input | Lab action |
| --- | --- |
| Active keyboard/mouse or controller profile | Normal movement, aim, fire, and shield |
| `Q` / `E` | Select previous / next card |
| `G` | Grant one stack of the selected card |
| `C` | Clear the current build |
| `T` | Toggle target shields |
| `B` | Toggle target firing |
| `Y` | Reset the heat |
| `O` | Start overtime, or reset warning/overtime to a full 90-second clock |
| `Shift+O` | Cycle diagnostic overtime stages |
| `F1` | Toggle laboratory help |

The lab uses shared movement, combat, collision, card, and overtime rules, but it is not a substitute for network testing.

## 12. Disconnects and Rejoining

- Disconnecting during a heat eliminates that participant before survivor resolution.
- Disconnecting in another match state removes the participant from future spawns.
- Joining after a match has started admits the client as a spectator.
- A late spectator becomes a normal lobby participant after the match returns to the lobby.
- Returning to the same lobby after victory supports a clean rematch without reconnecting.

Active-match reconnect restoration is not implemented. A rejoining player does not reclaim their earlier ship/build during the current match.

## 13. Troubleshooting

### The project says Godot is not bootstrapped

Run:

```powershell
.\tools\bootstrap.ps1
```

If files are incomplete, use `-Force`.

### A LAN server does not appear

- Select **Refresh**.
- Confirm both machines are on the same subnet and are not isolated by guest Wi-Fi/VLAN settings.
- Allow UDP `7359` through the host firewall for local discovery.
- Try **Direct Connect** with the host's private LAN address and gameplay port.
- Confirm client and server builds use the same protocol version.

### Direct connection fails

- Confirm the address and UDP gameplay port.
- Confirm the dedicated server reports `server_started` rather than `server_bind_failed`.
- Allow the selected UDP port through the server firewall.
- For internet play, verify the router forwards UDP—not TCP—to the correct internal machine.
- Do not choose gameplay port `7359`.

### The lobby will not start

- Every connected human must be ready.
- Changing rounds, seats, NPC settings, or difficulty clears readiness.
- Without NPCs, at least two humans are required.
- A solo leader must enable NPCs before starting.
- Only the lobby leader can start or change settings.

### I cannot shoot

- Release the shield; firing is disabled while shielding.
- Wait for the automatic reload to finish.
- Confirm the heat is active rather than in READY/countdown/result state.
- Extremely stacked builds still obey the global and per-owner projectile budgets.

### My controller or joystick does not respond correctly

- Open **Settings → Controls** and select **Controller / Joystick**; devices do not take over automatically.
- Confirm the detected-device line lists the hardware. Reconnect it and reopen Settings if needed.
- Use the binding list for nonstandard flight sticks, rudders, or controllers whose physical layout does not match the twin-stick defaults.
- Increase the deadzone if an axis drifts, or reduce it if small deliberate movement is ignored.
- If menus work but the ship does not aim, bind all four aim directions to suitable positive/negative axes.

### My shield is held but shots pass through

The shield is directional. Turn the visible arc toward the incoming projectile. Also check whether the shield is depletion-locked below its recovery threshold.

### The game continues behind the Escape menu

That is intentional for online play. The server never pauses for one client. Use the menu quickly or move to safety before opening it.

### I rejoined and cannot control my old ship

Reconnect restoration is outside the current slice. Mid-match rejoiners spectate until the lobby returns. A connected same-lobby rematch is supported normally.

### Music or sound is missing

- Check master, music, effects, and mute settings.
- Confirm the files use accepted `.mp3`, `.wav`, or `.ogg` extensions and documented paths.
- Let Godot finish importing newly added audio.
- Missing authored effects intentionally fall back to generated audio; missing menu/gameplay music is skipped.

### Performance becomes chaotic late in a match

Hold `F3` to inspect network and entity diagnostics. Card scaling is intentionally excessive, but the server caps active projectiles at 64 per owner and 1024 globally. If diagnosing a regression, record the build, participant count, state, and server log window.

## 14. Hosting Checklist

Before inviting players:

- Run the same revision/build on server and clients.
- Choose a gameplay UDP port other than `7359`.
- Confirm the port is allowed through the host firewall.
- Test LAN discovery or direct connection from a second machine.
- Decide the total seats, round target, and whether NPC fill is appropriate.
- For an internet session, verify UDP forwarding and the public address.
- Ask every human to ready again after the final lobby change.

After the session:

- Let the leader return the victory screen to the lobby before starting another match.
- Stop a dedicated server with `Ctrl+C`.
- Preserve relevant JSON-line server logs when reporting a bug.
- Include reproduction steps, player count, card builds, and whether the problem occurred before or after a rematch.

## 15. Current Limitations

The current vertical slice does not include public matchmaking, a public server directory, accounts, persistent progression, teams, chat, automatic UPnP/NAT traversal, relay hosting, active-match reconnect restoration, manual map selection/voting, advanced map-specific hazards, anti-DDoS infrastructure, or console/mobile/web builds.

Those omissions are deliberate scope boundaries, not hidden menu options.
