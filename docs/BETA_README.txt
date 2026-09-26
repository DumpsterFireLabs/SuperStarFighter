SUPER STAR FIGHTER — BETA 17
Version 0.1.0-beta.17

QUICK START

1. Extract the entire ZIP to a writable folder.
2. On Windows, run SuperStarFighter-Beta17.exe.
   On Linux, run: chmod +x SuperStarFighter-Beta17.x86_64 && ./SuperStarFighter-Beta17.x86_64
   On Linux ARM64/Raspberry Pi with a 64-bit OS, run: chmod +x SuperStarFighter-Beta17.arm64 && ./SuperStarFighter-Beta17.arm64
   On macOS, Control-click Super Star Fighter.app, choose Open, then confirm Open.
   If macOS instead says the app is damaged, open Terminal in the extracted folder and run:

     xattr -cr "Super Star Fighter.app"

   Then Control-click the app and choose Open again. Only clear the attributes after verifying
   the supplied SHA-256 checksum; this command is needed because the beta is not notarized.
3. One player chooses Host Game, selects a gameplay TCP port, and chooses Host & Join.
4. Friends on the same local network join from LAN Servers.
5. Internet players use Direct Connect with the host's public IP address and gameplay port.

LINUX AND RASPBERRY PI GRAPHICS FALLBACKS

The normal Linux launch uses Godot's Compatibility renderer through desktop OpenGL 3.3. Start with the ordinary command above. Add --verbose while diagnosing graphics startup so Godot prints the selected renderer, driver, and GPU.

If a Linux machine has native OpenGL ES 3.0 through Mesa but does not expose desktop OpenGL 3.3, try:

  ./SuperStarFighter-Beta17.arm64 --rendering-method gl_compatibility --rendering-driver opengl3_es --verbose

For Linux x64, replace SuperStarFighter-Beta17.arm64 with SuperStarFighter-Beta17.x86_64.

If the machine has a working Vulkan driver, including Mesa V3DV on a suitably configured Raspberry Pi, the Mobile renderer is another possible fallback:

  ./SuperStarFighter-Beta17.arm64 --rendering-method mobile --rendering-driver vulkan --verbose

As a slow last resort on Mesa systems, software rendering may work:

  LIBGL_ALWAYS_SOFTWARE=1 ./SuperStarFighter-Beta17.arm64 --rendering-method gl_compatibility --rendering-driver opengl3 --verbose

These are compatibility suggestions, not native acceptance-tested configurations. Renderer overrides may change appearance or performance, and software rendering can be very slow. Godot 4 requires at least OpenGL ES 3.0 for its Compatibility renderer; GLES 2-only hardware is not supported. Use a current 64-bit OS and current Mesa/V3D drivers on Raspberry Pi.

INTERNET HOSTING

The host must allow the executable through the operating-system firewall and forward the selected TCP gameplay port (7000 by default) in the router. LAN discovery uses UDP 7359 only on the local network. There is no public matchmaking or automatic NAT traversal in Beta 17.

BETA 17 CHANGES

- If your connection drops during a match, the server holds your seat for 90 seconds. Reconnect from the connection screen (without restarting the game) to return with your cards, score, team, name and ship colour.
- If a dropped player's absence would end the match, such as in a 1v1, the match pauses and shows who it is waiting for. If they are not back within 90 seconds, the other side wins by forfeit.
- Returning to the main menu or closing the game gives your seat up straight away. Kicked and banned players never keep a seat.
- The game remembers your display name after you quit.
- Linux server launch scripts keep Unix line endings even when the package is built on Windows.
- Beta 17 cannot connect to Beta 16 or earlier; every player and server must update together (protocol 47). Older clients are told their version does not match.
- Gameplay now runs over TCP (WebSocket) instead of UDP. Hosts forward the TCP gameplay port (7000 by default); no UDP forwarding is needed.
- Players on slow or congested connections now receive fewer but current updates instead of falling seconds behind, and the server uses far less memory per player.
- Quickly changing lobby settings can no longer leave a healthy player stuck on reduced updates, and ejected players always see why they were removed.
- A player whose connection falls too far behind is disconnected instead of silently missing lobby and match messages.
- Direct Connect asks for the port in its own field instead of accepting host:port, and wss:// addresses no longer need a port or lose their remembered password.
- Direct Connect accepts wss:// addresses, so a Linux dedicated server can run behind a Cloudflare Tunnel on port 443 with --bind=127.0.0.1 --behind-proxy and no port forwarding.
- Clients retry briefly when many players join at once, and both sides drop a connection that stays silent for 10 seconds.
- The F3 diagnostics measure round-trip time with a once-per-second ping; UDP loss/throttle readouts are removed.
- Windows x64, Linux x64, Linux ARM64, and universal macOS packages share version 0.1.0-beta.17.

DEDICATED SERVER OPERATION

These ZIPs contain client builds. Standalone dedicated-server packages for Windows x64, Linux x64, and Linux ARM64 are published alongside them on the project's GitHub releases page. Source-based hosting uses the repository's bootstrapped Godot tools.

From the repository root in PowerShell, start a headless server with:

  .\tools\start-server.ps1 -Port 7000 -ServerName "Friday Fight Night" -AdminPort 7001 -MaxPlayers 32 -RoundsToWin 3

The launcher securely prompts for a lobby password and a distinct admin password. Admin passwords must contain 12-64 printable characters. Do not place passwords directly in command-line arguments, source control, shell history, or shared logs.

For unattended startup, store each password as one line in a separately access-controlled file outside the repository:

  .\tools\start-server.ps1 -Port 7000 -ServerName "Friday Fight Night" -AdminPort 7001 -MaxPlayers 32 -RoundsToWin 3 -PasswordFile "C:\ServerSecrets\ssf-lobby.txt" -AdminPasswordFile "C:\ServerSecrets\ssf-admin.txt" -BanFile "C:\ServerData\ssf-bans.json"

The selected gameplay port is TCP (WebSocket) and must be allowed through the firewall. Forward that TCP port at the router for direct internet hosting. UDP 7359 is LAN discovery only. The admin port is TCP but binds only to 127.0.0.1; never expose it directly through a public TCP proxy.

The server prints bounded JSON-line events and simulation metrics to standard output. Preserve the relevant log window when reporting problems. Stop an interactive server with Ctrl+C or use the authenticated shutdown command below.

DEDICATED SERVER MANAGEMENT

Run these commands from the repository root. The tool prompts securely for the admin password; add -AdminPasswordFile with the protected admin-password file for unattended operation.

  .\tools\admin.ps1 -Port 7001 -Command status
  .\tools\admin.ps1 -Port 7001 -Command players
  .\tools\admin.ps1 -Port 7001 -Command kick -PeerId 4
  .\tools\admin.ps1 -Port 7001 -Command ban -PeerId 7
  .\tools\admin.ps1 -Port 7001 -Command block -Source 203.0.113.8
  .\tools\admin.ps1 -Port 7001 -Command unblock -Source 203.0.113.8
  .\tools\admin.ps1 -Port 7001 -Command set -Setting rounds_to_win -Value 5
  .\tools\admin.ps1 -Port 7001 -Command set-password
  .\tools\admin.ps1 -Port 7001 -Command shutdown

For a remote host, tunnel the loopback-only admin endpoint over SSH, then run admin.ps1 locally against the forwarded port:

  ssh -N -L 7001:127.0.0.1:7001 operator@example-server

The set command supports rounds_to_win, player_limit, npcs_enabled, npc_difficulty, game_mode, team_count, random_spawn_powerups, random_powerup_interval, random_powerups_permanent, overtime_start, server_name, and auto_start. Match-rule changes are rejected during an active match and clear ready states when accepted.

status reports health and lobby state; players lists peer IDs and source addresses. kick disconnects without blocking reconnection. ban disconnects the peer and persists its current address. block and unblock manage an address directly. Address blocks can affect multiple people behind one NAT and are not account bans.

Runtime settings and password changes last only for the current server process. Mirror permanent changes in the launch configuration before restarting. The configured ban file is the exception and is updated immediately. Watch simulation_metrics, especially p95/max latency and over_budget_ticks, before competitive sessions.

UNSIGNED BUILD WARNING

These beta executables are not code-signed. Windows SmartScreen may display an unrecognized-app warning, Linux may require the executable permission command shown above, and macOS Gatekeeper may require the Control-click Open flow. Verify the SHA-256 value supplied by the person sharing the build before running it.

KNOWN BETA LIMITATIONS

- Windows x64, Linux x64, Linux ARM64 (including 64-bit Raspberry Pi), and macOS arm64/x86_64 only.
- No standalone dedicated-server package yet; dedicated operation currently requires a source checkout and bootstrapped tools.
- No public server browser, accounts, or chat. Reconnecting into a match works only without restarting the game.
- Map voting and advanced map-specific hazards are not implemented.
- The host's game process is also the authoritative server unless a dedicated server is run from source.

CONTROLS

Keyboard/mouse is the default. Controller and joystick profiles, Newtonian or screen-relative flight, full rebinding, display modes, resolution, and audio controls are available in Settings.

Press R (or X / Square on a controller) to reload manually. Ammo and reload progress appear directly above your ship.

Hold Tab (or View / Back on a controller) during a match to inspect standings, builds, the active map, and the currently playing gameplay track.
