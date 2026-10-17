# RoomInteractable.gd
class_name RoomInteractable
extends Resource

@export var id: String
@export_enum("Chest", "Switch", "NPC", "Shrine") var type: String = "Chest"
@export var name: String = "Wooden Chest"
@export var is_triggered: bool = false

# Chest properties
@export var chest_loot_table_id: String = "" # Draws 3 choices on open

# Switch / Lever properties
@export var target_door_id: String = "" # Links to DoorData.unlock_switch_id

# NPC properties
@export var npc_dialogue_id: String = ""
@export var offers_merchant_shop: bool = false
