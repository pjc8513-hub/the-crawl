class_name FloorDefinition
extends Resource

@export var floor_depth: int = 1
@export var theme_name: String = "Catacombs"

@export_group("Generation")
@export_range(6, 64) var min_rooms: int = 10
@export_range(6, 64) var max_rooms: int = 14
@export_range(3, 32) var spine_rooms: int = 6
@export_range(0.0, 1.0) var loop_chance: float = 0.15
@export_range(1, 32) var generation_attempts: int = 8
@export var encounter_budget: int = 24
@export_range(1, 4) var max_encounter_groups: int = 4

## VARIANT ROLL
@export var available_variants: Array[String] = ["Standard", "Infested", "Arcane Anomaly", "Cursed"]

## SPAWN CHANCES (0.0 to 1.0)
@export_range(0.0, 1.0) var side_dungeon_chance: float = 0.25
@export_range(0.0, 1.0) var rare_npc_chance: float = 0.15

## EVENT & ENEMY POOLS
@export var standard_enemy_pool: Array[EnemyGroupResource] = []
@export var variant_enemy_pools: Dictionary = {} # Maps "Infested" -> [Spider_Horde, Rat_Swarm]
@export var possible_events: Array[RoomEvent] = []
@export var possible_bosses: Array[EnemyResource] = []
