# DungeonRoomData.gd
class_name DungeonRoomData
extends Resource

## --- GRID & STATE ---
@export_group("Grid Location")
@export var coordinates: Vector2i = Vector2i.ZERO
@export var node_type: DungeonEnums.RoomNodeType = DungeonEnums.RoomNodeType.NORMAL
@export var is_explored: bool = false

## --- EXITS / DOORS ---
@export_group("Exits")
@export var doors: Array[DoorData] = []

## --- COMBAT & ENCOUNTERS ---
@export_group("Encounters")
@export var is_cleared: bool = false
@export var is_boss_room: bool = false
@export var boss_data: EnemyResource # Loaded if is_boss_room == true

# Candidate monster pools for standard auto-combat generation
@export var candidate_enemy_groups: Array[EnemyGroupResource] = []
@export var min_enemy_groups: int = 1
@export var max_enemy_groups: int = 3

## --- ROOM CONTENTS & EVENTS ---
@export_group("Interactables & Events")
@export var chests: Array[RoomInteractable] = []
@export var switches: Array[RoomInteractable] = []
@export var npcs: Array[RoomInteractable] = []
@export var room_event: RoomEvent # Null unless node_type == EVENT
