class_name MatchEventTypes
extends RefCounted

## Match event type names. These values are sent over the wire as the
## `event_type` of a `match_event` RPC, so changing one is a protocol change.
## Use these constants instead of writing the names as literals: a misspelled
## literal compiles and silently never matches.

const STATE_CHANGED := &"STATE_CHANGED"
const DRAFT_OFFER := &"DRAFT_OFFER"
const DRAFT_READY := &"DRAFT_READY"
const DRAFT_RESOLVED := &"DRAFT_RESOLVED"
const PLAYER_ELIMINATED := &"PLAYER_ELIMINATED"
const PLAYER_RESPAWNED := &"PLAYER_RESPAWNED"
const OBJECTIVE_UPDATED := &"OBJECTIVE_UPDATED"
const OBJECTIVE_TRANSITION := &"OBJECTIVE_TRANSITION"
const ARENA_EFFECTS_UPDATED := &"ARENA_EFFECTS_UPDATED"
const CARD_POWERUP_SPAWNED := &"CARD_POWERUP_SPAWNED"
const CARD_POWERUP_REMOVED := &"CARD_POWERUP_REMOVED"
const CARD_POWERUP_COLLECTED := &"CARD_POWERUP_COLLECTED"
const COMBAT_FEEDBACK := &"COMBAT_FEEDBACK"
const MINE_DETONATIONS := &"MINE_DETONATIONS"
const MATCH_PAUSE_CHANGED := &"MATCH_PAUSE_CHANGED"
const MATCH_START_ACCEPTED := &"MATCH_START_ACCEPTED"
const REQUEST_REJECTED := &"REQUEST_REJECTED"
