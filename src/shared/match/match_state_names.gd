class_name MatchStateNames
extends RefCounted

## Match state names as published in the match payload's `state_name`. They
## are the `MatchStateMachine.State` key names; a unit test keeps the two in
## step. Compare `state_name` against these, never against a bare literal.

const LOBBY := "LOBBY"
const DRAFT := "DRAFT"
const COUNTDOWN := "COUNTDOWN"
const ACTIVE_HEAT := "ACTIVE_HEAT"
const HEAT_RESULT := "HEAT_RESULT"
const ROUND_RESULT := "ROUND_RESULT"
const MATCH_RESULT := "MATCH_RESULT"

const ALL: Array[String] = [LOBBY, DRAFT, COUNTDOWN, ACTIVE_HEAT, HEAT_RESULT, ROUND_RESULT, MATCH_RESULT]
