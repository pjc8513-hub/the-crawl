class_name CrawlCombatContent
extends RefCounted
## Initial balance presets; Resource fields are independent of the engine.


static func rule(rule_id: String, metric: String, threshold: float, skill: String, selector: String) -> CrawlTacticRule:
	var result := CrawlTacticRule.new()
	result.id = rule_id
	result.metric = metric
	result.threshold = threshold
	result.skill_id = skill
	result.selector = selector
	if metric == "self_mp_percent" or metric == "enemy_group_count":
		result.comparator = "above" if metric == "self_mp_percent" else "at_least"
	return result


static func skills() -> Dictionary:
	var result: Dictionary = {}
	for spec in [
		["attack", "Attack", "attack", "melee", "physical", 0, 0],
		["defend", "Defend", "defend", "melee", "physical", 0, 0],
		["potion", "Healing potion", "potion", "ranged", "spirit", 35, 0],
		["heal", "Heal", "heal", "ranged", "spirit", 18, 4],
		["fireball", "Fireball", "group_damage", "ranged", "fire", 10, 6],
		["dart", "Fire dart", "attack", "ranged", "fire", 3, 3],
		["cleave", "Cleave", "cleave", "melee", "physical", 8, 3],
		["poison_strike", "Poison strike", "attack", "melee", "physical", 0, 2],
		["stun_strike", "Stunning strike", "attack", "melee", "physical", 0, 3]
	]:
		var skill := CrawlCombatSkill.new()
		skill.id = spec[0]
		skill.display_name = spec[1]
		skill.kind = spec[2]
		skill.reach = spec[3]
		skill.element = spec[4]
		skill.power = spec[5]
		skill.mp_cost = spec[6]
		if skill.id == "poison_strike":
			skill.status_id = "poison"
			skill.status_turns = 2
			skill.status_potency = 3
		if skill.id == "stun_strike":
			skill.status_id = "stun"
			skill.status_turns = 1
		result[skill.id] = skill
	return result


static func party() -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	for spec in [
		["warrior", "Warrior", 120, 12, 16, 0, 4, 6, "Front"],
		["cleric", "Cleric", 95, 40, 8, 7, 2, 5, "Middle"],
		["mage", "Mage", 75, 42, 5, 6, 1, 8, "Back"]
	]:
		var definition := CrawlClassDefinition.new()
		definition.id = spec[0]
		definition.display_name = spec[1]
		definition.max_hp = spec[2]
		definition.max_mp = spec[3]
		definition.attack = spec[4]
		definition.magic = spec[5]
		definition.armor = spec[6]
		definition.initiative = spec[7]
		definition.formation = spec[8]
		definition.tactics.append(rule("potion", "self_hp_percent", 25, "potion", "self"))
		if definition.id == "cleric":
			definition.skill_ids.append("heal")
			definition.tactics.append(rule("heal", "lowest_ally_hp_percent", 40, "heal", "lowest_hp_percent"))
		if definition.id == "mage":
			definition.skill_ids.append("fireball")
			var aoe := rule("fireball", "self_mp_percent", 35, "fireball", "highest_count")
			aoe.min_group_count = 4
			definition.tactics.append(aoe)
		definition.tactics.append(rule("attack", "always", 0, "attack", "lowest_hp"))
		var actor := CrawlCombatant.new()
		actor.from_class(definition, "party:" + definition.id)
		result.append(actor)
	return result
