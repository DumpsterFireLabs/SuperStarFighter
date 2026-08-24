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
.\tools\start-server.ps1
.\tools\start-client.ps1
```

The bootstrap script downloads the pinned portable Godot release and export templates into the ignored `.tools` directory. Nothing is installed system-wide.

## Current Status

Milestones 0 and 1 are complete. The repository now includes the pinned self-contained Godot toolchain, startup modes, deterministic shared rules, all 16 card resources, seeded draft handling, and the UI-independent match state machine. The headless suite passes 345 assertions and verifies that an intentional failure returns a nonzero exit code.

Milestone 2 (offline combat sandbox) is next.
