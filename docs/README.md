# Super Star Fighter Documentation

This directory holds practical guides at the top level, the authoritative design documents in [`design/`](./design/), and dated reviews and measurement evidence in [`archive/`](./archive/).

## Start Here

| I want to… | Read |
| --- | --- |
| Play, host, join, configure a lobby, or understand the rules | [Player and Host Manual](./MANUAL.md) |
| Set up the source project, understand its architecture, add cards/audio, or run validation | [Development Guide](./DEVELOPMENT.md) |
| Check the exact implemented rule or network contract | [Authoritative Specification](design/spec.md) |
| Understand product intent and deliberate exclusions | [Product Plan](design/plan.md) |
| Review the planned ten-map roster and its full-capacity guarantees | [Ten-Map Expansion Plan](design/maps.md) |
| Track movement fields, destructible cover, and teleporter relays | [Arena Mechanics Roadmap](./ARENA-MECHANICS-ROADMAP.md) |
| Review completed work and acceptance evidence | [Implementation Milestones](design/milestones.md) |
| Review audio startup, memory, crowded-mix evidence, and remaining listening checks | [Audio Study](./archive/AUDIO-STUDY-2026-09-04.md) |
| Add music or replace placeholder sound effects | [Audio Drop-in Contract](../assets/audio/README.md) |
| Check source/asset provenance and engine notices | [Attribution Inventory](./ATTRIBUTION.md) |
| Run the stripped Windows server package | [Dedicated Server Instructions](./SERVER_README.txt) |
| Read historical reviews, studies, and raw measurement evidence | [Archive](./archive/) |

## Document Authority

The documents serve different purposes:

1. `spec.md` is the implementation source of truth. If prose elsewhere conflicts with it, the specification wins.
2. `MANUAL.md` describes the game from a player's and host's perspective.
3. `DEVELOPMENT.md` describes the repository and contributor workflow.
4. `plan.md` records product direction; `maps.md` and `ARENA-MECHANICS-ROADMAP.md` record arena expansion; `milestones.md` records delivery history.

When an intentional gameplay or protocol change lands, update the specification, affected manual passages, tests, and milestone evidence together.
