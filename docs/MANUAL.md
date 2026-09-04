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

Super Star Fighter is a top-down space shooter about mechanical skill, solo or team objectives, and increasingly unreasonable upgrades.

Every match is made of rounds, and every round is made of heats governed by the lobby's selected game mode. Before round one, every pilot receives a private draw of five cards and chooses one. Before later rounds, everyone except the previous solo round winner—or every member of the previous winning team—drafts another card. The cards permanently modify that pilot's build for the remainder of the match.

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

The main screen displays **BETA 10 · VERSION 0.1.0-beta.10** so players can confirm they are using the same build before joining one another.

The splash screen accepts a keyboard, mouse, or controller press immediately and otherwise advances after ten seconds.

The connection screen has three online paths:

- **LAN Servers** discovers compatible sessions on the local subnet.
- **Direct Connect** joins a known hostname or IP address and UDP port.
- **Host Game** starts an authoritative server locally and joins it through the normal network protocol.

The same screen also offers:

- **Offline Combat Lab** for solo movement, combat, card, shield, and overtime experimentation.
- **Settings** for display mode, resolution, audio, controls, and accessibility.
- **Quit** to close the game.

Display names may contain 1–16 visible characters. Unsafe invisible or direction-formatting characters are rejected. International text and emoji are supported; when names are visually confusable, the server adds bounded suffixes such as `#2` for display clarity.

## 4. Hosting and Joining

### 4.1 One-click local hosting

For most playtests, use **Host Game**:

1. Enter your display name.
2. Open the **Host Game** tab.
3. Enter a server name. This is what nearby players see in the LAN list.
4. Choose a gameplay UDP port from `1024` through `65535`. Port `7359` is reserved for discovery and cannot be used for gameplay.
5. Set the required lobby password (1–64 printable characters).
6. Select **Host & Join**.

The game starts an authoritative server inside an isolated multiplayer subtree, then connects your playable client to it over loopback. The host's player does not receive special simulation authority or gameplay advantages.

Closing or disconnecting the hosting client shuts down its in-process server, so use the dedicated server path when the authority should outlive any particular player's window.

### 4.2 Joining from the LAN browser

1. Enter your display name.
2. Open **LAN Servers**.
3. Select **Refresh** if the desired host has not appeared.
4. Review the server name, occupancy, player limit, match state, compatibility, and ping.
5. Join a compatible row. If this address has no remembered password, the game opens **Direct Connect** so you can enter it.

LAN discovery uses UDP port `7359` and works within one broadcast domain. Guest Wi-Fi isolation, VLAN boundaries, VPN routing, or operating-system firewall rules may prevent discovery even when direct connection works.

An incompatible protocol server remains visible but cannot be joined. All players and the server must run compatible builds.

### 4.3 Direct connection

Use **Direct Connect** when you know the server address:

1. Enter a hostname or IPv4/IPv6 address in **Server host or IP**.
2. Enter the server's gameplay UDP port.
3. Enter the lobby password.
4. Optionally enable **Remember password for this server**. The password is saved only in this client's local settings after the server accepts it; a failed guess is never saved.
5. Select **Connect to Server**.

Remembered passwords are keyed by normalized host address and gameplay port, preventing one service at an address from receiving another service's saved credential. They are stored in the game's local settings file, so leave the option off on a shared computer.

For the same computer, use `127.0.0.1`. For another computer on the LAN, use that computer's private address, such as `192.168.1.50`. For an internet server, use its public hostname or public IP.

### 4.4 Dedicated server

From the repository root:

```powershell
.\tools\start-server.ps1 `
    -Port 7000 `
    -ServerName "Friday Fight Night" `
    -AdminPort 7001 `
    -MaxPlayers 32 `
    -RoundsToWin 3
```

The launcher securely prompts for a lobby password and a distinct admin password. Admin passwords must contain 12–64 printable characters; use a long randomly generated value rather than a memorable phrase. The launcher never puts either prompted secret in the process command line, and the dedicated server never saves or remembers them. For unattended startup, put each secret on one line in a separately ACL-protected file outside the repository and pass `-PasswordFile` and `-AdminPasswordFile`; these are read-only operator inputs, not server-managed remembered-password files. `SSF_LOBBY_PASSWORD` and `SSF_ADMIN_PASSWORD` are also accepted as process-environment alternatives; avoid machine-wide environment variables on shared hosts.

Parameters:

| Parameter | Range | Default | Meaning |
| --- | ---: | ---: | --- |
| `Port` | 1024–65535 | 7000 | ENet gameplay UDP port |
| `ServerName` | 1–40 printable characters | Super Star Fighter Server | LAN browser name |
| `PasswordFile` | Readable one-line file | Prompt | Lobby password source for unattended startup |
| `AdminPort` | 0 or 1024–65535 | 0 | Loopback-only TCP admin listener; 0 disables it |
| `AdminPasswordFile` | Readable one-line file | Prompt when admin is enabled | Distinct admin credential source |
| `BanFile` | Writable file path | Godot user-data `server-bans.json` | Persistent blocked-address list |
| `MaxPlayers` | 2–32 | 32 | Maximum server/lobby participant capacity |
| `RoundsToWin` | 1–5 | 3 | Initial lobby round target |

The dedicated process runs headlessly and prints bounded JSON-line events and metrics to standard output. Stop it with `Ctrl+C` when the session is over.

### 4.5 Dedicated-server administration

The admin listener accepts connections only on `127.0.0.1`. Do not expose it through a public TCP proxy. For a remote server, tunnel it with SSH (for example, local port `7001` to server loopback port `7001`) and run the commands locally:

```powershell
.\tools\admin.ps1 -Port 7001 -Command status
.\tools\admin.ps1 -Port 7001 -Command kick -PeerId 4
.\tools\admin.ps1 -Port 7001 -Command ban -PeerId 7
.\tools\admin.ps1 -Port 7001 -Command unblock -Source 203.0.113.8
.\tools\admin.ps1 -Port 7001 -Command set -Setting rounds_to_win -Value 5
.\tools\admin.ps1 -Port 7001 -Command set-password
.\tools\admin.ps1 -Port 7001 -Command shutdown
```

The tool prompts securely for the admin password unless `-AdminPasswordFile` or the process-scoped `SSF_ADMIN_PASSWORD` variable is present. `status` returns a compact health and lobby summary; `players` includes peer IDs and source addresses for moderation. `ban` immediately removes the selected peer and atomically persists its current source address; `kick` removes it without blocking reconnection. The block list accepts valid IP addresses only and is capped at 4,096 entries. Address blocks are useful but are not account bans: shared NATs can affect multiple players and a player can change addresses. Admin authentication failures are throttled across reconnects, authenticated connections expire after five idle minutes, and inbound and outbound messages are bounded. Repeated authentication failures temporarily lock the loopback endpoint, so do not run automated password guessing against a live server.

The `set` command supports `rounds_to_win`, `player_limit`, `npcs_enabled`, `npc_difficulty` (0–4), `game_mode` (0–4), `team_count`, `random_spawn_powerups`, `random_powerup_interval`, `random_powerups_permanent`, `overtime_start`, `server_name`, and `auto_start`. Match-rule changes are rejected during an active match and clear ready states when accepted. Gameplay/admin ports and physical server capacity are restart-only because their sockets and allocation are created at startup. Admin activity is written to the server's JSON-line audit output without passwords or proofs.

Runtime setting and password changes apply to the current server process only. The server does not persist a rotated password. Before restarting, mirror intended long-term values in the launch arguments and update the operator-owned protected lobby-password source. Address blocks are the exception: they are saved immediately to the configured ban file.

### 4.6 Internet hosting and firewalls

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
- Clicks the appearance swatch beside their own roster name to combine an HSV colour with **Solid**, **Zebra Stripes**, **Leopard Spots**, **Checkerboard**, **Racing Stripes**, or **Chevrons**, then selects **Apply Appearance**. **Random Colour** asks the server for a high-contrast colour without changing the selected pattern. Both preferences are remembered for later sessions.
- Selects **Ready for Launch** when prepared.
- Becomes not ready whenever the leader changes a lobby setting.
- May disconnect voluntarily before or during a match.

### Lobby leader

- Selects **Death Match**, **Team Death Match**, **King of the Hill**, **Capture the Flag**, or **Team Capture the Flag** from Match Options. Death Match is the default.
- When Team Death Match is selected, sets **Number of teams** from 2 through 8 without exceeding the player limit.
- Sets **Rounds to win** from 1 through 5.
- Sets the **Player limit** from 2 through server capacity, never above 32 or below the number of connected humans.
- Enables or disables NPC fill.
- Enables **Random Spawn Powerups** when desired. It is off by default.
- Sets random drops from 5 through 90 seconds, chooses whether collected drops expire after the heat or persist through the match, and sets overtime from 30 through 120 seconds.
- Uses the bulk NPC difficulty dropdown to update every NPC together when desired.
- Selects each NPC's difficulty.
- Ejects other waiting human players.
- Starts the match once the launch conditions are satisfied.
- Selects **Exit to Lobby** from final results after the match.

The leader cannot eject players during an active match and cannot eject themselves. Ejected players return to the connection screen with a clear reason.

### Launch conditions

- Every connected human must be ready.
- With NPCs disabled, at least two humans are required.
- With NPCs enabled, one ready human may start with the configured NPC roster.
- In a team mode, every available team must contain at least one participant.

The start button explains whichever requirement is missing. When a normal human lobby is ready it reads **Start Match**; a solo NPC-assisted launch reads **Start Match with NPCs**.

Changing a match option clears human readiness. Changing your own ship appearance clears only your readiness. Every roster swatch previews the authoritative colour and identifies the pattern other players will see, but only your own human-player swatch is clickable. Colour and pattern changes remain a preview until **Apply Appearance** is selected; **Random Colour** asks the server for a high-contrast palette colour while preserving the selected pattern.

### Random Spawn Powerups

When the leader enables this optional rule, one Rare-or-better card can appear at a safe random arena position every 5–90 seconds of active combat (20 seconds by default). King of the Hill enables temporary powerups by default; the other modes start with them off. Fly over a glowing rarity-coloured marker to collect it. The card is added immediately and its stats take effect without waiting for another draft. By default the collected stack expires when the heat ends; the leader may instead make arena drops permanent until the match ends. Humans and NPCs can collect powerups. At most eight uncollected markers may exist at once. Each expires after 60 seconds, when the overtime boundary passes it, or when the heat ends. New markers stay inside the safe zone; a spawn is skipped when no safe position is available.

### Game modes

| Mode | Heat objective |
| --- | --- |
| Death Match | Be the final surviving pilot. |
| Team Death Match | Be the final team with at least one living pilot; the host may configure two through eight teams. |
| King of the Hill | Accumulate 20 seconds alone in the marked point. Leaving or sharing the point pauses scoring without erasing earned time; the hill moves after each round. |
| Capture the Flag | Collect the neutral center flag and carry it back to your marked launch base. |
| Team Capture the Flag | Collect the neutral center flag and carry it to your team's coloured base. |

Every participant row in a team-mode lobby has a team dropdown. **Auto** balances that participant onto the least-populated available team; a specific choice locks them to that team. The host may assign anyone, each human may assign themselves, and any human may assign an NPC. A non-host cannot alter another human's selection. Team Death Match supports two through eight named/coloured teams; Team Capture the Flag stays fixed to **Cyan Team** and **Magenta Team** because each map has two bases. The roster, live standings, and results identify each pilot's team. Friendly projectile, beam, and shield-ram damage is disabled; ships still separate physically so teammates cannot occupy the same space. NPCs do not target or dodge allies and will pursue the active objective.

In team combat, ship labels identify the team number and ally/enemy relationship. Circles mark allies and diamonds mark enemies on ships, ordnance, and offscreen indicators, even when pilots choose identical hull colours. The combat HUD repeats this key.

Flags drop where their carrier dies and can be recovered. An untouched dropped flag returns to the center after eight seconds. King of the Hill and both flag modes respawn eliminated pilots after a five-second countdown. Placement stays inside the current safe zone, avoids occupied positions, and favours distance or cover from enemies and nearby weapons. If no legal position is available, the HUD reports that respawn is waiting for clear space. Respawning grants no invulnerability. Combat deaths alone do not decide an objective heat; completing the objective or reaching the time limit does.

### NPC fill

Enabling NPCs fills all open configured seats immediately. Each waiting NPC appears in the roster and can be configured before launch. The leader may set every NPC together with the bulk dropdown, then override individual rows as needed. If a human joins a full waiting lobby, that human replaces one NPC rather than being rejected. Disabling NPCs removes all waiting NPCs.

NPC difficulty changes behavior, not stats:

| Difficulty | Intended experience |
| --- | --- |
| Passive | Movement target; never fires or shields |
| Easy | Slow reactions, broad aim error, conservative firing |
| Neutral | General-purpose opponent with moderate leading and pressure |
| Skilled | Fast reactions, predictive leading, committed flanks, projectile dodging, and reactive shield use |
| Insane | Every-tick decisions, near-perfect predictive aim, early threat reactions, strong dodging, and relentless closing pressure |

Every NPC uses the same cards, health, weapon rules, movement limits, collision, and damage model as a human.

NPCs respect arena cover and overtime. They do not deliberately fire through blocking geometry. Skilled and Insane pilots predict projectile travel, dodge incoming lanes, shield reactively when impact is imminent, close neutral-range engagements more aggressively, and commit to flanks more readily. When two NPCs lose line of sight behind the same object, one initially holds while the other commits to a deterministic flank. If the obstruction persists for three seconds, the holder takes the opposite route; brief sightline flickers do not restart that clock, while a sustained clear lane resets it. This keeps fights progressing before overtime without turning normal cover use into constant motion. During overtime, moving inside the shrinking safe circle takes priority over ordinary pursuit—even for Passive NPCs.

## 6. Match Flow

### Draft

Every participant drafts before round one. Before later rounds, the pilot who just won the round receives no card; in a team mode, the entire winning team receives that bye. Everyone else receives a comeback draft. This prevents the leader from automatically snowballing through extra upgrades.

Human players see five private cards and have 30 seconds to choose. Hover a choice to open the same rarity-styled graphical stat card used for inspected builds; it previews the compounded build totals after taking that card. Click a card or press `1` through `5`. If the timer expires, the server chooses one of the offered cards. NPC choices are server-owned. When every eligible choice is locked, the draft ends immediately.

Cards with **NO EFFECTIVE BENEFIT** have no improving stat or newly unlocked mechanic in the current build; any displayed drawbacks still apply. You can still choose them. Timeout and NPC picks prefer an offered card with an effective benefit, falling back to the full offer if none qualify. Card ownership remains unlimited, and capped benefits are not converted into another bonus.

The cards apply simultaneously. Builds become public after the draft and can be inspected while holding `Tab`.

### Countdown and BEGIN

Ships spawn at full derived health, full shield energy, and a full magazine. Controls remain locked during the three-second countdown. The center plate shows **READY**, changes to **BEGIN** with `0.10` seconds remaining, and fades through the first `0.10` seconds of active combat.

The camera snaps to your ship at the start of every heat.

### Active heat

Complete the selected mode's heat objective. A solo winner gains one heat win; in team modes, every member shares the team's heat and round score. Two heat wins award the round.

If every remaining ship dies during the same authoritative tick, the heat is a tie: nobody receives a heat win and the heat is replayed after the result screen.

The HUD names the current mode and reports hill control time or flag ownership. The hill has a segmented boundary, a control-progress arc, and explicit neutral, contested, or controller labels. Your own base is labelled **YOUR BASE** or **YOUR TEAM BASE**; other bases identify their owner. Offscreen objective markers show direction and distance: a segmented circle for the hill, a diamond for the flag, and a square for your base. Carrying the flag changes your base marker to **RETURN FLAG**. Overtime applies in every mode. In King of the Hill, the overtime ring follows the hill and stops shrinking at a 350 px diameter, leaving a visible buffer around the 250 px control point. In flag modes, its minimum radius keeps every scoring base inside the safe zone.

### Round and match results

After a non-final round, heat-win counters clear and the next comeback draft begins. The first pilot to reach the configured round target wins the match.

The final victory screen stays open. Its compact standings show rank, pilot, rounds won, and final build; heat wins are omitted because they reset when the deciding round ends. Hover any card in a final build to inspect its per-stack and compounded effects. The lobby leader selects **Exit to Lobby** when the group is ready. Everyone returns to the same connected lobby with builds, scores, and readiness cleared.

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
| `R` | Manually reload a partially used magazine |
| `Q` / `E` | Select the previous / next owned active ability |
| `Shift` | Activate only the selected ability |
| Hold `Tab` | Live standings and public builds |
| `Escape` | Pilot menu; online combat continues |
| `F2` | Return to the main menu online; active sessions require confirmation. In the lab, switch between editor and range |
| `F3` | Network diagnostic overlay |

The controller/joystick profile defaults to:

| Input | During combat and menus |
| --- | --- |
| Left stick | Forward/backward thrust and strafe |
| Right stick | Point ship and weapon |
| Hold right trigger | Automatic fire |
| Hold left trigger | Directional shield |
| X / Square | Manually reload a partially used magazine |
| D-pad left / right during combat | Select the previous / next owned active ability |
| Left Stick Click | Activate only the selected ability |
| Hold View / Back | Live standings and public builds |
| Menu / Start | Pilot menu; online combat continues |
| Y / Triangle | Network diagnostic overlay |
| Left / right bumper while spectating | Cycle living pilots |
| D-pad in menus | Navigate menus and draft cards |
| A / Cross | Confirm |
| B / Circle | Back |

**Relative** is the default flight mode. Movement stays aligned to the screen, so `W` or stick-up always moves upward regardless of aim. **Newtonian** mode instead follows the ship's heading: if the ship faces down, forward input moves down. Select either persistent mode under **Settings → Controls**.

Diagonal input is normalized, so combining directions does not increase top speed.

Every listed gameplay and menu action can be rebound independently under **Settings → Controls**. The keyboard/mouse and controller profiles are stored separately, so changing one does not erase the other. A flight stick, rudder, arcade stick, or other joystick can bind any detected button or positive/negative axis direction; hardware still needs enough independent axes or buttons to provide both movement and aim.

### 7.2 Weapons

The base weapon deals 25 damage, fires four shots per second, holds eight rounds, reloads automatically in 1.5 seconds, and launches projectiles at 900 pixels per second for 2.5 seconds.

When the magazine empties, reload begins automatically. Press the configured manual-reload action (`R` or X / Square by default) to reload a partially used magazine. Firing is disabled during reload and while shielding.

Cards can alter damage, cadence, magazine size, reload, projectile count, spread, speed, lifetime, pierces, ricochets, and knockback. Concussion Rounds and Repulsor Payload push struck ships; a shield block retains only 20% of that push. Beam cards transform shots into fast, short-lived pulse beams while retaining authoritative collision and damage.

Afterburner, Star Mines, Hunter Missiles, and Cloak! are independently selected abilities. Use the previous/next-ability actions (`Q` / `E` or D-pad left / right by default) to cycle through abilities your build owns. The HUD identifies the selected ability. Press the configured Special action (`Shift` or Left Stick Click by default) to activate that ability alone. Other abilities retain their charges and cooldowns. Selecting an empty or cooling-down ability does not automatically spend a different ability. Selection actions can be rebound under **Settings → Controls**.

Afterburner is an active Ship card. Select it and activate Special for a short forward speed and acceleration burst. It has an authoritative cooldown, works for human and NPC pilots, and produces a larger exhaust bloom while active.

Breakaway Thrusters is a passive Rare Ship card. Depleting the shield, or losing at least 30% of maximum hull inside 0.35 seconds, triggers 0.85 seconds of stronger acceleration and braking without granting invulnerability or additional maximum speed. Its base cooldown is eight seconds; each stack reduces that cooldown by 15%. The HUD shows whether it is active, ready, or cooling down.

Star Mines is an active Legendary Weapon card. Select it before using Special. Each stack supplies ten mines at the start of every heat. A mine can be placed immediately and then at most once every three seconds. It arms 0.25 seconds after placement; once armed, it slowly drags itself toward the nearest enemy within 320 pixels. An enemy entering its small trigger radius, direct contact, any projectile hit, or another mine's enlarged 200-pixel blast detonates it for 100 damage. Chain reactions can continue through other armed mines. The HUD shows authoritative remaining charges and cooldown. Mines disappear when their owner is eliminated or the heat ends; objective-mode respawns do not replenish charges within the same heat.

Deployed mines have a protected budget of 16 per owner and 512 across the arena, within the overall 64-per-owner and 1024-global projectile limits. Ordinary gunfire and missiles cannot remove a deployed mine merely by filling the projectile budget; they replace older moving ordnance instead. Deploying beyond a mine limit removes the oldest applicable mine. Budget removal and cleanup do not detonate mines or deal blast damage.

Hunter Missiles is an active Legendary Weapon card. Each stack supplies 20 missiles per heat. Select it and activate Special to launch one, with a one-second cooldown between launches. A missile deals 40 damage and acquires targets within its forward cone and clear line of sight, including while already in flight. It turns toward the target rather than changing direction instantly. The HUD shows remaining charges and cooldown; objective-mode respawns do not replenish the inventory.

Cloak! is an active Legendary Ship card. Select it before using Special. Each stack supplies one use at the start of every heat, with a shared 20-second cooldown between activations. Objective-mode respawns do not replenish uses or clear the cooldown. Activation makes the ship invisible for five seconds and prevents it from firing; any positive hull damage ends invisibility immediately. The local pilot sees a faint outline, opponents see no ship, nameplate, shield, or exhaust, and NPC pilots cannot acquire a cloaked target. The HUD shows authoritative remaining uses, cooldown, and active state.

Cloaked ship state is withheld from every other client, including allies and spectators. Entering or contesting the hill, picking up the flag, or carrying it reveals you. Activating cloak while doing so still spends the use and immediately reveals you. Missiles can still track you; mines can still approach and detonate, and projectiles, collisions, and overtime can still damage you. These visible interactions may reveal clues to your position.

### 7.3 Directional shields

The base shield covers a 120-degree arc centered on the ship's aim. It starts with 100 energy, drains 20 energy per second while held, and spends 25 energy for each blocked projectile or successful shield ram.

A projectile is blocked only if it strikes inside the visible forward arc. Rear and side shots outside the arc continue to the hull. A blocked projectile is consumed even if it had pierces or ricochets remaining.

After shield activity, regeneration waits 1.25 seconds, then restores 30 energy per second. Fully depleting the shield locks it until it reaches the recovery threshold. Cards can modify capacity, drain, regeneration, delay, block cost, recovery threshold, arc, and acceleration while shielding.

Shielding prevents firing and normally reduces acceleration, so timing matters: turn the arc into danger, absorb the burst, then release to shoot and recover maneuverability.

Every shield has Perfect Guard. The first projectile blocked within 0.25 seconds of raising the shield costs 80% less shield energy. The gold guard arc marks the timing window. Blocking once consumes the window, so an opponent can lead with a weaker shot, stagger a volley, wait it out, or attack outside the directional arc.

Kinetic Vent is an Epic Shield card. Blocked projectile damage stores up to 100 vent charge, shown in the HUD. Deliberately releasing the shield with at least 25 charge emits a 240-pixel line-of-sight pulse: hostile projectiles turn away while retaining their original ownership, and exposed enemy ships and armed mines are pushed outward. Shield depletion discards stored charge. Each stack increases push strength by 20%; it does not increase the fixed radius or turn the pulse into damage.

Ordinary collisions remain harmless. A melee card enables shield ramming: strike an enemy while your shield is active and relative impact speed meets the card-derived threshold. Impact speed scales the damage, and each attacker-target pair has a short cooldown so resting contact cannot deal damage every simulation tick. Ramming Shields is the direct serious-damage option and lowers its practical trigger speed by 30%; Kinetic Prow, Impact Capacitor, Breach Vector, Sundering Aegis, and Worldbreaker Prow provide further damage, durability, speed access, and faster repeat impacts.

Nosferatu Shield restores hull equal to a percentage of the incoming projectile damage whenever the shield successfully blocks that hit. Healing is capped at the pilot's card-modified maximum hull.

Rebound Shields is a Legendary Shield card. A projectile blocked by its active shield turns toward the original shooter, changes ownership to the defending pilot, and continues with half its damage and half its remaining range. A projectile can rebound only once; a later shield block absorbs it normally. Reflected kills are credited to the defending pilot, and reflected shots follow that pilot's team-damage rules.

### 7.4 Collision and cover

Ships slide against arena walls, map obstacles, and other ships. Base ship collisions do no damage; only a qualifying card-enabled shield ram deals contact damage. Deterministic separation transfers blocked correction away from walls or cover, searches nearby legal escape positions for unresolved clusters, and gives ships an outward impulse. Local prediction applies the same immediate visual exclusion so two models cannot appear glued together between snapshots. Projectiles collide authoritatively with the selected map geometry; ricochets consume the unused distance after a bounce in the same physics tick and can damage the first enemy reached along that reflected path.

Shots cannot spawn through a wall when the ship's nose is pressed against it.

The built-in rotation contains Core Arena, Riftline, Prism Array, Twin Suns, Dead Freight, Longwave Array, Broken Orbit, Switchyard, Solar Tide, and Relay Zero. The server shuffles all ten from the match seed without repeats. Every heat—including tied replays—stays on the round's current map. Winning the round advances the next round to the next map in that deck.

The active map appears in the countdown banner, combat HUD, and live scoreboard. Its synchronized ID controls server collision, projectiles, NPC sightlines/flanking, spawn assignment, overtime navigation, and client presentation.

### 7.5 Overtime

After the configured 30–120 second delay (45 seconds by default), a circular safe zone begins shrinking. The HUD warns five seconds before activation. Ships outside the boundary take continuous damage; once the boundary reaches its minimum size, the damage escalates over time.

Every heat ends no later than 60 seconds after overtime starts: 105 seconds of active combat with the default settings. The overtime HUD counts down to this deadline. If King of the Hill reaches it, the pilot with the sole highest positive control time wins, including a pilot awaiting respawn. Equal leading control times or no control time produce a draw. Unresolved deathmatch and flag heats also draw. A normal victory completed on the deadline takes precedence. Results identify time-limit endings. This bounds each heat; repeated draws can still extend a match.

Watch the boundary, reposition before it cuts off your route, and avoid relying on passive repair to outlast it.

NPC pilots acquire opponents across the full arena, including opposite-edge spawns. They also react to the warning and shrinking radius. An NPC near or outside the boundary prioritizes an inward route over its preferred engagement distance; when cover blocks an engagement, its flank behavior continues to seek a viable firing lane rather than waiting for circle damage to decide the heat. At collision distance it releases shield/fire and executes a separating sidestep before resuming combat.

## 8. Cards and Builds

### Categories

- **Ship** cards modify hull, speed, acceleration, braking, shielded movement, and repair behavior.
- **Shield** cards modify shield economy, coverage, recovery, mobility, and shield-ram melee damage.
- **Weapon** cards modify firing, ammunition, damage, projectile behavior, beam transformations, and deployable mines.

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

Acquisition order does not change the result. A card showing `+20%` per stack compounds its multiplier: three stacks apply `1.20³`, not a one-time 60% flat bonus.

Auto-repair and beam cards enable behaviors. Other cards can improve repair delay/rate before repair is enabled, creating deliberate setup-and-payoff combinations.

### Reading a card

Each draft card shows:

- Its input number and title.
- Ship, Shield, or Weapon category.
- Exact per-stack effect.
- Current stack transition, such as `STACK 2 → 3`.
- Rarity and rarity-tier weight in smaller text at the bottom.

Draft details show the actual whole-build values before and after the pick. `AT LIMIT` means a technical stat limit reduces or prevents that effect; any other effects, including drawbacks, still apply. The card and confirmation also flag limited effects. For example, another Twin Shot at six projectiles cannot add a seventh projectile, but its damage reduction still applies. Inspect the comparison before confirming.

Click a card or press its `1`–`5` shortcut to stage it, then select **Confirm Pick** to lock it in. Until you confirm, select another card directly or use **Choose Another** (or Back/Escape) to clear the staged choice.

Cards do not always contain a downside. Higher rarity means scarcity, not a guarantee that the card is correct for the current build.

### Build advice

- Pair projectile count with spread control or pierces instead of evaluating each stat alone.
- Magazine, fire rate, and reload form one sustained-damage economy. Improving only cadence can empty the magazine faster than expected.
- Projectile lifetime and speed both affect practical range; ricochets benefit especially from added lifetime.
- Shield block cost matters more against high projectile counts, while continuous drain matters more during long holds.
- Recovery threshold and regeneration delay solve different depletion problems.
- Repair-rate cards do nothing until a card enables auto-repair, but their stacks remain ready for that future unlock.
- Extreme speed needs acceleration and braking support if the ship is expected to remain controllable.

The complete 135-card reference is in [section 7.3 of the specification](../spec.md#73-catalog).

## 9. HUD, Scoreboard, Spectating, and Menus

The compact upper-left HUD carries match state, round/heat number, countdown or elapsed time, health, shield, ammunition, and owned ability resources such as mine inventory, cloak state, Kinetic Vent charge, and Breakaway cooldown without taking over the center of the arena. The upper-right kill feed shows the newest authoritative eliminations first, highlights events involving your pilot, and distinguishes environmental eliminations and disconnects from credited kills. The offline combat lab uses the same feed with locally resolved attribution. Entries fade after five seconds, while the decisive elimination remains visible through the immediate heat or round result. A second compact ammo bar and `AMMO`/`RELOAD` readout stays directly above the local ship for immediate combat awareness. Every ship's in-world health ring is scaled against that pilot's own card-modified maximum, so full health always appears full at the start of a heat.

Combat feedback distinguishes confirmed hull hits from blocked or reflected shots. **HIT** reports damage actually removed from the target's hull, excluding overkill; **SHOT BLOCKED**, **SHOT REFLECTED**, and **PERFECT GUARD** explain defensive outcomes. Your own shield blocks have separate feedback. These confirmations come from the combat simulation, so firing or seeing a predicted projectile does not itself confirm a hit. Misses produce no hull-hit confirmation.

When destroyed, a recap identifies the credited attacker or environment and the damage source: cannon, beam, missile, mine blast, shield ram, or overtime. Where applicable, it explains a reflection, a hit outside the shield arc, a depleted shield, or a mine blast bypassing shields. It also reports the final applied damage. The recap clears for a new life or session.

Hold the configured scoreboard action (`Tab` or View / Back by default) to show live standings. The overlay tracks each pilot's kills across the entire match and explicitly identifies the active round map and currently playing gameplay song; menu and victory tracks are not reported there. The overlay is momentary and closes as soon as the action is released. Match-total kills also appear in the final standings, and builds are public after every draft.

When eliminated, you immediately spectate. Use the configured previous/next-target actions (`A`/`D` or the controller bumpers by default) to move among living ships. Late joiners also spectate until the current match returns to the lobby.

Press the configured pilot-menu action (`Escape` or Menu / Start by default) to open the pilot menu. Online combat does not pause: the overlay blocks only your local controls. From it you may resume, open settings, disconnect to the main menu, or quit.

The configured diagnostics action (`F3` or Y / Triangle by default) shows frame rate, round-trip time and variance, ENet loss/throttle, snapshot jitter and gaps, interpolation extrapolation, prediction error/snaps, pending replay inputs, expired predicted shots, and the latest input acknowledgment. It is primarily a playtest and troubleshooting tool.

## 10. Settings, Controls, and Audio

Settings are available from the main menu and the in-match pilot menu. They have three tabs: **Display & Audio**, **Controls**, and **Accessibility**.

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
- A persistent **Newtonian** ship-facing or **Relative** screen-aligned flight-mode selector.
- Live connected-controller names. Bindings can also be prepared before a device is connected.
- A controller stick-deadzone slider, defaulting to 22%.
- One binding button for every movement, aim, combat, spectator, draft, and menu-navigation action available to the selected profile.
- **Restore This Profile's Defaults**, which does not overwrite the other profile.

To remap an action, select its binding button and press the replacement key, mouse button, controller button, or joystick axis direction. Axis capture requires a deliberate movement past 65%, which avoids binding ordinary stick drift. Capture times out after eight seconds without changing the binding.

The **Accessibility** tab provides:

- **HUD size**, from 100% to 150% in 10% steps, for larger combat text and controls.
- **Disable camera shake and boost kick**, which suppresses both impact shake and Afterburner camera movement.
- **Reduce combat flashes**, which reduces bright hit, shield, elimination, and boost flashes while retaining damage information and impact cues.
- **Keep HUD within a centered 16:9 area**, enabled by default, which keeps important readouts near the center on ultrawide displays. Disable it to use the full display width.

These options apply immediately to online play and the offline laboratory. Navigate settings with `Tab` / `Shift+Tab` or the controller D-pad; left / right adjusts HUD size. The settings tabs and toggles also support controller navigation.

All display, audio, flight-mode, profile, deadzone, binding, and accessibility settings save automatically to Godot's per-user `super_star_fighter_settings.cfg` and persist between launches.

The game safely runs without authored audio: combat effects are synthesized, victory has a generated fallback, and absent music is skipped. Repository maintainers can add real music and sound effects without code changes by following the [audio drop-in contract](../assets/audio/README.md).

## 11. Offline Combat Lab

The lab opens in a paused build editor. It runs the same authoritative combat simulation as the server locally, including movement, collisions, projectiles, shields, active abilities, and damage. It is useful for testing a build without hosting a match; it does not simulate network delay or packet loss.

Search cards by name, description, or rarity, then select a result to inspect its description and actual before/after stat changes. **+ Stack** adds the selected card, **− Stack** removes one stack, and **Clear build** restores the base ship. The build summary lists owned cards, while derived stats show the resulting hull, movement, weapon, shield, and ability values. Search and stat details are scrollable when space is limited.

The preset menu contains **Base ship**, **Rapid scatter**, **Beam specialist**, **Shield tank**, and **All abilities**. Further edits turn a preset into a custom build. The target controls select one through five targets, 10–600 hull HP, and a distance of 160–900 pixels. You can enable target shields, return fire, and strafing independently. With a controller, D-pad left / right changes a focused numeric target control.

Build and target changes reset the encounter, restoring health, ammunition, and ability resources and clearing projectiles and measurements. **Reset encounter** does the same without changing your build or target setup. **Reset measurements** clears only the counters. Targets stay destroyed until the encounter is reset; they do not silently heal or respawn. The default setup is one stationary, unshielded 100-HP target at 420 pixels.

Choose **Enter range** to fly and fight, or **Edit build** to pause and return to the editor. The live readout counts trigger shots, confirmed hull hits, blocked shots, actual hull damage, and measured damage per second. Damage excludes shields and overkill. DPS uses active simulation time since the first shot or hit: misses, projectile travel, and reloads count, while time paused in the editor does not. A spread shot may produce multiple hull hits, so the hit count is not a percentage of trigger shots. The range also shows hit/block confirmations and death explanations.

| Input | Lab action |
| --- | --- |
| Active keyboard/mouse or controller profile | Normal movement, aim, fire, shield, reload, and selected ability |
| `F2` | Switch between paused editor and live range |
| `Enter` or A / Cross while flying | Open the editor |
| `Q` / `E` or D-pad left / right while flying | Select the previous / next owned ability |
| `Shift` or Left Stick Click | Activate only the selected ability |
| `Y` while flying | Reset the encounter |
| `O` while flying | Start overtime, or disable it and reset the elapsed clock |
| `Shift+O` while flying | Cycle overtime warning, active, fully shrunk, and off stages |

Practice is untimed until overtime is explicitly enabled. HUD size, reduced shake, reduced flashes, and the centered HUD preference also apply in the lab. Use the pilot menu to leave the laboratory.

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

Press `F3` to inspect network and entity diagnostics. Card scaling is intentionally excessive, but the server caps active projectiles at 64 per owner and 1024 globally. Deployed mines have protected limits of 16 per owner and 512 globally within those totals; ordinary fire replaces moving ordnance rather than deployed mines. If diagnosing a regression, record the build, participant count, state, and server log window.

## 14. Hosting Checklist

Before inviting players:

- Run the same revision/build on server and clients.
- Choose a gameplay UDP port other than `7359`.
- Expose only the selected gameplay UDP port. Keep the admin TCP port on loopback and reach it through an authenticated SSH tunnel.
- Run the process as a dedicated unprivileged OS account, keep the OS/runtime patched, and restrict read access to password files and write access to the ban file.
- Use unique, randomly generated lobby and admin passwords; the admin password must be at least 12 characters.
- Confirm the gameplay port is allowed through the host firewall and apply provider/host UDP rate limiting when the server is Internet-facing.
- Test LAN discovery or direct connection from a second machine.
- Decide the total seats, round target, and whether NPC fill is appropriate.
- For an internet session, verify UDP forwarding and the public address.
- Ask every human to ready again after the final lobby change.
- Run `status` and watch `simulation_metrics` for p95/max latency and `over_budget_ticks` before the competitive session begins.
- Investigate repeated `AUTH_RATE_LIMITED` rejections: the server caps each source at 63 accepted connection attempts per 60-second window before a one-minute cooldown, in addition to the stricter failed-password limiter.

After the session:

- Let the leader return the victory screen to the lobby before starting another match.
- Stop a dedicated server with `Ctrl+C`.
- Preserve relevant JSON-line server logs when reporting a bug.
- Include reproduction steps, player count, card builds, and whether the problem occurred before or after a rematch.

## 15. Current Limitations

The current vertical slice does not include public matchmaking, a public server directory, accounts, stable player identity, persistent progression, team colour customization, chat, automatic UPnP/NAT traversal, relay hosting, active-match reconnect restoration, manual map selection/voting, advanced map-specific hazards, anti-DDoS infrastructure, replays, or console/mobile/web builds. Server authority rejects invalid state-changing requests, but without stable identity and replay evidence the current build should be treated as suitable for organized semi-competitive play rather than prize-bearing tournament administration.

Those omissions are deliberate scope boundaries, not hidden menu options.
