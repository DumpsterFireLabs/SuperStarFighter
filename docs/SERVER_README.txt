Super Star Fighter - Dedicated Server (Windows x64 / Linux x64 / Linux ARM64, Beta 15)

WINDOWS QUICK START

Extract the entire ZIP to a writable folder on Windows x64. Open PowerShell
in that folder and run:

  .\start-server.ps1 -Port 7777 -AdminPort 7778 -ServerName "Friday Fight Night" -LogFile .\logs\server.log

The launcher securely prompts for separate lobby and admin passwords. Leave
that PowerShell session running. Players use Direct Connect with the server
address, gameplay port 7777 and lobby password. Once inside the lobby, open
Admin and enter the separate admin password to operate the server. On the
server PC itself, use address 127.0.0.1. The optional admin.ps1 tool uses
the loopback TCP listener on port 7778.
To watch logs in another window: Get-Content .\logs\server.log -Tail 30 -Wait
If Windows marks downloaded scripts as blocked, verify the ZIP checksum and
use Unblock-File on the included start-server.ps1 and admin.ps1 scripts.

The package starts in server mode without graphics or audio. No Godot editor,
source checkout, client assets or separate PCK file is required. Use the same
game/protocol version on clients: 0.1.0-beta.15 (compatibility 45, binary packets 17).

Set the lobby password before starting. The example is not a public password.
Use the --port value when connecting directly. Configure any network/firewall
access appropriate to your host; this package does not change those settings.
Gameplay uses TCP (WebSocket) on the selected port. LAN discovery uses UDP 7359.
Console/server logs report startup, joins, match activity and health every ten
wall-clock seconds, including while idle or paused.

For unattended operation, use the included launcher with secret files containing
one printable line (lobby: 1-64 characters, admin: 12-64, different passwords):

  .\start-server.ps1 -NonInteractive -Port 7777 -MaxPlayers 32 `
    -PasswordFile .\lobby-password.txt -AdminPort 7778 `
    -AdminPasswordFile .\admin-password.txt -LogFile .\logs\server.log

SSF_LOBBY_PASSWORD and SSF_ADMIN_PASSWORD are alternatives to secret files.
Restrict access to those files to the server's OS account. The launcher fails
instead of prompting when -NonInteractive is set and a credential is missing.
It preserves the server exit code. Use a process supervisor to restart on
failure; the launcher does not install an OS service or restart automatically.
Give separate instances distinct gameplay/admin ports, log paths and -BanFile
paths (default bans: Godot user data/server-bans.json).

Remote administration binds only TCP 127.0.0.1. Run these on the server host:

  .\admin.ps1 -NonInteractive -Port 7778 -AdminPasswordFile .\admin-password.txt -Command status
  .\admin.ps1 -NonInteractive -Port 7778 -AdminPasswordFile .\admin-password.txt -Command shutdown

Admin commands time out after five seconds by default (-TimeoutSeconds 1-60).
Use admin shutdown for a final metrics flush and a clean exit. Ctrl+C is a
fallback stop; forced process termination cannot guarantee a final log flush.

Status includes uptime, the latest health window and its age (-1 before the
first window). Healthy sustained operation targets 60 physics callbacks/sec;
investigate full windows below 57, p95 callback work at or above 16.67 ms, or
more than 1% of callbacks exceeding that budget. max_physics_gap_usec exposes
scheduling stalls outside the measured callback. Pausing freezes match ticks
while health callbacks continue. outbound_bytes_per_second is replication
payload traffic, not total wire bandwidth; allow room for protocol overhead
and other control messages. Watch OS memory and network use alongside these
metrics. Arrange host-managed log retention for long-running servers and
preserve failed-run evidence.

Dedicated servers batch tick records and write them on a background worker.
The producer queue is bounded to 262,144 characters; a blocked sink cannot grow
server memory without limit. Admin status exposes queue depth and cumulative
dropped batches. Treat any log_dropped_batches/server_log_overflow as a host
logging problem. mean_logging_usec/max_logging_usec measure main-thread log
submission, not the worker's file I/O. Graceful shutdown drains queued records.

Optional launcher settings: -ServerName, -RoundsToWin (1-5), -CompetitiveView,
and -AutoStart (start on admission once at least two participants are present).
Without -AutoStart, the lobby leader controls match startup.

The executable uses the official Godot template with server-only game resources.
It is not a custom engine binary with renderer code compiled out. This build is
unsigned. Native distribution and representative-hardware release acceptance
are tracked separately.

See THIRD_PARTY_NOTICES.txt and GODOT_COPYRIGHT.txt for engine/component notices.

WINDOWS ADMINISTRATION REFERENCE

Run admin.ps1 on the server host in a second PowerShell session. Each command
prompts for the admin password unless -AdminPasswordFile or SSF_ADMIN_PASSWORD
is supplied. Examples use port 7778; replace the example peer ID/source with
an actual value returned by players.

  .\admin.ps1 -Port 7778 -Command players
  .\admin.ps1 -Port 7778 -Command kick -PeerId 42
  .\admin.ps1 -Port 7778 -Command ban -PeerId 42
  .\admin.ps1 -Port 7778 -Command block -Source '192.0.2.10'
  .\admin.ps1 -Port 7778 -Command unblock -Source '192.0.2.10'
  .\admin.ps1 -Port 7778 -Command set -Setting rounds_to_win -Value 3
  .\admin.ps1 -Port 7778 -Command set -Setting player_limit -Value 16
  .\admin.ps1 -Port 7778 -Command set -Setting competitive_view -Value true
  .\admin.ps1 -Port 7778 -Command set -Setting server_name -Value 'Friday Fight Night'
  .\admin.ps1 -Port 7778 -Command set-password
  .\admin.ps1 -Port 7778 -Command restart-match
  .\admin.ps1 -Port 7778 -Command shutdown

players lists peer IDs, names, source addresses, readiness, spectator status,
and blocked sources. kick disconnects a player; ban also blocks their source.
Source bans can affect other players sharing the same public address.
unblock removes a source ban. Keep the ban file between restarts.

set-password prompts for the NEW LOBBY password after admin authentication.
For unattended rotation, supply SSF_NEW_LOBBY_PASSWORD as well as the admin
credential. Update your launcher's lobby secret file/environment separately
so the intended password survives the next restart. Restart with an updated
admin credential to rotate the admin password.

restart-match starts a fresh match at round one using the current rules and
participants. It resets scores and builds, and requires an active match with at
least two participants. It can interrupt a heat, draft, or results screen.

After joining, open Admin in the online lobby or Server Admin in the pause menu
and enter the separate admin password. The panel uses the existing gameplay
connection: no SSH account, forwarded port or local admin port is needed.
The first human to join leads and can configure the lobby until an admin
unlocks access. That admin then leads; the previous leader's setup controls
become read-only. If every admin locks or leaves, the earliest remaining human
becomes leader again.
It shows status and player IDs and can kick, ban, block, unblock, change live
settings, restart a match or shut down the server. At final results, the leader
or an unlocked admin can add five rounds, start a fresh rematch or return to
the lobby. The results screen also has an Unlock Admin button. Closing the
panel keeps access active for this connection; Lock Admin or disconnecting
revokes it. Set -AdminPasswordFile at launch to enable this even with
-AdminPort 0. Lobby-password changes use the local admin tool.

Gameplay ws:// traffic is not encrypted. Authentication avoids sending the raw
admin password and commands are signed, but a captured exchange permits offline
password guessing. Use a long random admin password. The optional TCP admin
listener stays on loopback; reach it with SSH only for command-line access.

set accepts JSON-style numbers/booleans or text. Available setting names are:
rounds_to_win, player_limit, npcs_enabled, npc_difficulty, game_mode, team_count,
random_spawn_powerups, random_powerup_interval, random_powerups_permanent,
competitive_view, overtime_start, server_name, auto_start.
The server validates ranges and match-state restrictions; check the returned
ok/error fields. Make gameplay configuration changes in the lobby. Ports and
admin credentials require restart. Runtime settings are not a saved server
configuration: reapply them after restart or use supported launcher options.
Use the lobby UI for named game-mode/difficulty choices.

Commands return JSON; exit code 0 indicates success and 1 a rejected command.
Connection/authentication failures also cause a nonzero process exit. Avoid
repeated incorrect passwords, which can temporarily throttle admin access.
The admin endpoint is loopback-only: use a secure remote session onto the
host to run the tool. Do not forward the admin port on your router.

NETWORK AND INSTANCE SETUP

For internet play, allow inbound TCP on your chosen gameplay port and forward
that TCP port to this machine if it is behind a router. Players outside the
LAN need the public address; LAN players use the host's LAN address or LAN
discovery. Carrier-grade NAT may prevent inbound connections. Discovery is
local-only on UDP 7359. In-game admin uses the gameplay connection; the
optional TCP command listener is loopback-only.

Behind Cloudflare (players connect to wss://game.example.com on port 443):
run cloudflared with an ingress rule to http://127.0.0.1:7000 and start the
server with --bind=127.0.0.1 --behind-proxy. No port forwarding is needed.
Proxy mode is required because every player shares the tunnel's address: it
tracks limits per connection, slows logins after repeated wrong passwords
instead of locking everyone out, and disables address bans (kick instead).
See the Player and Host Manual, section 4.7, for the full tunnel setup.

Launcher defaults: gameplay port 7000, TCP admin listener disabled (AdminPort 0), 32 players,
3 rounds to win, auto-start off. Give each instance a writable working folder,
separate ports, log file and explicit -BanFile (for example .\server-bans.json).
Start with a writable existing parent folder for that ban path. Secret paths
and -LogFile paths are resolved relative to your PowerShell working directory.

ROUTINE OPERATION, BACKUP AND UPGRADES

1. Verify startup in the log and run status. Check again after players join.
2. Preserve secret files, ban files and your launcher command/configuration in
   private backups. Do not include credentials in shared diagnostic archives.
3. Use admin shutdown before maintenance. Confirm the launcher exits and the
   log contains SSF_SERVER_GRACEFUL_SHUTDOWN=admin.
4. Extract the next version into a new folder. Retain the previous package for
   rollback, and explicitly reuse the intended secret and ban file paths.
5. Restart, reapply runtime settings and verify status with matching clients.

There is no active-match save/resume across a server restart. Schedule updates
between matches. A supervisor can invoke powershell.exe -NoProfile -File with
the noninteractive launcher arguments above. Configure its working directory,
account, restart delay and log retention explicitly. Test manual startup first.

TROUBLESHOOTING

No startup marker: inspect the log for invalid passwords, file permissions or
a port already in use. Confirm the full ZIP was extracted, including scripts.
No players can connect: check client version, lobby password, TCP port, host
firewall and router forwarding. A local test does not verify internet access.
Admin connection refused: check the server is running with -AdminPort 7778 and
run the tool on the same host. Authentication failure: check the ADMIN secret,
not the lobby secret. Slow operation: inspect ten-second health windows and
OS CPU/memory/network metrics; reduce load and retain logs for investigation.

Windows packages include the server executable, this README, start-server.ps1,
admin.ps1 and both engine notice files. Linux packages include the architecture-
specific executable, start-server.sh, admin.py, this README and both notices. No credentials,
bans, verification logs or development tools belong in the distribution ZIP.

LINUX QUICK START (x64 OR ARM64)

Use x64 for Intel/AMD 64-bit hosts; arm64 for AArch64 hosts, including a
Raspberry Pi with a 64-bit Linux OS. No Godot installation or desktop session
is required. Python 3 is needed only for admin.py. These exports have static
ELF/resource/archive verification on Windows; native Linux launch and load
acceptance still need to be performed on your deployment host.

Extract the matching archive into a writable folder, then cd into that folder:

  tar -xzf SuperStarFighter-Beta15-Server-Linux-x64.tar.gz
  chmod +x start-server.sh SuperStarFighter-Server.x86_64

For ARM64 use the arm64 archive and SuperStarFighter-Server.arm64 instead.
ZIP alternatives contain the same files; run chmod if your extractor drops
executable permissions. Launch scripts use /bin/sh and have Unix line endings.

Prepare private secret files with one printable line each. The following Bash
commands prompt without echoing or placing password values in shell history:

  mkdir -p secrets logs
  chmod 700 secrets
  umask 077
  read -r -s -p 'Lobby password: ' ssf_lobby; printf '\n'
  printf '%s\n' "$ssf_lobby" > secrets/lobby.txt; unset ssf_lobby
  read -r -s -p 'Admin password (12-64 characters): ' ssf_admin; printf '\n'
  printf '%s\n' "$ssf_admin" > secrets/admin.txt; unset ssf_admin

Use different lobby/admin passwords. Start from the extracted folder:

  ./start-server.sh --port=7777 --admin-port=7778 \
    --password-file="$PWD/secrets/lobby.txt" \
    --admin-password-file="$PWD/secrets/admin.txt" \
    --ban-file="$PWD/server-bans.json" \
    --server-name="Friday Fight Night" --max-players=32 --rounds-to-win=3 \
    >> logs/server.log 2>&1

The shell launcher passes game options through unchanged, starts headlessly
and preserves the server's process/exit status. It does not prompt for secrets.
SSF_LOBBY_PASSWORD and SSF_ADMIN_PASSWORD environment variables are alternatives
to files. Use --auto-start or --competitive-view when wanted. The launcher
selects the executable for uname -m; installing the wrong architecture fails.
Use tail -f logs/server.log in another terminal to watch startup and health.

LINUX ADMINISTRATION

Run on the server host from the extracted directory (Python standard library;
no pip dependencies). Omit --admin-password-file to receive a hidden prompt.

  python3 admin.py status --port 7778 --admin-password-file secrets/admin.txt
  python3 admin.py players --port 7778 --admin-password-file secrets/admin.txt
  python3 admin.py kick --port 7778 --peer-id 42
  python3 admin.py ban --port 7778 --peer-id 42
  python3 admin.py block --port 7778 --source 192.0.2.10
  python3 admin.py unblock --port 7778 --source 192.0.2.10
  python3 admin.py set --port 7778 --setting rounds_to_win --value 3
  python3 admin.py set --port 7778 --setting competitive_view --value true
  python3 admin.py set-password --port 7778 --new-password-file secrets/new-lobby.txt
  python3 admin.py shutdown --port 7778 --admin-password-file secrets/admin.txt

Replace peer/source examples with real values from players. Command semantics,
settings and persistence rules are the same as the Windows reference above.
--non-interactive rejects missing credentials; --timeout defaults to 5 seconds
(range 1-60). Authentication, connection and server rejection failures return
nonzero. Update your startup secret file after changing the lobby password.
Use admin shutdown for guaranteed graceful logging drain. Ctrl+C/SIGTERM may
stop the process without the same application-level shutdown sequence.

OPTIONAL SYSTEMD SERVICE

For systemd hosts, an operator can install into /opt/ssf-beta12 and create a
dedicated unprivileged account named ssf. Give that account read/execute access
to the package and private read access to secrets. Create /var/lib/ssf owned
by ssf for writable state. Adjust every path/account before installing this
example as /etc/systemd/system/ssf.service:

  [Unit]
  Description=Super Star Fighter Beta 15 dedicated server
  After=network.target

  [Service]
  Type=simple
  User=ssf
  Group=ssf
  WorkingDirectory=/var/lib/ssf
  Environment=HOME=/var/lib/ssf
  UMask=0077
  ExecStart=/opt/ssf-beta12/start-server.sh --port=7777 --admin-port=7778 --password-file=/var/lib/ssf/secrets/lobby.txt --admin-password-file=/var/lib/ssf/secrets/admin.txt --ban-file=/var/lib/ssf/server-bans.json --max-players=32
  ExecStop=/usr/bin/python3 /opt/ssf-beta12/admin.py shutdown --port 7778 --admin-password-file /var/lib/ssf/secrets/admin.txt --non-interactive
  Restart=on-failure
  RestartSec=5
  TimeoutStopSec=20
  StandardOutput=journal
  StandardError=journal

  [Install]
  WantedBy=multi-user.target

After checking the paths and testing manual startup as the service account:

  sudo systemctl daemon-reload
  sudo systemctl enable --now ssf
  sudo systemctl status ssf
  sudo journalctl -u ssf -f
  sudo systemctl stop ssf

ExecStop requests authenticated graceful shutdown; systemd may terminate the
process if that fails or exceeds the timeout. Confirm the graceful marker in
the journal. Configure journal retention on the host. This is an operator-
installed service example, not an installer or a native-tested deployment.
