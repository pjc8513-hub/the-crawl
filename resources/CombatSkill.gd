class_name CrawlCombatSkill
extends Resource

@export var id: String = "attack"
@export var display_name: String = "Attack"
@export_enum("attack", "group_damage", "cleave", "heal", "potion", "defend") var kind: String = "attack"
@export_enum("melee", "ranged") var reach: String = "melee"
@export_enum("physical", "fire", "spirit") var element: String = "physical"
@export var power: int = 0
@export var variance: int = 0
@export var mp_cost: int = 0
@export var status_id: String = ""
@export var status_turns: int = 0
@export var status_potency: int = 0


func is_valid() -> bool:
	return id != "" and kind in ["attack", "group_damage", "cleave", "heal", "potion", "defend"] and reach in ["melee", "ranged"] and element in ["physical", "fire", "spirit"] and power >= 0 and variance >= 0 and mp_cost >= 0 and status_turns >= 0 and status_potency >= 0 and status_id in ["", "poison", "stun"]
