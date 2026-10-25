class_name CrawlProgressionController
extends RefCounted

var store := CrawlSaveStore.new()
var economy := CrawlContent.economy()
var profile: Dictionary = {}
var active: CrawlRoomFlow
var active_definition: FloorDefinition
var run_skill_ranks: Dictionary = {}
var notice: String = ""
var blocked: bool = false


func initialize(directory: String = "user://progression") -> bool:
	store.directory = directory
	active = null
	blocked = false
	notice = ""
	var content_errors := CrawlContent.CATALOG.errors()
	if not content_errors.is_empty():
		blocked = true
		notice = "Invalid game content: " + "; ".join(content_errors)
		return false
	var loaded := store.load_document("profile", CrawlProgressionCatalog.profile_error)
	if not loaded.ok:
		if not loaded.get("missing", false) or FileAccess.file_exists(directory.path_join("run.json")) or FileAccess.file_exists(directory.path_join("run.json.bak")):
			blocked = true
			notice = loaded.reason + " Progression is read-only until a valid profile is restored."
			profile = CrawlProgressionCatalog.fresh_profile()
			return false
		profile = CrawlProgressionCatalog.fresh_profile()
		var written := store.write_document("profile", profile, CrawlProgressionCatalog.profile_error)
		if not written.ok:
			blocked = true
			notice = written.reason
			return false
	else:
		profile = loaded.payload
		notice = loaded.notice
	var run := store.load_document("run", CrawlRunCodec.error)
	if not run.ok:
		if not run.get("missing", false):
			blocked = true
			notice += " " + run.reason
		return not blocked
	if run.notice != "": notice += " " + run.notice
	if run.payload.status == "settled":
		var receipt: Dictionary = run.payload
		if not profile.settled.has(receipt.run_id):
			# A recovered profile backup can precede the last bank deposit. The durable
			# run receipt restores that deposit and its ID together, never twice.
			var candidate := profile.duplicate(true)
			candidate.gold = int(candidate.gold) + int(receipt.gold)
			candidate.settled[receipt.run_id] = {"gold": int(receipt.gold), "outcome": receipt.outcome}
			candidate.next_run = maxi(int(candidate.next_run), receipt.run_id.trim_prefix("run-").to_int() + 1)
			var recovered_notice := notice
			var committed := _commit(candidate)
			if not committed.ok:
				blocked = true
				return false
			notice = recovered_notice + " Recovered the latest bank deposit from its settlement receipt."
		return true
	if profile.settled.has(run.payload.run_id): return true
	var decoded := CrawlRunCodec.unpack(run.payload)
	if not decoded.ok:
		blocked = true
		notice += decoded.reason
		return false
	active = decoded.flow
	active.session.banked_gold = int(profile.gold)
	active_definition = decoded.definition
	run_skill_ranks = decoded.skill_ranks
	if active.session.party.size() != int(profile.party_slots):
		blocked = true
		notice += " Saved party size disagrees with profile."
	for actor in active.session.party:
		if not profile.classes.has(actor.class_id):
			blocked = true
			notice += " Saved party uses a locked class."
		var allowed := CrawlProgressionCatalog.party(profile, [actor.class_id])[0].known_skills
		for skill_id in actor.known_skills:
			if not allowed.has(skill_id):
				blocked = true
				notice += " Saved party uses a locked skill."
	for skill_id in run_skill_ranks:
		if int(run_skill_ranks[skill_id]) > int(profile.ranks.get(skill_id, 0)):
			blocked = true
			notice += " Saved run skill ranks disagree with profile."
	if blocked: active = null
	return not blocked


func _commit(candidate: Dictionary) -> Dictionary:
	if blocked: return {"ok": false, "reason": notice}
	var result := store.write_document("profile", candidate, CrawlProgressionCatalog.profile_error)
	if result.ok:
		profile = candidate
		notice = ""
	else: notice = result.reason
	return result


func purchase_reason(kind: String, id: String = "") -> String:
	if blocked: return notice
	if active != null: return "Finish or abandon the saved run before purchasing upgrades."
	var price := 0
	match kind:
		"slot":
			if int(profile.party_slots) >= economy.maximum_slots: return "Party size is at the %d-member cap." % economy.maximum_slots
			price = economy.slot_costs[int(profile.party_slots) - economy.starting_slots]
		"class":
			if not economy.class_costs.has(id): return "Unknown class upgrade."
			if profile.classes.has(id): return "Class already unlocked."
			price = int(economy.class_costs[id])
		"skill":
			if not economy.skill_unlocks.has(id): return "Unknown skill unlock."
			if profile.skills.has(id): return "Skill already unlocked."
			if not profile.classes.has(economy.skill_unlocks[id]["class"]): return "Unlock the associated class first."
			price = int(economy.skill_unlocks[id].cost)
		"rank":
			if not economy.rank_costs.has(id): return "Unknown skill upgrade."
			if economy.skill_unlocks.has(id) and not profile.skills.has(id): return "Unlock this skill first."
			var rank := int(profile.ranks.get(id, 0))
			if rank >= economy.maximum_skill_rank: return "This skill is at maximum rank."
			price = int(economy.rank_costs[id]) * (rank + 1)
		_: return "Unknown purchase."
	return "Requires %d gold; banked gold is %d." % [price, int(profile.gold)] if int(profile.gold) < price else ""


func price(kind: String, id: String = "") -> int:
	match kind:
		"slot": return economy.slot_costs[int(profile.party_slots) - economy.starting_slots] if int(profile.party_slots) < economy.maximum_slots else 0
		"class": return int(economy.class_costs.get(id, 0))
		"skill": return int(economy.skill_unlocks.get(id, {}).get("cost", 0))
		"rank": return int(economy.rank_costs.get(id, 0)) * (int(profile.ranks.get(id, 0)) + 1)
	return 0


func purchase(kind: String, id: String = "") -> Dictionary:
	var reason := purchase_reason(kind, id)
	if reason != "": return {"ok": false, "reason": reason}
	var candidate := profile.duplicate(true)
	candidate.gold = int(candidate.gold) - price(kind, id)
	match kind:
		"slot":
			candidate.party_slots = int(candidate.party_slots) + 1
			candidate.loadout.append(economy.starting_party[0].id)
		"class": candidate.classes.append(id)
		"skill": candidate.skills.append(id)
		"rank": candidate.ranks[id] = int(candidate.ranks.get(id, 0)) + 1
	var result := _commit(candidate)
	if result.ok: result.reason = "Upgrade purchased."
	return result


func start_run(definition: FloorDefinition, seed_value: int, classes: Array) -> Dictionary:
	if blocked or active != null: return {"ok": false, "reason": notice if blocked else "Resume or abandon the current saved run first."}
	if classes.size() != int(profile.party_slots): return {"ok": false, "reason": "Fill all purchased party slots."}
	for class_id in classes:
		if not profile.classes.has(class_id): return {"ok": false, "reason": "This party contains a locked class."}
	var candidate := profile.duplicate(true)
	var run_id := "run-%012d" % int(candidate.next_run)
	candidate.next_run = int(candidate.next_run) + 1
	candidate.loadout = classes.duplicate()
	var result := _commit(candidate)
	if not result.ok: return result
	var session := CrawlEncounterSession.new()
	session.floor_state = CrawlFloorGenerator.new().generate(definition, seed_value)
	session.party = CrawlProgressionCatalog.party(profile, classes)
	session.skill_definitions = CrawlProgressionCatalog.skills(profile)
	session.banked_gold = int(profile.gold)
	active = CrawlRoomFlow.new()
	active.session = session
	active.run_id = run_id
	active_definition = definition
	run_skill_ranks = profile.ranks.duplicate(true)
	result = checkpoint()
	if not result.ok:
		active = null
		return result
	return {"ok": true, "flow": active}


func checkpoint() -> Dictionary:
	if blocked or active == null: return {"ok": false, "reason": notice if blocked else "No active run to save."}
	var payload := CrawlRunCodec.pack(active, active_definition, run_skill_ranks)
	if payload.is_empty(): return {"ok": false, "reason": "This is not a supported save boundary. Combat resumes from its previous room checkpoint."}
	var result := store.write_document("run", payload, CrawlRunCodec.error)
	if not result.ok: notice = result.reason
	return result


func save_presets() -> Dictionary:
	if active == null: return {"ok": true}
	var candidate := profile.duplicate(true)
	var seen: Dictionary = {}
	for actor in active.session.party:
		if seen.has(actor.class_id): continue
		seen[actor.class_id] = true
		var rules: Array = []
		for rule in actor.tactics: rules.append(CrawlProgressionCatalog.pack_rule(rule))
		candidate.presets[actor.class_id] = rules
	if candidate.presets == profile.presets: return {"ok": true}
	return _commit(candidate)


func settle(outcome: String) -> Dictionary:
	if blocked or active == null: return {"ok": false, "reason": notice if blocked else "No active run to settle."}
	if outcome not in ["victory", "defeat", "draw", "stalemate", "invalid", "abandon"]: return {"ok": false, "reason": "Unknown run outcome."}
	if outcome != "abandon" and (active.phase != "ended" or active.end_outcome != outcome): return {"ok": false, "reason": "The run has not reached that outcome."}
	var run_id := active.run_id
	var gold := active.session.run_gold
	var candidate := profile.duplicate(true)
	var already_settled: bool = candidate.settled.has(run_id)
	if not already_settled:
		candidate.gold = int(candidate.gold) + gold
		candidate.settled[run_id] = {"gold": gold, "outcome": outcome}
		var seen: Dictionary = {}
		for actor in active.session.party:
			if seen.has(actor.class_id): continue
			seen[actor.class_id] = true
			candidate.presets[actor.class_id] = []
			for rule in actor.tactics: candidate.presets[actor.class_id].append(CrawlProgressionCatalog.pack_rule(rule))
		var committed := _commit(candidate) # Gold and settlement ID commit in ONE profile replacement.
		if not committed.ok: return committed
	if active.phase != "ended": active._end_run(outcome)
	var cleanup := store.write_document("run", {"version": 1, "status": "settled", "run_id": run_id, "gold": gold, "outcome": outcome}, CrawlRunCodec.error)
	active = null # The profile ledger also rejects a stale run if tombstone replacement failed.
	if not cleanup.ok: notice = "Gold is safely banked. Run cleanup will be retried on the next save: " + cleanup.reason
	return {"ok": true, "gold": 0 if already_settled else gold, "already_settled": already_settled, "reason": "" if cleanup.ok else notice}
