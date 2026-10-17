# DoorData.gd
class_name DoorData
extends Resource

@export var id: String = "" # Shared by both directions of an edge.

@export var direction: Vector2i = Vector2i.UP # (0, -1) North, (1, 0) East, etc.
@export var state: DungeonEnums.DoorState = DungeonEnums.DoorState.CLOSED
@export var required_key_type: DungeonEnums.KeyType = DungeonEnums.KeyType.NONE
@export var connected_room_coords: Vector2i
@export var unlock_switch_id: String = "" # Set if unlocked by a switch/lever instead of a key
