class_name CrawlItemDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export_enum("weapon", "armor", "charm") var slot: String = "weapon"
@export var attack: int = 0
@export var magic: int = 0
@export var armor: int = 0
@export var max_hp: int = 0
@export var max_mp: int = 0
@export var initiative: int = 0
@export var status_chance_bonus: int = 0
@export var freeze_thaw_penalty: int = 0


func bonuses() -> Dictionary:
	return {"attack": attack, "magic": magic, "armor": armor, "max_hp": max_hp, "max_mp": max_mp, "initiative": initiative, "status_chance_bonus": status_chance_bonus, "freeze_thaw_penalty": freeze_thaw_penalty}


func summary() -> String:
	var labels := {"attack": "Attack", "magic": "Magic", "armor": "Armor", "max_hp": "Max HP", "max_mp": "Max MP", "initiative": "Initiative", "status_chance_bonus": "Status chance", "freeze_thaw_penalty": "Freeze hold"}
	var lines: Array[String] = []
	for stat in bonuses():
		var value: int = bonuses()[stat]
		if value != 0:
			lines.append("%+d %s" % [value, labels[stat]])
	return " · ".join(lines)


func is_valid() -> bool:
	if id == "" or display_name == "" or slot not in ["weapon", "armor", "charm"]:
		return false
	for value in bonuses().values():
		if value < 0:
			return false
	return true
