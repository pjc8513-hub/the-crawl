class_name CrawlCombatEngine
extends RefCounted
## One step = one actor opportunity. No timers, nodes, UI, or direct commands.

const ROWS: Dictionary = {"Front": 0, "Middle": 1, "Back": 2}
const DEBUFFS: Array[String] = ["poison", "burn", "stun", "sleep", "frozen", "fear"]
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
var current_gold: int = 0


func configure(party_members: Array[CrawlCombatant], enemy_groups: Array[EnemyGroup], seed_value: int, skill_definitions: Dictionary = {}, start_effects: bool = true, gold_on_hand: int = 0) -> void:
	party = party_members.duplicate()
	groups = enemy_groups.duplicate()
	actors = party.duplicate()
	for group in groups:
		actors.append_array(group.units)
	skills = CrawlContent.skills() if skill_definitions.is_empty() else skill_definitions
	current_gold = maxi(0, gold_on_hand)
	enemy_skills = CrawlContent.skills()
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
	if start_effects:
		_start_passives()
	_check_end()


func _start_passives() -> void:
	var front_enemies := 0
	for enemy in _living("enemy"):
		if enemy.row == "Front":
			front_enemies += 1
	for warrior in _living("party"):
		warrior.battle_armor = 0
		warrior.bloodlust_bonus = 0
		if warrior.known_skills.has("battle_harden"):
			warrior.battle_armor = front_enemies * int(skills["battle_harden"].power)
			_emit("passive", {"actor": warrior.id, "skill": "battle_harden", "amount": warrior.battle_armor})
		if warrior.known_skills.has("intimidate"):
			for enemy in _living("enemy"):
				if enemy.row == "Front" and not _resists(enemy, "spirit") and rng.randi_range(1, 100) <= int(skills["intimidate"].power):
					enemy.statuses["fear"] = {"turns": 100, "potency": 30}
					_emit("status", {"actor": warrior.id, "target": enemy.id, "status": "fear", "turns": 100})


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
		queue.sort_custom(func(a: CrawlCombatant, b: CrawlCombatant) -> bool: return _initiative(a) > _initiative(b) if _initiative(a) != _initiative(b) else a.id < b.id)
		_emit("round")
	var actor: CrawlCombatant = queue.pop_front()
	if not actor.alive():
		return
	actor.defending = false
	var stunned := false
	var skip_reason := "stunned"
	for status_id in actor.statuses.keys():
		var status: Dictionary = actor.statuses[status_id]
		if status_id in ["poison", "burn"]:
			_damage(actor, maxi(0, int(status.potency)), str(status.get("source", "status:poison")), status_id)
		elif status_id in ["stun", "sleep", "frozen"]:
			stunned = true
		elif status_id == "fear" and rng.randi_range(1, 100) <= int(status.potency):
			stunned = true
			skip_reason = "feared"
		if status_id == "frozen" and rng.randf() < float(maxi(0, 50 - int(status.potency))) / 100.0:
			actor.statuses.erase(status_id)
			_emit("status_expired", {"target": actor.id, "status": status_id})
			continue
		if status_id not in ["sleep", "frozen", "fear"]:
			status.turns -= 1
		if status.turns <= 0:
			actor.statuses.erase(status_id)
			_emit("status_expired", {"target": actor.id, "status": status_id})
	if _check_end() or not actor.alive():
		return
	if stunned:
		_emit("skip", {"actor": actor.id, "reason": skip_reason})
		return
	var action := choose_action(actor)
	perform(actor, action.skill, action.target, action.reserve, action.rule)
	_check_end()


func eligible_targets(actor: CrawlCombatant, skill: CrawlCombatSkill) -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	if skill.kind in ["party_heal", "divine_intervention", "balance_life"]:
		if actor.side != "party":
			return result
		var allies := _living("party")
		if allies.is_empty():
			return result
		if skill.kind == "balance_life":
			var first_hp := allies[0].hp
			for ally in allies:
				if ally.hp != first_hp:
					return [actor]
			return result
		return [actor]
	if skill.kind == "resurrect":
		for ally in party:
			if ally.side == "party" and ally.hp <= 0 and not ally.fled:
				result.append(ally)
		return result
	if skill.kind == "cleanse":
		for ally in _living("party"):
			if _has_debuff(ally):
				result.append(ally)
		return result
	if skill.kind == "heroism":
		for ally in _living("party"):
			if not ally.statuses.has("heroism"):
				result.append(ally)
		return result
	if skill.kind in ["potion", "defend", "group_armor"]:
		if skill.kind in ["defend", "group_armor"] or actor.hp < actor.max_hp:
			result.append(actor)
		return result
	var healing := skill.kind == "heal"
	var target_side := actor.side if healing else "enemy" if actor.side == "party" else "party"
	var living := _living(target_side)
	var nearest := 3
	for target in living:
		nearest = mini(nearest, ROWS[target.row])
	for target in living:
		if skill.kind == "group_flee" and target.enemy_data != null and not target.enemy_data.can_flee:
			continue
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
	return skill != null and skill.is_valid() and skill.kind != "passive" and actor.known_skills.has(skill.id) and reserve >= 0 and actor.mp - _cost(actor, skill) >= reserve and (skill.kind != "potion" or actor.potions > 0)


func _cost(actor: CrawlCombatant, skill: CrawlCombatSkill) -> int:
	if skill.kind in ["potion", "defend"] or actor.focus_percent <= 0:
		return skill.mp_cost
	return ceili(skill.mp_cost * (100 - clampi(actor.focus_percent, 0, 100)) / 100.0)


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
			result.reason = "Needs %d MP plus %d reserved MP." % [_cost(actor, skill), rule.reserve_mp]
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
	var cost := _cost(actor, skill)
	actor.mp -= cost
	if skill.kind == "potion":
		actor.potions -= 1
	_emit("action", {"actor": actor.id, "target": target.id, "skill": skill.id, "rule": rule_id, "mp_cost": cost, "mp": actor.mp, "potions": actor.potions})
	if skill.kind == "defend":
		actor.defending = true
	elif skill.kind == "divine_intervention":
		for ally in _living("party"):
			ally.statuses["divine_intervention"] = {"turns": skill.power, "potency": 1, "source": actor.id}
			_emit("status", {"actor": actor.id, "target": ally.id, "status": "divine_intervention", "turns": skill.power})
	elif skill.kind == "balance_life":
		var allies := _living("party")
		allies.sort_custom(func(a: CrawlCombatant, b: CrawlCombatant) -> bool: return a.id < b.id)
		var total_hp := 0
		for ally in allies:
			total_hp += ally.hp
		var shared_hp := floori(float(total_hp) / allies.size())
		var remainder := total_hp - shared_hp * allies.size()
		for index in range(allies.size()):
			allies[index].hp = shared_hp + (1 if index < remainder else 0)
			_emit("balance", {"actor": actor.id, "target": allies[index].id, "hp": allies[index].hp})
	elif skill.kind == "resurrect":
		target.hp = maxi(1, ceili(target.max_hp * skill.power / 100.0))
		_emit("resurrect", {"actor": actor.id, "target": target.id, "hp": target.hp, "max_hp": target.max_hp})
	elif skill.kind == "cleanse":
		for debuff in DEBUFFS:
			if target.statuses.has(debuff):
				target.statuses.erase(debuff)
				_emit("status_expired", {"target": target.id, "status": debuff})
		target.freeze_thaw_penalty = 0
	elif skill.kind == "heroism":
		target.statuses["heroism"] = {"turns": skill.status_turns, "potency": skill.power, "source": actor.id}
		_emit("status", {"actor": actor.id, "target": target.id, "status": "heroism", "turns": skill.status_turns})
	elif skill.kind == "group_armor":
		for ally in _living(actor.side):
			ally.statuses["smoke_bomb"] = {"turns": skill.status_turns, "potency": skill.power, "source": actor.id}
		_emit("status", {"actor": actor.id, "target": actor.id, "status": "smoke_bomb", "turns": skill.status_turns})
	elif skill.kind in ["heal", "potion"]:
		var amount := skill.power + (actor.magic if skill.kind == "heal" else 0)
		var healed := mini(target.max_hp - target.hp, maxi(0, amount))
		target.hp += healed
		_emit("heal", {"actor": actor.id, "target": target.id, "amount": healed, "hp": target.hp})
	elif skill.kind == "party_heal":
		for ally in _living("party"):
			var healed := mini(ally.max_hp - ally.hp, maxi(0, skill.power))
			ally.hp += healed
			_emit("heal", {"actor": actor.id, "target": ally.id, "amount": healed, "hp": ally.hp})
	else:
		var targets: Array[CrawlCombatant] = [target]
		if skill.kind in ["group_damage", "group_status", "group_flee", "cleave"]:
			targets.clear()
			targets.append(target)
			for unit in actors:
				if unit != target and unit.alive() and unit.side == target.side and unit.group_id == target.group_id:
					targets.append(unit)
		var cleave_remaining := _power(actor, skill, target) if skill.kind == "cleave" else 0
		for unit in targets:
			if skill.kind == "group_flee":
				if unit.enemy_data != null and unit.enemy_data.can_flee and not _resists(unit, skill.element) and rng.randi_range(1, 100) <= mini(100, int(unit.enemy_data.flee_chance * 100.0) + skill.status_chance + actor.status_chance_bonus):
					unit.fled = true
					_emit("flee", {"actor": actor.id, "target": unit.id})
				continue
			var raw := cleave_remaining if skill.kind == "cleave" else _power(actor, skill, unit)
			var damage := _mitigated(unit, skill, raw)
			if actor.side == "enemy" and damage > 0 and _aegis_blocks(unit):
				continue
			var dealt := _damage(unit, damage, actor.id, skill.id) if skill.kind != "group_status" else 0
			if skill.kind == "cleave":
				cleave_remaining = maxi(0, damage - dealt)
			if unit.alive() and skill.status_id != "" and skill.status_turns > 0 and not (skill.status_id == "sleep" and unit.statuses.has("sleep")) and not _resists(unit, skill.element) and rng.randi_range(1, 100) <= mini(100, skill.status_chance + actor.status_chance_bonus):
				unit.statuses[skill.status_id] = {"turns": skill.status_turns, "potency": actor.freeze_thaw_penalty if skill.status_id == "frozen" else skill.status_potency, "source": actor.id}
				_emit("status", {"actor": actor.id, "target": unit.id, "status": skill.status_id, "turns": skill.status_turns})
			if skill.kind == "cleave" and (unit.alive() or cleave_remaining <= 0):
				break
	_check_end()
	return true


func _power(actor: CrawlCombatant, skill: CrawlCombatSkill, target: CrawlCombatant) -> int:
	var heroism_bonus := int(actor.statuses.get("heroism", {}).get("potency", 0))
	var base_stat := actor.attack if skill.element == "physical" else actor.magic
	var value := skill.power + base_stat + heroism_bonus + rng.randi_range(0, skill.variance)
	if skill.element == "physical":
		value += actor.bloodlust_bonus
		if actor.known_skills.has("hoarder"):
			value += floori(float(current_gold) / maxi(1, skills["hoarder"].power))
		if actor.known_skills.has("cheap_shot") and not target.statuses.is_empty():
			value = ceili(value * (100 + int(skills["cheap_shot"].power)) / 100.0)
		var critical_chance := 0
		if actor.known_skills.has("battle_tempo"):
			critical_chance += actor.battle_kills * int(skills["battle_tempo"].power)
		if critical_chance > 0 and rng.randi_range(1, 100) <= mini(100, critical_chance):
			var multiplier := 150 + (int(skills["weak_spot"].power) if actor.known_skills.has("weak_spot") else 0)
			value = ceili(value * multiplier / 100.0)
			_emit("critical", {"actor": actor.id, "target": target.id, "skill": skill.id, "chance": mini(100, critical_chance), "multiplier": multiplier})
		if actor.known_skills.has("berserk"):
			value += mini(int(skills["berserk"].power), (actor.max_hp - actor.hp) / 10)
		if actor.known_skills.has("giant_slayer") and target.hp > actor.hp:
			var percent: int = mini(int(skills["giant_slayer"].power), floori(100.0 * (target.hp - actor.hp) / maxi(1, actor.max_hp)))
			value = ceili(value * (100 + percent) / 100.0)
	return maxi(0, value)


func _aegis_blocks(target: CrawlCombatant) -> bool:
	if target.side != "party":
		return false
	var protectors := _living("party")
	protectors.sort_custom(func(a: CrawlCombatant, b: CrawlCombatant) -> bool: return a.id < b.id)
	for warrior in protectors:
		if warrior.known_skills.has("aegis") and rng.randi_range(1, 100) <= int(skills["aegis"].power):
			_emit("block", {"actor": warrior.id, "target": target.id, "skill": "aegis"})
			return true
	return false


func _mitigated(target: CrawlCombatant, skill: CrawlCombatSkill, raw: int) -> int:
	var smoke_armor := int(target.statuses.get("smoke_bomb", {}).get("potency", 0))
	var heroism_armor := int(target.statuses.get("heroism", {}).get("potency", 0))
	var value := maxi(0, raw - (target.armor + target.battle_armor + smoke_armor + heroism_armor if skill.element == "physical" else 0))
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
	var damage_cap := maxi(0, target.hp - 1) if target.hp > 0 and target.statuses.has("divine_intervention") else target.hp
	var dealt := mini(damage_cap, maxi(0, amount))
	target.hp -= dealt
	_emit("damage", {"actor": source, "target": target.id, "skill": skill_id, "amount": dealt, "hp": target.hp})
	if not target.alive():
		_emit("defeat", {"actor": source, "target": target.id})
		for killer in party:
			if killer.id == source and killer.known_skills.has("battle_tempo"):
				killer.battle_kills += 1
				_emit("passive", {"actor": killer.id, "skill": "battle_tempo", "amount": killer.battle_kills * int(skills["battle_tempo"].power)})
				break
		if target.side == "enemy" and _source_is_party(source):
			for warrior in _living("party"):
				if warrior.known_skills.has("blood_lust"):
					warrior.bloodlust_bonus = mini(int(skills["blood_lust"].power), warrior.bloodlust_bonus + 1)
					_emit("passive", {"actor": warrior.id, "skill": "blood_lust", "amount": warrior.bloodlust_bonus})
	return dealt


func _source_is_party(source: String) -> bool:
	for actor in party:
		if actor.id == source:
			return true
	return false


func _has_debuff(actor: CrawlCombatant) -> bool:
	if actor.freeze_thaw_penalty > 0:
		return true
	for debuff in DEBUFFS:
		if actor.statuses.has(debuff):
			return true
	return false


func _initiative(actor: CrawlCombatant) -> int:
	return actor.initiative + int(actor.statuses.get("heroism", {}).get("potency", 0))
