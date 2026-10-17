class_name CrawlCombatEngine
extends RefCounted
## One step = one actor opportunity. No timers, nodes, UI, or direct commands.

const ROWS: Dictionary = {"Front": 0, "Middle": 1, "Back": 2}
var actors: Array[CrawlCombatant] = []
var party: Array[CrawlCombatant] = []
var groups: Array[EnemyGroup] = []
var skills: Dictionary = {}
var enemy_skills: Dictionary = {}
var events: Array[Dictionary] = []
var round_index: int = 0
var round_limit: int = 100
var outcome: String = "ongoing"
var rng := RandomNumberGenerator.new()
var queue: Array[CrawlCombatant] = []


func configure(party_members: Array[CrawlCombatant], enemy_groups: Array[EnemyGroup], seed_value: int, skill_definitions: Dictionary = {}) -> void:
	party = party_members.duplicate()
	groups = enemy_groups.duplicate()
	actors = party.duplicate()
	for group in groups:
		actors.append_array(group.units)
	skills = CrawlCombatContent.skills() if skill_definitions.is_empty() else skill_definitions
	enemy_skills = CrawlCombatContent.skills()
	rng.seed = seed_value
	events.clear()
	queue.clear()
	round_index = 0
	outcome = "ongoing"
	var ids: Dictionary = {}
	for actor in actors:
		if actor.id == "" or ids.has(actor.id) or actor.max_hp <= 0 or actor.max_mp < 0 or actor.hp < 0 or actor.hp > actor.max_hp or actor.mp < 0 or actor.mp > actor.max_mp or not ROWS.has(actor.row) or actor.side not in ["party", "enemy"]:
			_finish("invalid")
			return
		ids[actor.id] = true
	_check_end()


func _emit(kind: String, fields: Dictionary = {}) -> void:
	var event := fields.duplicate(true)
	event["id"] = events.size()
	event["round"] = round_index
	event["type"] = kind
	events.append(event)


func _living(side: String) -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	for actor in actors:
		if actor.alive() and actor.side == side:
			result.append(actor)
	return result


func _check_end() -> bool:
	if outcome != "ongoing":
		return true
	var allies := _living("party")
	var enemies := _living("enemy")
	if allies.is_empty() or enemies.is_empty():
		_finish("draw" if allies.is_empty() and enemies.is_empty() else "defeat" if allies.is_empty() else "victory")
		return true
	return false


func _finish(result: String) -> void:
	if outcome == "ongoing":
		outcome = result
		_emit("complete", {"outcome": result, "gold": reward_gold()})


func reward_gold() -> int:
	if outcome != "victory":
		return 0
	var gold := 0
	for group in groups:
		for unit in group.units:
			if unit.hp <= 0 and not unit.fled and unit.enemy_data != null:
				gold += maxi(0, unit.enemy_data.gold)
	return gold


func step() -> void:
	if _check_end():
		return
	if queue.is_empty():
		if round_index >= maxi(1, round_limit):
			_finish("stalemate")
			return
		round_index += 1
		for actor in actors:
			if actor.alive():
				queue.append(actor)
		queue.sort_custom(func(a: CrawlCombatant, b: CrawlCombatant) -> bool: return a.initiative > b.initiative if a.initiative != b.initiative else a.id < b.id)
		_emit("round")
	var actor: CrawlCombatant = queue.pop_front()
	if not actor.alive():
		return
	actor.defending = false
	var stunned := false
	for status_id in actor.statuses.keys():
		var status: Dictionary = actor.statuses[status_id]
		if status_id in ["poison", "burn"]:
			_damage(actor, maxi(0, int(status.potency)), "status:poison", status_id)
		elif status_id in ["stun", "sleep", "frozen"]:
			stunned = true
		if status_id == "frozen" and rng.randf() < float(maxi(0, 50 - int(status.potency))) / 100.0:
			actor.statuses.erase(status_id)
			_emit("status_expired", {"target": actor.id, "status": status_id})
			continue
		if status_id not in ["sleep", "frozen"]:
			status.turns -= 1
		if status.turns <= 0:
			actor.statuses.erase(status_id)
			_emit("status_expired", {"target": actor.id, "status": status_id})
	if _check_end() or not actor.alive():
		return
	if stunned:
		_emit("skip", {"actor": actor.id, "reason": "stunned"})
		return
	var action := choose_action(actor)
	perform(actor, action.skill, action.target, action.reserve, action.rule)
	_check_end()


func eligible_targets(actor: CrawlCombatant, skill: CrawlCombatSkill) -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	if skill.kind in ["potion", "defend"]:
		if skill.kind == "defend" or actor.hp < actor.max_hp:
			result.append(actor)
		return result
	var healing := skill.kind == "heal"
	var target_side := actor.side if healing else "enemy" if actor.side == "party" else "party"
	var living := _living(target_side)
	var nearest := 3
	for target in living:
		nearest = mini(nearest, ROWS[target.row])
	for target in living:
		if healing:
			if target.hp < target.max_hp:
				result.append(target)
		elif (skill.reach == "ranged" or ROWS[target.row] == nearest) and not (skill.id == "sleep" and target.statuses.has("sleep")):
			result.append(target)
	return result


func _group_size(target: CrawlCombatant) -> int:
	var count := 0
	for unit in actors:
		if unit.alive() and unit.side == target.side and unit.group_id == target.group_id:
			count += 1
	return count


func _select(candidates: Array[CrawlCombatant], selector: String, actor: CrawlCombatant) -> CrawlCombatant:
	if candidates.is_empty():
		return null
	if selector == "self":
		return actor if candidates.has(actor) else null
	if selector not in ["lowest_hp", "highest_hp", "lowest_hp_percent", "backline", "highest_count"]:
		return null
	candidates.sort_custom(func(a: CrawlCombatant, b: CrawlCombatant) -> bool:
		var av: float = a.hp
		var bv: float = b.hp
		match selector:
			"highest_hp":
				av = -a.hp
				bv = -b.hp
			"lowest_hp_percent":
				av = a.hp_percent()
				bv = b.hp_percent()
			"backline":
				av = -ROWS[a.row]
				bv = -ROWS[b.row]
			"highest_count":
				av = -_group_size(a)
				bv = -_group_size(b)
		return av < bv if av != bv else a.id < b.id
	)
	return candidates[0]


func _condition(actor: CrawlCombatant, rule: CrawlTacticRule) -> bool:
	if not rule.enabled or rule.reserve_mp < 0 or rule.min_group_count < 0 or not is_finite(rule.threshold):
		return false
	if rule.metric == "always":
		return true
	var value := 0.0
	match rule.metric:
		"self_hp_percent": value = actor.hp_percent()
		"self_hp": value = actor.hp
		"lowest_ally_hp":
			value = INF
			for ally in _living(actor.side):
				value = minf(value, ally.hp)
		"self_mp_percent":
			if actor.max_mp <= 0:
				return false
			value = 100.0 * actor.mp / actor.max_mp
		"lowest_ally_hp_percent":
			value = 100.0
			for ally in _living(actor.side):
				value = minf(value, ally.hp_percent())
		"enemy_group_count":
			for enemy in _living("enemy" if actor.side == "party" else "party"):
				value = maxf(value, _group_size(enemy))
		_: return false
	match rule.comparator:
		"below": return value < rule.threshold
		"above": return value > rule.threshold
		"at_most": return value <= rule.threshold
		"at_least": return value >= rule.threshold
	return false


func _payable(actor: CrawlCombatant, skill: CrawlCombatSkill, reserve: int) -> bool:
	return skill != null and skill.is_valid() and actor.known_skills.has(skill.id) and reserve >= 0 and actor.mp - skill.mp_cost >= reserve and (skill.kind != "potion" or actor.potions > 0)


func choose_action(actor: CrawlCombatant) -> Dictionary:
	for rule in actor.tactics:
		var inspection := inspect_rule(actor, rule)
		if inspection.reason != "":
			continue
		return {"skill": inspection.skill, "target": inspection.target, "reserve": rule.reserve_mp, "rule": rule.id}
	for fallback in ["attack", "defend"]:
		var skill: CrawlCombatSkill = (enemy_skills if actor.side == "enemy" else skills).get(fallback)
		if _payable(actor, skill, 0):
			var target := _select(eligible_targets(actor, skill), "lowest_hp", actor)
			if target != null:
				return {"skill": skill, "target": target, "reserve": 0, "rule": "fallback"}
	return {"skill": null, "target": null, "reserve": 0, "rule": "no_action"}


func inspect_rule(actor: CrawlCombatant, rule: CrawlTacticRule) -> Dictionary:
	var result := {"reason": "", "skill": null, "target": null}
	if rule == null or not rule.enabled:
		result.reason = "Disabled."
	elif not actor.alive():
		result.reason = "This member is downed."
	elif rule.metric == "self_mp_percent" and actor.max_mp == 0:
		result.reason = "This member has no MP pool."
	elif not _condition(actor, rule):
		result.reason = "Condition is not currently met."
	else:
		var skill: CrawlCombatSkill = (enemy_skills if actor.side == "enemy" else skills).get(rule.skill_id)
		if skill == null or not skill.is_valid() or not actor.known_skills.has(rule.skill_id):
			result.reason = "This skill is not available to this member."
		elif skill.kind == "potion" and actor.potions <= 0:
			result.reason = "No healing potions remain."
		elif not _payable(actor, skill, rule.reserve_mp):
			result.reason = "Needs %d MP plus %d reserved MP." % [skill.mp_cost, rule.reserve_mp]
		else:
			var filtered: Array[CrawlCombatant] = []
			for target in eligible_targets(actor, skill):
				if _group_size(target) >= rule.min_group_count:
					filtered.append(target)
			result.target = _select(filtered, rule.selector, actor)
			result.skill = skill
			if result.target == null:
				result.reason = "No target matches reach, selector, health and group size."
	return result


func perform(actor: CrawlCombatant, skill: CrawlCombatSkill, target: CrawlCombatant, reserve: int = 0, rule_id: String = "") -> bool:
	# This model entry point validates again immediately before committing costs.
	if outcome != "ongoing" or not actors.has(actor) or not actor.alive() or actor.statuses.has("stun") or not _payable(actor, skill, reserve) or target == null or not eligible_targets(actor, skill).has(target):
		return false
	actor.mp -= skill.mp_cost
	if skill.kind == "potion":
		actor.potions -= 1
	_emit("action", {"actor": actor.id, "target": target.id, "skill": skill.id, "rule": rule_id, "mp_cost": skill.mp_cost, "mp": actor.mp, "potions": actor.potions})
	if skill.kind == "defend":
		actor.defending = true
	elif skill.kind in ["heal", "potion"]:
		var amount := skill.power + (actor.magic if skill.kind == "heal" else 0)
		var healed := mini(target.max_hp - target.hp, maxi(0, amount))
		target.hp += healed
		_emit("heal", {"actor": actor.id, "target": target.id, "amount": healed, "hp": target.hp})
	else:
		var targets: Array[CrawlCombatant] = [target]
		if skill.kind in ["group_damage", "group_status", "group_flee", "cleave"]:
			targets.clear()
			targets.append(target)
			for unit in actors:
				if unit != target and unit.alive() and unit.side == target.side and unit.group_id == target.group_id:
					targets.append(unit)
		var cleave_remaining := _power(actor, skill) if skill.kind == "cleave" else 0
		for unit in targets:
			if skill.kind == "group_flee":
				if unit.enemy_data != null and unit.enemy_data.can_flee and not _resists(unit, skill.element) and rng.randi_range(1, 100) <= mini(100, int(unit.enemy_data.flee_chance * 100.0) + skill.status_chance + actor.status_chance_bonus):
					unit.fled = true
					_emit("flee", {"actor": actor.id, "target": unit.id})
				continue
			var raw := cleave_remaining if skill.kind == "cleave" else _power(actor, skill)
			var damage := _mitigated(unit, skill, raw)
			var dealt := _damage(unit, damage, actor.id, skill.id) if skill.kind != "group_status" else 0
			if skill.kind == "cleave":
				cleave_remaining = maxi(0, damage - dealt)
			if unit.alive() and skill.status_id != "" and skill.status_turns > 0 and not (skill.status_id == "sleep" and unit.statuses.has("sleep")) and not _resists(unit, skill.element) and rng.randi_range(1, 100) <= mini(100, skill.status_chance + actor.status_chance_bonus):
				unit.statuses[skill.status_id] = {"turns": skill.status_turns, "potency": actor.freeze_thaw_penalty if skill.status_id == "frozen" else skill.status_potency}
				_emit("status", {"actor": actor.id, "target": unit.id, "status": skill.status_id, "turns": skill.status_turns})
			if skill.kind == "cleave" and (unit.alive() or cleave_remaining <= 0):
				break
	_check_end()
	return true


func _power(actor: CrawlCombatant, skill: CrawlCombatSkill) -> int:
	return maxi(0, skill.power + (actor.attack if skill.element == "physical" else actor.magic) + rng.randi_range(0, skill.variance))


func _mitigated(target: CrawlCombatant, skill: CrawlCombatSkill, raw: int) -> int:
	var value := maxi(0, raw - (target.armor if skill.element == "physical" else 0))
	if target.defending:
		value = floori(value / 2.0)
	if _resists(target, skill.element):
		value = floori(value / 2.0)
	return value


func _resists(target: CrawlCombatant, element: String) -> bool:
	return target.enemy_data != null and bool(target.enemy_data.get("resist_" + element))


func _damage(target: CrawlCombatant, amount: int, source: String, skill_id: String) -> int:
	if target.statuses.has("sleep") and amount > 0:
		amount = floori(amount * 1.5)
		target.statuses.erase("sleep")
		_emit("status_expired", {"target": target.id, "status": "sleep"})
	if target.statuses.has("burn") and amount > 0 and skill_id != "burn":
		amount = floori(amount * 1.2)
	var dealt := mini(target.hp, maxi(0, amount))
	target.hp -= dealt
	_emit("damage", {"actor": source, "target": target.id, "skill": skill_id, "amount": dealt, "hp": target.hp})
	if not target.alive():
		_emit("defeat", {"actor": source, "target": target.id})
	return dealt
