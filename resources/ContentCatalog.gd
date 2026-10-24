class_name CrawlContentCatalog
extends Resource
## Explicit ordered references work in exported builds and preserve seeded pools.

@export var skills: Array[CrawlCombatSkill] = []
@export var classes: Array[CrawlClassDefinition] = []
@export var items: Array[CrawlItemDefinition] = []
@export var enemies: Array[EnemyResource] = []
@export var progression: CrawlProgressionDefinition


func errors() -> Array[String]:
	var result: Array[String] = []
	for collection in [skills, classes, items, enemies]:
		var seen: Dictionary = {}
		for definition in collection:
			if definition == null or definition.id == "":
				result.append("Catalog contains a missing definition or empty ID.")
				continue
			if seen.has(definition.id):
				result.append("Duplicate content ID: " + definition.id)
			seen[definition.id] = true
	for skill in skills:
		if skill != null and not skill.is_valid():
			result.append("Invalid skill: " + skill.id)
	for item in items:
		if item != null and not item.is_valid():
			result.append("Invalid item: " + item.id)
	for definition in classes:
		if definition == null:
			continue
		if definition.max_hp < 1 or definition.max_mp < 0 or definition.attack < 0 or definition.magic < 0 or definition.armor < 0 or definition.formation not in ["Front", "Middle", "Back"]:
			result.append("Invalid class stats: " + definition.id)
		var known: Array[String] = []
		for skill in definition.skills:
			if skill == null or not skills.has(skill):
				result.append("Class references an unregistered skill: " + definition.id)
			elif known.has(skill.id):
				result.append("Repeated class skill: " + definition.id + "/" + skill.id)
			else:
				known.append(skill.id)
		for tactic in definition.tactics:
			if not _valid_tactic(tactic, known):
				result.append("Invalid default tactic: " + definition.id)
	if progression == null:
		result.append("Missing progression definition.")
		return result
	if progression.starting_slots < 1 or progression.maximum_slots < progression.starting_slots or progression.slot_costs.size() != progression.maximum_slots - progression.starting_slots or progression.maximum_skill_rank < 1:
		result.append("Invalid progression slot or rank limits.")
	for cost in progression.slot_costs:
		if cost < 0:
			result.append("Negative party slot cost.")
	for definition in progression.starting_party:
		if definition == null or not classes.has(definition):
			result.append("Starting party references an unregistered class.")
	var purchases: Dictionary = {}
	var unlocks: Dictionary = {}
	for upgrade in progression.upgrades:
		if upgrade == null or upgrade.kind not in ["class", "skill", "rank"]:
			result.append("Missing or invalid upgrade definition.")
			continue
		if upgrade.cost < 0 or upgrade.power_per_rank < 0 or upgrade.status_chance_per_rank < 0:
			result.append("Negative upgrade cost or rank bonus.")
		if upgrade.kind in ["class", "skill"] and (upgrade.class_definition == null or not classes.has(upgrade.class_definition)):
			result.append("Upgrade references an unregistered class.")
			continue
		if upgrade.kind in ["skill", "rank"] and (upgrade.skill == null or not skills.has(upgrade.skill)):
			result.append("Upgrade references an unregistered skill.")
			continue
		var key := upgrade.kind + ":" + upgrade.purchase_id()
		if purchases.has(key):
			result.append("Duplicate purchase: " + key)
		purchases[key] = true
		if upgrade.kind == "class" and progression.starting_party.has(upgrade.class_definition):
			result.append("Starting class also sold as an unlock: " + key)
		if upgrade.kind == "skill":
			unlocks[upgrade.skill.id] = true
			if upgrade.class_definition.skills.has(upgrade.skill):
				result.append("Starting skill also sold as an unlock: " + key)
			if upgrade.default_tactic != null and (upgrade.skill.kind == "passive" or not _valid_tactic(upgrade.default_tactic, [upgrade.skill.id])):
				result.append("Invalid unlocked tactic: " + key)
	for definition in classes:
		if definition != null and not progression.starting_party.has(definition) and not purchases.has("class:" + definition.id):
			result.append("Class has no unlock path: " + definition.id)
	for definition in classes:
		if definition == null:
			continue
		for skill in definition.skills:
			if skill != null and unlocks.has(skill.id):
				result.append("A sold skill is already available to a class: " + skill.id)
	return result


func _valid_tactic(rule: CrawlTacticRule, known: Array) -> bool:
	return rule != null and known.has(rule.skill_id) and rule.metric in ["always", "self_hp_percent", "self_hp", "lowest_ally_hp_percent", "lowest_ally_hp", "self_mp_percent", "enemy_group_count"] and rule.comparator in ["below", "above", "at_most", "at_least"] and rule.selector in ["self", "lowest_hp", "highest_hp", "lowest_hp_percent", "backline", "highest_count"] and is_finite(rule.threshold) and rule.threshold >= 0 and rule.threshold <= 9999 and rule.reserve_mp >= 0 and rule.reserve_mp <= 999 and rule.min_group_count >= 0 and rule.min_group_count <= 100
