class_name CrawlProgressionDefinition
extends Resource
## Authored economy and purchase composition. Maps are derived compatibility views.

@export var starting_party: Array[CrawlClassDefinition] = []
@export var maximum_slots: int = 6
@export var slot_costs: Array[int] = []
@export var maximum_skill_rank: int = 3
@export var upgrades: Array[CrawlUpgradeDefinition] = []

var starting_slots: int:
	get: return starting_party.size()
var class_costs: Dictionary:
	get: return _values("class", "cost")
var rank_costs: Dictionary:
	get: return _values("rank", "cost")
var power_per_rank: Dictionary:
	get: return _values("rank", "power_per_rank")
var skill_unlocks: Dictionary:
	get:
		var result: Dictionary = {}
		for upgrade in upgrades:
			if upgrade.kind == "skill":
				result[upgrade.skill.id] = {"class": upgrade.class_definition.id, "cost": upgrade.cost}
		return result


func starting_class_ids() -> Array[String]:
	var result: Array[String] = []
	for definition in starting_party:
		result.append(definition.id)
	return result


func _values(kind: String, field: String) -> Dictionary:
	var result: Dictionary = {}
	for upgrade in upgrades:
		if upgrade.kind == kind:
			result[upgrade.purchase_id()] = upgrade.get(field)
	return result
