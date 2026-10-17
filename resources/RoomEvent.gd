# RoomEvent.gd
class_name RoomEvent
extends Resource

@export var event_id: String
@export var title: String
@export var description: String
@export var choices: Array[Dictionary] = [
	# Example: {"text": "Drink from Altar", "result_type": "HEAL", "value": 50},
	# Example: {"text": "Desecrate Altar", "result_type": "AMBUSH", "enemy_group_id": "ghost_horde"}
]
