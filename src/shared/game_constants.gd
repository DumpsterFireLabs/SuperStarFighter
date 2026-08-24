class_name GameConstants
extends RefCounted

const GAME_NAME: String = "Super Star Fighter"
const ENGINE_VERSION: String = "4.7.2"
const PROTOCOL_VERSION: int = 1

const DEFAULT_PORT: int = 7000
const MIN_PORT: int = 1024
const MAX_PORT: int = 65535

const DEFAULT_MAX_PLAYERS: int = 32
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 32

const DEFAULT_ROUNDS_TO_WIN: int = 3
const MIN_ROUNDS_TO_WIN: int = 1
const MAX_ROUNDS_TO_WIN: int = 5

const PHYSICS_TICKS_PER_SECOND: int = 60
const INPUT_SEND_RATE: int = 30
const PLAYER_SNAPSHOT_RATE: int = 20
const PROJECTILE_CORRECTION_RATE: int = 5

const DRAFT_DURATION_SECONDS: float = 20.0
const COUNTDOWN_DURATION_SECONDS: float = 3.0
const HEAT_RESULT_DURATION_SECONDS: float = 3.0
const ROUND_RESULT_DURATION_SECONDS: float = 4.0
const MATCH_RESULT_DURATION_SECONDS: float = 10.0
const HEAT_WINS_TO_WIN_ROUND: int = 2
const CARD_OFFER_SIZE: int = 5

