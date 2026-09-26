# How To: Host on an Ubuntu VPS Behind a Cloudflare Tunnel

This guide runs the Linux dedicated server on an Ubuntu machine (a VPS or a home box) and publishes it through a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/). Players connect to a `wss://` address on port 443. Nothing listens on a public port, so there is no router port forwarding, no firewall opening, and it works behind carrier-grade NAT.

```text
Player ──wss:// 443──→ Cloudflare edge ──tunnel (outbound from your host)──→ cloudflared ──ws://127.0.0.1:7000──→ game server
```

There are two setups:

- [Part A — Temporary tunnel](#part-a--temporary-tunnel): one command, a random `https://….trycloudflare.com` address, no domain or account. Good for a quick session or testing.
- [Part B — Permanent tunnel](#part-b--permanent-tunnel): your own `wss://game.example.com`, the server and tunnel start at boot.

Both need Beta 16 (`0.1.0-beta.16`, protocol 46) or later on every client and the server.

## Requirements

- Ubuntu 22.04 or 24.04, x86_64 or arm64, with outbound internet access and `sudo`.
- The matching server package from `builds/beta-16/`:
  - x86_64: `server-linux-x86_64/SuperStarFighter-Beta16-Server-Linux-x64.tar.gz`
  - arm64: `server-linux-arm64/SuperStarFighter-Beta16-Server-Linux-arm64.tar.gz`
- Python 3 for the admin tool (preinstalled on Ubuntu).
- Part B only: a domain whose DNS is managed by Cloudflare (a free account is enough).

Check the architecture with `uname -m` (`x86_64` or `aarch64`).

Copy the package to the host, for example:

```bash
scp SuperStarFighter-Beta16-Server-Linux-x64.tar.gz you@your-vps:~
```

## Install cloudflared (both parts)

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
cloudflared --version
```

## Part A — Temporary tunnel

1. Unpack the server into a folder. The archive has no top-level folder of its own.

   ```bash
   mkdir -p ~/ssf && cd ~/ssf
   tar -xzf ~/SuperStarFighter-Beta16-Server-Linux-x64.tar.gz
   chmod +x start-server.sh SuperStarFighter-Server.*
   ```

2. Start the server listening only on loopback, in proxy mode. The password prompt keeps it out of shell history and the process list.

   ```bash
   read -r -s -p 'Lobby password: ' SSF_LOBBY_PASSWORD; printf '\n'; export SSF_LOBBY_PASSWORD
   ./start-server.sh --port=7000 --bind=127.0.0.1 --behind-proxy --server-name="Quick Match"
   ```

   Wait for `SSF_MODE_READY=server port=7000`.

3. In a second terminal, start the temporary tunnel:

   ```bash
   cloudflared tunnel --url http://127.0.0.1:7000
   ```

   It prints an address such as `https://random-words-here.trycloudflare.com`.

4. Players choose **Direct Connect**, enter the same address with `wss://` instead of `https://` (for example `wss://random-words-here.trycloudflare.com`), and the lobby password. The port field is ignored for `wss://` addresses.

5. Stop with `Ctrl+C` in both terminals when you are done.

Notes:

- The address changes every time `cloudflared tunnel --url` starts, and Cloudflare offers no uptime guarantee for temporary tunnels. Use Part B for anything you want to keep.
- A temporary tunnel will not start while `~/.cloudflared/config.yml` exists. Rename it for the session if you also have a permanent tunnel.
- To keep the session alive after you disconnect from SSH, run both commands inside `tmux` or `screen`.

## Part B — Permanent tunnel

### B1. Install the server under /var/opt/ssf

Program files stay owned by root; the `ssf` service account can only write to `state/`.

```text
/var/opt/ssf/          root:root  755   server package (binary, start-server.sh, admin.py, docs)
/var/opt/ssf/state/    ssf:ssf    700   service HOME: Godot user data and engine logs, ban list
```

```bash
sudo useradd --system --no-create-home --home-dir /var/opt/ssf/state --shell /usr/sbin/nologin ssf
sudo mkdir -p /var/opt/ssf/state
sudo tar -xzf ~/SuperStarFighter-Beta16-Server-Linux-x64.tar.gz -C /var/opt/ssf
sudo chown root:root /var/opt/ssf && sudo chmod 755 /var/opt/ssf
sudo chmod 755 /var/opt/ssf/start-server.sh /var/opt/ssf/SuperStarFighter-Server.*
sudo chown ssf:ssf /var/opt/ssf/state && sudo chmod 700 /var/opt/ssf/state
```

`state/` must exist before the service starts; systemd refuses to start (`status=226/NAMESPACE`) if a `ReadWritePaths=` directory is missing.

### B2. Create the game server service

Create `/etc/systemd/system/ssf.service` with `sudo nano /etc/systemd/system/ssf.service`:

```ini
[Unit]
Description=Super Star Fighter dedicated server
After=network-online.target
Wants=network-online.target

[Service]
User=ssf
Group=ssf
WorkingDirectory=/var/opt/ssf/state
Environment=HOME=/var/opt/ssf/state
Environment="SSF_LOBBY_PASSWORD=change-me-lobby"
Environment="SSF_ADMIN_PASSWORD=change-me-admin-12+"
UMask=0077
ExecStart=/var/opt/ssf/start-server.sh --port=7000 --bind=127.0.0.1 --behind-proxy --admin-port=7778 --ban-file=/var/opt/ssf/state/server-bans.json --server-name="Friday Fight Night" --max-players=32
ExecStop=/usr/bin/python3 /var/opt/ssf/admin.py shutdown --port 7778 --non-interactive
Restart=on-failure
RestartSec=5
TimeoutStopSec=20
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/opt/ssf/state
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Password rules:

- Lobby password: 1–64 printable characters. Admin password: 12–64 printable characters. They must differ.
- Keep each value inside the quotes. Write a literal `%` as `%%`, and put `\` before any `"` or `\`.
- Keep `ExecStart=` on one line.

Lock the file (it contains the passwords), then start the server:

```bash
sudo chmod 600 /etc/systemd/system/ssf.service
sudo systemctl daemon-reload
sudo systemctl enable --now ssf
sudo journalctl -u ssf -f          # expect SSF_MODE_READY=server port=7000
```

Anyone with `sudo` can read the passwords in the unit file, and some systemd versions show `Environment=` values to local users through `systemctl show`. That is fine on a machine only you log into; on a shared machine, move the two `Environment=` lines into a root-only `EnvironmentFile=`.

### B3. Create the tunnel

**Option 1 — Cloudflare dashboard (simplest):**

1. Open **Zero Trust → Networks → Tunnels → Create a tunnel → Cloudflared** and name it `ssf`.
2. Copy the displayed command and run it on the host. It installs `cloudflared` as a service that starts at boot:

   ```bash
   sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
   ```

3. Under **Public Hostname**, add: subdomain `game`, your domain, **Type** `HTTP`, **URL** `127.0.0.1:7000`.

**Option 2 — command line:**

```bash
cloudflared tunnel login                       # opens a browser link to authorise your domain
cloudflared tunnel create ssf                  # prints the tunnel ID and writes ~/.cloudflared/<tunnel-id>.json
cloudflared tunnel route dns ssf game.example.com
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/<tunnel-id>.json /etc/cloudflared/
sudo chmod 600 /etc/cloudflared/<tunnel-id>.json
```

Create `/etc/cloudflared/config.yml`:

```yaml
tunnel: ssf
credentials-file: /etc/cloudflared/<tunnel-id>.json
region: us                  # optional: keep the tunnel on US data centres
ingress:
  - hostname: game.example.com
    service: http://127.0.0.1:7000
  - service: http_status:404
```

Install it as a boot service:

```bash
sudo cloudflared service install
```

### B4. Start the tunnel and confirm

```bash
sudo systemctl enable --now cloudflared
sudo journalctl -u cloudflared -f      # expect "Registered tunnel connection"
```

Players choose **Direct Connect** and enter `wss://game.example.com` and the lobby password.

After a reboot both `ssf` and `cloudflared` start on their own. Start order does not matter; if the tunnel is up first, joins fail briefly until the game server is ready.

To keep a dashboard-created tunnel on US data centres, run `sudo systemctl edit --full cloudflared`, add `--region us` to its `ExecStart=` line, and `sudo systemctl restart cloudflared`. This affects only your host's side of the tunnel; each player always enters Cloudflare at their nearest data centre.

## Cloudflare settings that keep players from being blocked

The game client is not a browser and cannot solve a Cloudflare challenge page, so any challenge becomes a failed connection. For your domain in the Cloudflare dashboard:

1. **Security → Bots:** turn **Bot Fight Mode** off. On the free plan it applies to the whole domain.
2. **Security → Settings:** keep **Security Level** at Medium or lower and never enable **I'm Under Attack** mode.
3. **Rules → Configuration Rules:** for *Hostname equals `game.example.com`*, turn **Browser Integrity Check** off.
4. **Security → WAF → Custom rules:** for the same hostname, use **Skip** so custom rules and country blocks do not apply.
5. Do not put a **Zero Trust Access** application on the game hostname.
6. **Network → WebSockets** must be on (the default).

Blocked or challenged connections appear under **Security → Events** with the rule responsible. A player whose own network blocks Cloudflare needs a different network or a VPN.

## Why --bind and --behind-proxy

- `--bind=127.0.0.1` makes the server listen only on the machine itself, so it can be reached only through the tunnel. Do not open port 7000 in `ufw` or a VPS security group; only SSH needs to be reachable.
- `--behind-proxy` is required behind any reverse proxy. Godot's WebSocket server cannot read Cloudflare's forwarded client address, so every player appears to come from the tunnel. Proxy mode tracks limits per connection instead of per address, slows new logins to one per second after eight wrong passwords in a minute instead of locking everyone out, and refuses address bans (kick players instead).

## Administration

The admin tool prompts for the admin password without echoing it:

```bash
python3 /var/opt/ssf/admin.py status  --port 7778
python3 /var/opt/ssf/admin.py players --port 7778
python3 /var/opt/ssf/admin.py kick    --port 7778 --peer-id 42
```

`ban` and `block` are refused in proxy mode. In-game admin also works through the tunnel: open **Admin** in the lobby and enter the admin password. Never add port 7778 to the tunnel; it is loopback-only by design.

Logs: `sudo journalctl -u ssf -f` for the game server, `sudo journalctl -u cloudflared -f` for the tunnel.

## Upgrading

```bash
sudo systemctl stop ssf
sudo tar -xzf ~/SuperStarFighter-BetaNN-Server-Linux-x64.tar.gz -C /var/opt/ssf
sudo chmod 755 /var/opt/ssf/start-server.sh /var/opt/ssf/SuperStarFighter-Server.*
sudo systemctl start ssf
```

`state/` and the service file are not part of the package and are left unchanged. Clients and server must run the same version.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `status=226/NAMESPACE` and "Failed to set up mount namespacing: …/state" | `/var/opt/ssf/state` is missing. Create it (B1), then `sudo systemctl reset-failed ssf && sudo systemctl start ssf`. |
| `Set --admin-password-file or SSF_ADMIN_PASSWORD to 12–64 printable characters…` | The admin password is shorter than 12 characters, or the `SSF_ADMIN_PASSWORD` line is missing. Fix the unit, `daemon-reload`, restart. |
| `The admin password must differ from the lobby password.` | Use two different passwords. |
| Client says it cannot reach the server | Check `systemctl status ssf cloudflared`, that the address starts with `wss://`, and that the public hostname points at `HTTP 127.0.0.1:7000`. |
| Client connects then is rejected with a version mismatch | Client and server versions differ; update both. |
| Players connect from some networks but not others | Check **Security → Events** and the settings above. |
| Temporary tunnel refuses to start | Rename `~/.cloudflared/config.yml` while using `cloudflared tunnel --url`. |

## Limits to expect

- Every player's traffic flows through your host's upload bandwidth; check it before hosting a full 32-player lobby.
- Cloudflare adds a relay hop, so round-trip time is slightly higher than a direct connection.
- Cloudflare occasionally closes long-lived WebSocket connections during its own maintenance. The game cannot restore a player into an active match, so a dropped player rejoins as a spectator until the next match. The client's once-per-second ping keeps idle lobbies from hitting Cloudflare's WebSocket idle timeout.
