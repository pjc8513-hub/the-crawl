class_name CrawlRunCodec
extends RefCounted
## JSON contains only IDs, numbers, strings, arrays and dictionaries. Never load paths from a save.

const CONTENT: int = 4
const DEFINITION_FIELDS: Array[String] = ["floor_depth", "theme_name", "min_rooms", "max_rooms", "spine_rooms", "loop_chance", "generation_attempts", "encounter_budget", "max_encounter_groups"]
const ACTOR_NUMBERS: Array[String] = ["max_hp", "hp", "max_mp", "mp", "attack", "magic", "armor", "initiative", "potions"]
const ACTOR_STRINGS: Array[String] = ["id", "class_id", "display_name", "side", "group_id", "row"]


static func _at(coords: Vector2i) -> Array:
	return [coords.x, coords.y]


static func _coords(value: Variant) -> bool:
	return value is Array and value.size() == 2 and CrawlProgressionCatalog.integer(value[0], -64, 64) and CrawlProgressionCatalog.integer(value[1], -64, 64)


static func _point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func pack_actor(actor: CrawlCombatant) -> Dictionary:
	var result: Dictionary = {}
	for field in ACTOR_NUMBERS + ACTOR_STRINGS:
		result[field] = actor.get(field)
	result["defending"] = actor.defending
	result["fled"] = actor.fled
	result["status_chance_bonus"] = actor.status_chance_bonus
	result["freeze_thaw_penalty"] = actor.freeze_thaw_penalty
	result["meditation_percent"] = actor.meditation_percent
	result["focus_percent"] = actor.focus_percent
	result["battle_armor"] = actor.battle_armor
	result["bloodlust_bonus"] = actor.bloodlust_bonus
	result["statuses"] = actor.statuses.duplicate(true)
	result["known_skills"] = actor.known_skills.duplicate()
	result["tactics"] = []
	for rule in actor.tactics:
		result.tactics.append(CrawlProgressionCatalog.pack_rule(rule))
	return result


static func _actor_error(data: Variant) -> String:
	if not data is Dictionary: return "Invalid actor record."
	for field in ACTOR_NUMBERS:
		if not CrawlProgressionCatalog.integer(data.get(field), -1000 if field == "initiative" else 0, 100000): return "Invalid actor stat: " + field
	for field in ACTOR_STRINGS:
		if not data.get(field) is String or data[field].length() > 150: return "Invalid actor identity."
	if data.id == "" or data.group_id == "" or data.side not in ["party", "enemy"] or data.row not in ["Front", "Middle", "Back"] or data.max_hp < 1 or data.hp > data.max_hp or data.mp > data.max_mp or not data.get("defending") is bool: return "Invalid actor resources or formation."
	if not data.get("fled", false) is bool or not CrawlProgressionCatalog.integer(data.get("status_chance_bonus", 0), 0, 1000) or not CrawlProgressionCatalog.integer(data.get("freeze_thaw_penalty", 0), 0, 1000): return "Invalid actor effect bonuses."
	if not CrawlProgressionCatalog.integer(data.get("meditation_percent", 0), 0, 100) or not CrawlProgressionCatalog.integer(data.get("focus_percent", 0), 0, 100): return "Invalid passive bonuses."
	if not CrawlProgressionCatalog.integer(data.get("battle_armor", 0), 0, 1000) or not CrawlProgressionCatalog.integer(data.get("bloodlust_bonus", 0), 0, 1000): return "Invalid combat bonuses."
	if not data.get("known_skills") is Array or data.known_skills.size() > CrawlContent.CATALOG.skills.size(): return "Invalid learned skills."
	for id in data.known_skills:
		if not id is String or not CrawlContent.skills().has(id): return "Unknown learned skill."
	if CrawlProgressionCatalog.rules_error(data.get("tactics")) != "": return "Invalid saved tactics."
	if not data.get("statuses") is Dictionary or data.statuses.size() > 32: return "Invalid statuses."
	for id in data.statuses:
		var status: Variant = data.statuses[id]
		if not id is String or id.length() > 64 or not status is Dictionary or not CrawlProgressionCatalog.integer(status.get("turns"), 1, 100) or not CrawlProgressionCatalog.integer(status.get("potency"), 0, 100000): return "Invalid status duration or potency."
		if status.has("source") and (not status.source is String or status.source.length() > 150): return "Invalid status source."
	return ""


static func unpack_actor(data: Dictionary) -> CrawlCombatant:
	var actor := CrawlCombatant.new()
	for field in ACTOR_NUMBERS:
		actor.set(field, int(data[field]))
	for field in ACTOR_STRINGS:
		actor.set(field, data[field])
	actor.defending = data.defending
	actor.fled = data.get("fled", false)
	actor.status_chance_bonus = int(data.get("status_chance_bonus", 0))
	actor.freeze_thaw_penalty = int(data.get("freeze_thaw_penalty", 0))
	actor.meditation_percent = int(data.get("meditation_percent", 0))
	actor.focus_percent = int(data.get("focus_percent", 0))
	actor.battle_armor = int(data.get("battle_armor", 0))
	actor.bloodlust_bonus = int(data.get("bloodlust_bonus", 0))
	actor.statuses = data.statuses.duplicate(true)
	for id in data.known_skills: actor.known_skills.append(id)
	for rule in data.tactics: actor.tactics.append(CrawlProgressionCatalog.unpack_rule(rule))
	return actor


static func pack(flow: CrawlRoomFlow, definition: FloorDefinition, skill_ranks: Dictionary) -> Dictionary:
	var session := flow.session
	if session.combat != null and session.combat.outcome == "ongoing": return {}
	var floor_state := session.floor_state
	var def_data: Dictionary = {}
	for field in DEFINITION_FIELDS: def_data[field] = definition.get(field)
	def_data["pool"] = []
	for option in definition.standard_enemy_pool:
		def_data.pool.append({"enemy": option.enemy.id, "min": option.min_count, "max": option.max_count, "cost": option.unit_budget_cost, "row": option.formation})
	var result := {"version": 1, "content": CONTENT, "generator": 1, "status": "active", "run_id": flow.run_id, "seed": str(floor_state.run_seed), "definition": def_data, "phase": flow.phase, "end_outcome": flow.end_outcome, "gold": session.run_gold, "supplies": flow.supplies, "final_loadout": flow.final_loadout.duplicate(), "current": _at(floor_state.current), "discovered": [], "searched": [], "keys": floor_state.keys.keys(), "switches": floor_state.switches.keys(), "rooms": [], "party": [], "inventory": [], "offers": {}, "claimed": flow.claimed_offers.keys(), "pending": flow.pending_offer.get("id", ""), "result_pending": session.result_pending, "combat": {}, "skill_ranks": skill_ranks.duplicate(true)}
	for coords in floor_state.discovered: result.discovered.append(_at(coords))
	result["combat_claims"] = session.claimed_rewards.keys()
	for coords in floor_state.interaction_consumed: result.searched.append(_at(coords))
	for coords in floor_state.rooms:
		var room: DungeonRoomData = floor_state.rooms[coords]
		if room.room_event != null or not room.npcs.is_empty() or not room.switches.is_empty(): return {} # Future content requires a schema extension.
		var record := {"at": _at(coords), "visited": room.is_explored, "cleared": room.is_cleared, "doors": [], "chests": []}
		for door in room.doors: record.doors.append({"id": door.id, "state": door.state})
		for chest in room.chests: record.chests.append({"id": chest.id, "triggered": chest.is_triggered})
		result.rooms.append(record)
	for actor in session.party: result.party.append(pack_actor(actor))
	for entry in flow.inventory: result.inventory.append({"id": entry.id, "item": entry.item.id, "equipped_to": entry.equipped_to})
	for id in flow.offers:
		var items: Array[String] = []
		for item in flow.offers[id].items: items.append(item.id)
		result.offers[id] = {"id": id, "source": flow.offers[id].source, "items": items}
	if session.result_pending:
		var combat := session.combat
		result.combat = {"outcome": combat.outcome, "round": combat.round_index, "events": combat.events.slice(maxi(0, combat.events.size() - 120)), "groups": []}
		for group in combat.groups:
			var record := {"id": group.id, "enemy": group.enemy_data.id, "row": group.position_row, "units": []}
			for unit in group.units: record.units.append(pack_actor(unit))
			result.combat.groups.append(record)
	return result


static func error(data: Dictionary) -> String:
	return unpack(data).get("reason", "")


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func unpack(data: Dictionary) -> Dictionary:
	if not CrawlProgressionCatalog.integer(data.get("version"), 1, 100000): return _fail("Invalid run save version.")
	if data.get("version") != 1: return _fail("Unsupported run save version.")
	if data.get("status") == "settled":
		if not CrawlProgressionCatalog.valid_run_id(data.get("run_id")) or not CrawlProgressionCatalog.integer(data.get("gold"), 0, 2000000000) or data.get("outcome") not in ["victory", "defeat", "draw", "stalemate", "invalid", "abandon"]: return _fail("Invalid settlement receipt.")
		return {"ok": true, "settled": true}
	if not CrawlProgressionCatalog.integer(data.get("content"), 1, 100000) or not CrawlProgressionCatalog.integer(data.get("generator"), 1, 100000): return _fail("Invalid run content/generator version.")
	if data.content != CONTENT or data.generator != 1: return _fail("Unsupported run content/generator version. Original files were retained.")
	if data.get("status") != "active" or not CrawlProgressionCatalog.valid_run_id(data.get("run_id")) or not data.get("seed") is String or not data.seed.is_valid_int() or str(data.seed.to_int()) != data.seed: return _fail("Invalid run identity or seed.")
	if data.get("phase") not in ["room", "camp", "reward", "ended"] or data.get("end_outcome") not in ["", "victory", "defeat", "draw", "stalemate", "invalid", "abandon"] or not CrawlProgressionCatalog.integer(data.get("gold"), 0, 2000000000) or not CrawlProgressionCatalog.integer(data.get("supplies"), 0, 6): return _fail("Invalid run phase or resources.")
	var def_data: Variant = data.get("definition")
	if not def_data is Dictionary or not def_data.get("pool") is Array or def_data.pool.size() > 32 or not def_data.get("theme_name") is String: return _fail("Invalid floor definition.")
	for field in DEFINITION_FIELDS:
		if field == "theme_name": continue
		if field == "loop_chance":
			if not (def_data.get(field) is int or def_data.get(field) is float) or not is_finite(float(def_data[field])) or def_data[field] < 0 or def_data[field] > 1: return _fail("Invalid loop chance.")
		elif not CrawlProgressionCatalog.integer(def_data.get(field), 1, 10000): return _fail("Invalid generation value.")
	if def_data.min_rooms < 6 or def_data.max_rooms > 64 or def_data.min_rooms > def_data.max_rooms or def_data.spine_rooms > 32 or def_data.generation_attempts > 32 or def_data.max_encounter_groups > 4: return _fail("Invalid generation bounds.")
	var definition := FloorDefinition.new()
	for field in DEFINITION_FIELDS: definition.set(field, def_data[field])
	var enemies := CrawlProgressionCatalog.enemies()
	for entry in def_data.pool:
		if not entry is Dictionary or not enemies.has(entry.get("enemy")) or not CrawlProgressionCatalog.integer(entry.get("min"), 1, 100) or not CrawlProgressionCatalog.integer(entry.get("max"), 1, 100) or entry.min > entry.max or not CrawlProgressionCatalog.integer(entry.get("cost"), 1, 100) or entry.get("row") not in ["Front", "Middle", "Back"]: return _fail("Invalid encounter pool.")
		var option := EnemyGroupResource.new()
		option.enemy = enemies[entry.enemy]
		option.min_count = int(entry.min)
		option.max_count = int(entry.max)
		option.unit_budget_cost = int(entry.cost)
		option.formation = entry.row
		definition.standard_enemy_pool.append(option)
	var floor_state := CrawlFloorGenerator.new().generate(definition, data.seed.to_int())
	if not data.get("rooms") is Array or data.rooms.size() != floor_state.rooms.size(): return _fail("Saved room count disagrees with generator.")
	var seen: Dictionary = {}
	for record in data.rooms:
		if not record is Dictionary or not _coords(record.get("at")) or not record.get("visited") is bool or not record.get("cleared") is bool or not record.get("doors") is Array or not record.get("chests") is Array: return _fail("Invalid room state.")
		var coords := _point(record.at)
		if not floor_state.rooms.has(coords) or seen.has(coords): return _fail("Unknown or duplicate room.")
		seen[coords] = true
		var room: DungeonRoomData = floor_state.rooms[coords]
		room.is_explored = record.visited
		room.is_cleared = record.cleared
		if record.doors.size() != room.doors.size() or record.chests.size() != room.chests.size(): return _fail("Room contents disagree with generator.")
		var door_ids: Dictionary = {}
		for entry in record.doors:
			if not entry is Dictionary or not entry.get("id") is String or door_ids.has(entry.id) or not CrawlProgressionCatalog.integer(entry.get("state"), 0, 2): return _fail("Invalid door state.")
			var found := false
			for door in room.doors:
				if door.id == entry.id:
					door.state = int(entry.state)
					found = true
			if not found: return _fail("Unknown door ID.")
			door_ids[entry.id] = true
		for index in range(record.chests.size()):
			var entry: Variant = record.chests[index]
			if not entry is Dictionary or entry.get("id") != room.chests[index].id or not entry.get("triggered") is bool: return _fail("Invalid chest state.")
			room.chests[index].is_triggered = entry.triggered
	if not _coords(data.get("current")) or not floor_state.rooms.has(_point(data.current)): return _fail("Invalid current room.")
	floor_state.current = _point(data.current)
	floor_state.discovered.clear()
	for field in ["discovered", "searched"]:
		if not data.get(field) is Array or data[field].size() > floor_state.rooms.size(): return _fail("Invalid room history.")
		for coords in data[field]:
			if not _coords(coords) or not floor_state.rooms.has(_point(coords)): return _fail("Unknown room in history.")
			if field == "discovered": floor_state.discovered[_point(coords)] = true
			else: floor_state.interaction_consumed[_point(coords)] = true
	if not floor_state.discovered.has(floor_state.current) or not floor_state.rooms[floor_state.current].is_explored: return _fail("Current room was not discovered/visited.")
	for coords in floor_state.rooms:
		if floor_state.rooms[coords].is_explored and not floor_state.discovered.has(coords): return _fail("Visited room missing from discovery.")
	if not data.get("keys") is Array or data.keys.size() > 4 or not data.get("switches") is Array or not data.switches.is_empty(): return _fail("Invalid keys or unsupported switches.")
	for key in data.keys:
		if not CrawlProgressionCatalog.integer(key, 1, 4): return _fail("Invalid key type.")
		floor_state.keys[int(key)] = true
	if not CrawlFloorGenerator.new().validate(floor_state, definition).is_empty(): return _fail("Saved door graph is inconsistent.")
	if not data.get("party") is Array or data.party.is_empty() or data.party.size() > 6: return _fail("Invalid party size.")
	var session := CrawlEncounterSession.new()
	session.floor_state = floor_state
	session.run_gold = int(data.gold)
	if not data.get("combat_claims") is Array or data.combat_claims.size() > floor_state.rooms.size(): return _fail("Invalid encounter reward records.")
	var reward_ids: Dictionary = {}
	for coords in floor_state.rooms: reward_ids["combat:%d:%s" % [floor_state.floor_depth, coords]] = true
	for id in data.combat_claims:
		if not id is String or not reward_ids.has(id) or session.claimed_rewards.has(id): return _fail("Unknown or repeated encounter reward ID.")
		session.claimed_rewards[id] = true
	seen.clear()
	for record in data.party:
		var actor_error := _actor_error(record)
		if actor_error != "": return _fail(actor_error)
		if not CrawlContent.classes().has(record.class_id) or record.side != "party" or record.group_id != record.id or seen.has(record.id): return _fail("Invalid party identity.")
		seen[record.id] = true
		session.party.append(unpack_actor(record))
	var flow := CrawlRoomFlow.new()
	flow.session = session
	flow.run_id = data.run_id
	flow.phase = data.phase
	flow.end_outcome = data.end_outcome
	flow.supplies = int(data.supplies)
	if not data.get("final_loadout") is Array or data.final_loadout.size() > 6: return _fail("Invalid final loadout.")
	for name_value in data.final_loadout:
		if not name_value is String or name_value.length() > 150: return _fail("Invalid loadout name.")
		flow.final_loadout.append(name_value)
	var items := CrawlProgressionCatalog.items()
	if not data.get("inventory") is Array or data.inventory.size() > CrawlRoomFlow.GEAR_CAPACITY: return _fail("Invalid inventory size.")
	var owned_ids: Dictionary = {}
	var slots: Dictionary = {}
	for entry in data.inventory:
		if not entry is Dictionary or not entry.get("id") is String or owned_ids.has(entry.id) or not items.has(entry.get("item")) or not entry.get("equipped_to") is String: return _fail("Invalid inventory entry.")
		owned_ids[entry.id] = true
		var actor := flow.actor_by_id(entry.equipped_to)
		var item: CrawlItemDefinition = items[entry.item]
		if entry.equipped_to != "":
			if actor == null or slots.has(entry.equipped_to + item.slot): return _fail("Invalid equipment owner or duplicate slot.")
			actor.equipment[item.slot] = item # Saved stats already include bonuses: never apply twice.
			slots[entry.equipped_to + item.slot] = true
		flow.inventory.append({"id": entry.id, "item": item, "equipped_to": entry.equipped_to})
	for actor in session.party:
		var bonuses: Dictionary = {}
		for item in actor.equipment.values():
			for stat in item.bonuses(): bonuses[stat] = bonuses.get(stat, 0) + item.bonuses()[stat]
		for stat in bonuses:
			if actor.get(stat) - bonuses[stat] < (1 if stat == "max_hp" else 0): return _fail("Equipment bonuses exceed saved base stats.")
	if not data.get("offers") is Dictionary or data.offers.size() > 64 or not data.get("claimed") is Array or not data.get("pending") is String: return _fail("Invalid reward records.")
	for id in data.offers:
		var offer: Variant = data.offers[id]
		if not id is String or not offer is Dictionary or offer.get("id") != id or offer.get("source") not in ["chest", "boss"] or not offer.get("items") is Array or offer.items.size() != 3: return _fail("Invalid gear offer.")
		var choices: Array[CrawlItemDefinition] = []
		var choice_ids: Dictionary = {}
		for item_id in offer.items:
			if not items.has(item_id) or choice_ids.has(item_id): return _fail("Unknown or repeated reward choice.")
			choices.append(items[item_id])
			choice_ids[item_id] = true
		flow.offers[id] = {"id": id, "source": offer.source, "items": choices}
	for id in data.claimed:
		if not flow.offers.has(id): return _fail("Unknown claimed offer.")
		flow.claimed_offers[id] = true
	if data.phase == "reward":
		if not flow.offers.has(data.pending) or flow.claimed_offers.has(data.pending): return _fail("Missing pending offer.")
		flow.pending_offer = flow.offers[data.pending]
	elif data.pending != "": return _fail("Pending offer outside reward phase.")
	if not data.get("skill_ranks") is Dictionary: return _fail("Invalid run skill ranks.")
	var powers := CrawlProgressionCatalog.fresh_profile()
	powers.ranks = data.skill_ranks
	var upgrade_def := CrawlContent.economy()
	for id in data.skill_ranks:
		if not upgrade_def.rank_costs.has(id) or not CrawlProgressionCatalog.integer(data.skill_ranks[id], 1, upgrade_def.maximum_skill_rank): return _fail("Invalid run skill upgrade.")
	session.skill_definitions = CrawlProgressionCatalog.skills(powers)
	if not data.get("result_pending") is bool: return _fail("Invalid result state.")
	if data.result_pending:
		if session.claimed_rewards.has(session.encounter_id()): return _fail("Encounter reward is both claimed and pending.")
		var combat_error := _restore_combat(data.get("combat"), session, enemies)
		if combat_error != "": return _fail(combat_error)
		session.result_pending = true
	elif not data.get("combat") is Dictionary or not data.combat.is_empty(): return _fail("Unexpected combat snapshot.")
	if data.result_pending and data.phase != "room": return _fail("Results overlap another required screen.")
	if data.phase in ["camp", "reward"] or (data.phase == "room" and not data.result_pending):
		if not floor_state.rooms[floor_state.current].is_cleared: return _fail("Room action in an uncleared room.")
	if data.phase == "ended" and (data.end_outcome == "" or not flow.inventory.is_empty() or flow.supplies != 0): return _fail("Ended run retains temporary inventory.")
	floor_state.travel_block_reason = "Review combat results before travelling." if data.result_pending else {"room": "", "camp": "Return from camp before travelling.", "reward": "Choose one gear reward before travelling.", "ended": "The run has ended."}[data.phase]
	return {"ok": true, "flow": flow, "definition": definition, "skill_ranks": data.skill_ranks}


static func _restore_combat(data: Variant, session: CrawlEncounterSession, enemies: Dictionary) -> String:
	if not data is Dictionary or data.get("outcome") not in ["victory", "defeat", "draw", "stalemate", "invalid"] or not CrawlProgressionCatalog.integer(data.get("round"), 0, 100) or not data.get("groups") is Array or data.groups.is_empty() or data.groups.size() > 4 or not data.get("events") is Array or data.events.size() > 120: return "Invalid terminal combat snapshot."
	var groups: Array[EnemyGroup] = []
	var ids: Dictionary = {}
	var group_ids: Dictionary = {}
	for actor in session.party: ids[actor.id] = true
	for record in data.groups:
		if not record is Dictionary or not record.get("id") is String or group_ids.has(record.id) or not enemies.has(record.get("enemy")) or record.get("row") not in ["Front", "Middle", "Back"] or not record.get("units") is Array or record.units.is_empty() or record.units.size() > 100: return "Invalid saved enemy group."
		group_ids[record.id] = true
		var group := EnemyGroup.new()
		group.id = record.id
		group.enemy_data = enemies[record.enemy]
		group.position_row = record.row
		for unit_data in record.units:
			if _actor_error(unit_data) != "" or unit_data.side != "enemy" or unit_data.group_id != group.id or unit_data.row != group.position_row or ids.has(unit_data.id): return "Invalid enemy unit state."
			ids[unit_data.id] = true
			var unit := unpack_actor(unit_data)
			unit.enemy_data = group.enemy_data
			group.units.append(unit)
		groups.append(group)
	var engine := CrawlCombatEngine.new()
	engine.configure(session.party, groups, 0, session.skill_definitions, false)
	if data.outcome not in ["stalemate", "invalid"] and engine.outcome != data.outcome: return "Combat outcome disagrees with living units."
	if data.outcome == "stalemate" and engine.outcome != "ongoing": return "Invalid stalemate state."
	engine.outcome = data.outcome
	engine.round_index = int(data.round)
	engine.events.clear()
	for event in data.events:
		if not event is Dictionary or event.get("type") not in ["round", "action", "damage", "heal", "balance", "resurrect", "defeat", "flee", "status", "skip", "status_expired", "passive", "block", "critical", "complete"] or not CrawlProgressionCatalog.integer(event.get("id"), 0, 1000000) or not CrawlProgressionCatalog.integer(event.get("round"), 0, 100): return "Invalid saved combat event."
		var type: String = event.type
		if type in ["action", "damage", "heal", "balance", "resurrect", "defeat", "flee", "status", "skip", "passive", "block", "critical"] and (not event.get("actor") is String or (not ids.has(event.actor) and event.actor != "status:poison")): return "Unknown event source."
		if type in ["action", "damage", "heal", "balance", "resurrect", "defeat", "flee", "status", "status_expired", "block", "critical"] and not ids.has(event.get("target")): return "Unknown event target."
		if type == "action" and not engine.skills.has(event.get("skill")): return "Unknown event skill."
		if type in ["damage", "heal"] and (not CrawlProgressionCatalog.integer(event.get("amount"), 0, 100000) or not CrawlProgressionCatalog.integer(event.get("hp"), 0, 100000)): return "Invalid event amount."
		if type in ["balance", "resurrect"] and not CrawlProgressionCatalog.integer(event.get("hp"), 1, 100000): return "Invalid health event."
		if type == "resurrect" and not CrawlProgressionCatalog.integer(event.get("max_hp"), 1, 100000): return "Invalid resurrection event."
		if type in ["status", "status_expired"] and not event.get("status") is String: return "Invalid status event."
		if type == "status" and not CrawlProgressionCatalog.integer(event.get("turns"), 1, 100): return "Invalid status duration."
		if type == "skip" and not event.get("reason") is String: return "Invalid skipped turn."
		if type == "complete" and (event.get("outcome") != engine.outcome or not CrawlProgressionCatalog.integer(event.get("gold"), 0, 2000000000) or int(event.gold) != engine.reward_gold()): return "Invalid completion event."
		engine.events.append(event.duplicate(true))
	session.combat = engine
	return ""
