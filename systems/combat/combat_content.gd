class_name CrawlCombatContent
extends RefCounted
## Combat factories; authored balance lives in data/content.tres.


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
	return CrawlContent.skills()


static func party() -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	for definition in CrawlContent.economy().starting_party:
		var actor := CrawlCombatant.new()
		actor.from_class(definition, "party:" + definition.id)
		result.append(actor)
	return result
