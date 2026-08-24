# Super Star Fighter

Super Star Fighter is a Windows-first, server-authoritative, top-down multiplayer arena shooter built with Godot 4.7.2 and GDScript.

The project is currently implementing the vertical slice described in:

- [Product plan](./plan.md)
- [Authoritative specification](./spec.md)
- [Implementation milestones](./milestones.md)

## Foundation Commands

From PowerShell in the repository root:

```powershell
.\tools\bootstrap.ps1
.\tools\run-editor.ps1
.\tools\run-tests.ps1
.\tools\verify-foundation.ps1
.\tools\start-server.ps1
.\tools\start-client.ps1
```

The bootstrap script downloads the pinned portable Godot release and export templates into the ignored `.tools` directory. Nothing is installed system-wide.

## Current Status

Milestones 0–2 are complete. The default client launches a playable offline combat sandbox backed by the same deterministic combat rules intended for the authoritative server. The project verifier passes 43 startup, parser, and test checks; the headless suite passes 427 assertions and verifies that an intentional failure returns a nonzero exit code.

Milestone 3 (authoritative networking and lobby) is next.

## Offline Sandbox Controls

- `W` / `S`: move forward/back relative to ship aim; `A` / `D`: strafe left/right; mouse: aim with the custom crosshair; left mouse: automatic fire; right mouse: directional shield.
- `Q` / `E`: select a card; `G`: grant one stack; `C`: clear the current build.
- `T`: toggle target shields; `B`: toggle target fire; `Y`: reset the heat.
- `O`: cycle normal time, overtime warning, overtime start, and minimum-radius overtime.
- `F1`: toggle the on-screen help.
