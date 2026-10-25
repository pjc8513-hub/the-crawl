class_name CrawlProgressionCatalog
extends RefCounted

static func enemies() -> Dictionary:
	return CrawlContent.enemies()


static func items() -> Dictionary:
	var result: Dictionary = {}
	for item in CrawlRoomFlow.item_pool():
		result[item.id] = item
	return result


static func fresh_profile() -> Dictionary:
	var economy := CrawlContent.economy()
	var starting := economy.starting_class_ids()
	return {"version": 1, "gold": 0, "party_slots": economy.starting_slots, "classes": starting.duplicate(), "skills": [], "ranks": {}, "presets": {}, "settled": {}, "next_run": 1, "loadout": starting.duplicate()}


static func skills(profile: Dictionary) -> Dictionary:
	var result := CrawlContent.skills()
	for upgrade in CrawlContent.economy().upgrades:
		if upgrade.kind != "rank":
			continue
		var rank := int(profile.ranks.get(upgrade.skill.id, 0))
		var skill: CrawlCombatSkill = result[upgrade.skill.id]
		skill.power += rank * upgrade.power_per_rank
		skill.status_chance = mini(100, skill.status_chance + rank * upgrade.status_chance_per_rank)
	return result


static func party(profile: Dictionary, classes: Array) -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	var definitions := CrawlContent.classes()
	var skills_by_id := CrawlContent.skills()
	for index in range(classes.size()):
		var class_id: String = classes[index]
		if not definitions.has(class_id):
			push_error("Unknown class: " + class_id)
			return []
		var actor := CrawlCombatant.new()
		actor.from_class(definitions[class_id], "party:%02d:%s" % [index, class_id])
		actor.display_name += " %d" % (index + 1)
		for skill_id in profile.skills:
			for upgrade in CrawlContent.economy().upgrades:
				if upgrade.kind != "skill" or upgrade.skill.id != skill_id or upgrade.class_definition.id != class_id:
					continue
				actor.known_skills.append(skill_id)
				var skill: CrawlCombatSkill = skills_by_id[skill_id]
				if skill_id == "mind_expansion":
					actor.max_mp += skill.power
					actor.mp = actor.max_mp
				elif skill_id == "meditation":
					actor.meditation_percent = skill.power
				elif skill_id == "focus":
					actor.focus_percent = skill.power
				if upgrade.default_tactic != null:
					actor.tactics.insert(maxi(0, actor.tactics.size() - 1), upgrade.default_tactic.duplicate(true))
		if profile.presets.has(class_id):
			actor.tactics.clear()
			for data in profile.presets[class_id]:
				actor.tactics.append(unpack_rule(data))
		result.append(actor)
	return result


static func pack_rule(rule: CrawlTacticRule) -> Dictionary:
	return {"id": rule.id, "enabled": rule.enabled, "metric": rule.metric, "comparator": rule.comparator, "threshold": rule.threshold, "skill_id": rule.skill_id, "selector": rule.selector, "reserve_mp": rule.reserve_mp, "min_group_count": rule.min_group_count}


static func unpack_rule(data: Dictionary) -> CrawlTacticRule:
	var rule := CrawlTacticRule.new()
	for field in data:
		rule.set(field, data[field])
	return rule


static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high


static func valid_run_id(value: Variant) -> bool:
	if not value is String or not value.begins_with("run-") or not value.trim_prefix("run-").is_valid_int(): return false
	var counter: int = value.trim_prefix("run-").to_int()
	return counter >= 1 and counter < 2000000000 and value == "run-%012d" % counter


static func rules_error(value: Variant) -> String:
	if not value is Array or value.size() > 32:
		return "Invalid tactic list."
	for data in value:
		if not data is Dictionary or data.size() != 9 or not data.get("id") is String or data.id.length() > 100 or not data.get("enabled") is bool or data.get("metric") not in ["always", "self_hp_percent", "self_hp", "lowest_ally_hp_percent", "lowest_ally_hp", "self_mp_percent", "enemy_group_count"] or data.get("comparator") not in ["below", "above", "at_most", "at_least"] or not integer(data.get("reserve_mp"), 0, 999) or not integer(data.get("min_group_count"), 0, 100) or data.get("skill_id") not in CrawlContent.skills() or data.get("selector") not in ["self", "lowest_hp", "highest_hp", "lowest_hp_percent", "backline", "highest_count"]:
			return "Invalid tactic rule."
		if not (data.get("threshold") is int or data.get("threshold") is float) or not is_finite(float(data.threshold)) or data.threshold < 0 or data.threshold > 9999:
			return "Invalid tactic threshold."
	return ""


static func profile_error(data: Dictionary) -> String:
	if not integer(data.get("version"), 1, 100000): return "Invalid profile version."
	if data.get("version") != 1:
		return "Unsupported profile version."
	if not integer(data.get("gold"), 0, 2000000000) or not integer(data.get("party_slots"), CrawlContent.economy().starting_slots, CrawlContent.economy().maximum_slots) or not integer(data.get("next_run"), 1, 2000000000):
		return "Invalid profile currency, slots or run counter."
	for field in ["classes", "skills", "loadout"]:
		var limit: int = {"classes": CrawlContent.CATALOG.classes.size(), "skills": CrawlContent.economy().skill_unlocks.size(), "loadout": CrawlContent.economy().maximum_slots}[field]
		if not data.get(field) is Array or data[field].size() > limit:
			return "Invalid profile unlock list."
	for id in CrawlContent.economy().starting_class_ids():
		if not data.classes.has(id): return "Missing starting class."
	var seen: Dictionary = {}
	for id in data.classes:
		if not id is String or not CrawlContent.classes().has(id) or seen.has(id): return "Invalid class unlock."
		seen[id] = true
	var definition := CrawlContent.economy()
	seen.clear()
	for id in data.skills:
		if not id is String or not definition.skill_unlocks.has(id) or seen.has(id) or not data.classes.has(definition.skill_unlocks[id]["class"]): return "Invalid skill unlock."
		seen[id] = true
	if data.loadout.size() != int(data.party_slots): return "Invalid party composition."
	for id in data.loadout:
		if not id in data.classes: return "Locked class in party composition."
	for field in ["ranks", "presets", "settled"]:
		if not data.get(field) is Dictionary: return "Invalid profile record."
	for id in data.ranks:
		if not definition.rank_costs.has(id) or not integer(data.ranks[id], 1, definition.maximum_skill_rank) or (definition.skill_unlocks.has(id) and not data.skills.has(id)): return "Invalid skill rank."
	for id in data.presets:
		if not data.classes.has(id) or rules_error(data.presets[id]) != "": return "Invalid strategy preset."
	if data.settled.size() > 10000: return "Settlement history exceeds supported size."
	for id in data.settled:
		var entry: Variant = data.settled[id]
		if not valid_run_id(id) or not entry is Dictionary or not integer(entry.get("gold"), 0, 2000000000) or entry.get("outcome") not in ["victory", "defeat", "draw", "stalemate", "invalid", "abandon"]: return "Invalid settlement record."
	return ""
