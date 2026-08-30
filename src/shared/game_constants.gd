class_name GameConstants
extends RefCounted

const GAME_NAME: String = "Super Star Fighter"
const GAME_VERSION: String = "0.1.0-beta.6"
const RELEASE_LABEL: String = "BETA 6"
const ENGINE_VERSION: String = "4.7.2"
const PROTOCOL_VERSION: int = 14

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

const DRAFT_DURATION_SECONDS: float = 30.0
const COUNTDOWN_DURATION_SECONDS: float = 3.0
const HEAT_RESULT_DURATION_SECONDS: float = 2.0
const ROUND_RESULT_DURATION_SECONDS: float = 2.0
const HEAT_WINS_TO_WIN_ROUND: int = 2
const CARD_OFFER_SIZE: int = 5

const ARENA_SIZE: Vector2 = Vector2(3200.0, 1800.0)
const SHIP_COLLISION_RADIUS: float = 20.0
const PROJECTILE_RADIUS: float = 5.0
const PROJECTILE_LIFETIME_SECONDS: float = 2.5
const SHIELD_BLOCK_COST: float = 25.0
const SHIELD_DEPLETION_THRESHOLD: float = 25.0
const SHIELD_ACCELERATION_FACTOR: float = 0.75
const MAX_PROJECTILES_PER_OWNER: int = 64
const MAX_PROJECTILES_GLOBAL: int = 1024
const DEAD_OWNER_PROJECTILE_LIFETIME: float = 0.5

const OVERTIME_START_SECONDS: float = 45.0
const OVERTIME_WARNING_SECONDS: float = 5.0
const OVERTIME_SHRINK_SECONDS: float = 45.0
const OVERTIME_MINIMUM_RADIUS: float = 120.0
const OVERTIME_BASE_DAMAGE_PER_SECOND: float = 30.0
const OVERTIME_DAMAGE_STEP_SECONDS: float = 10.0
const OVERTIME_DAMAGE_STEP: float = 10.0
const OVERTIME_MAX_DAMAGE_PER_SECOND: float = 100.0
