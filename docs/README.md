# Super Star Fighter Documentation

This directory separates practical guidance from the authoritative implementation documents in the repository root.

## Start Here

| I want to… | Read |
| --- | --- |
| Play, host, join, configure a lobby, or understand the rules | [Player and Host Manual](./MANUAL.md) |
| Set up the source project, understand its architecture, add cards/audio, or run validation | [Development Guide](./DEVELOPMENT.md) |
| Check the exact implemented rule or network contract | [Authoritative Specification](../spec.md) |
| Understand product intent and deliberate exclusions | [Product Plan](../plan.md) |
| Review completed work and acceptance evidence | [Implementation Milestones](../milestones.md) |
| Add music or replace placeholder sound effects | [Audio Drop-in Contract](../assets/audio/README.md) |

## Document Authority

The documents serve different purposes:

1. `spec.md` is the implementation source of truth. If prose elsewhere conflicts with it, the specification wins.
2. `MANUAL.md` describes the game from a player's and host's perspective.
3. `DEVELOPMENT.md` describes the repository and contributor workflow.
4. `plan.md` records product direction; `milestones.md` records delivery history.

When an intentional gameplay or protocol change lands, update the specification, affected manual passages, tests, and milestone evidence together.
