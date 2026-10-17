extends SceneTree

var checks: int = 0
var failures: int = 0
var root_path: String


func _initialize() -> void:
	root_path = "res://.godot/progression_tests/%d" % Time.get_ticks_usec()
	_test_upgrades()
	_test_reward_reload()
	_test_terminal_reload()
	_test_settlement()
	_test_recovery()
	_test_write_failures()
	print("Progression checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)


func check(condition: bool, label_text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label_text)


func controller(name_key: String) -> CrawlProgressionController:
	var result := CrawlProgressionController.new()
	check(result.initialize(root_path.path_join(name_key)), "initialize " + name_key + ": " + result.notice)
	return result


func definition() -> FloorDefinition:
	var result := FloorDefinition.new()
	var option := EnemyGroupResource.new()
	option.enemy = load("res://data/enemies/koboldfighter.tres")
	option.min_count = 1
	option.max_count = 1
	result.standard_enemy_pool.append(option)
	result.max_encounter_groups = 1
	return result


func fund(target: CrawlProgressionController, amount: int = 10000) -> void:
	var candidate := target.profile.duplicate(true)
	candidate.gold = amount
	check(target._commit(candidate).ok, "fixture funding saved")


func start(target: CrawlProgressionController) -> bool:
	var result := target.start_run(definition(), 1042, target.profile.loadout)
	check(result.ok, "start run: " + result.get("reason", ""))
	return result.ok


func _test_upgrades() -> void:
	var target := controller("upgrades")
	check(not target.purchase("slot").ok and target.profile.gold == 0, "insufficient funds do not mutate profile")
	fund(target)
	check(not target.purchase("skill", "poison_strike").ok, "class prerequisite enforced")
	check(target.purchase("class", "rogue").ok, "Rogue unlock purchased")
	var gold: int = int(target.profile.gold)
	check(not target.purchase("class", "rogue").ok and target.profile.gold == gold, "duplicate class purchase rejected")
	check(target.purchase("skill", "poison_strike").ok, "new skill purchased")
	check(not target.purchase("skill", "poison_strike").ok, "duplicate skill purchase rejected")
	for index in range(3): check(target.purchase("slot").ok, "party slot purchase")
	check(target.profile.party_slots == 6 and not target.purchase("slot").ok, "party cap enforced by model")
	for index in range(3): check(target.purchase("rank", "fireball").ok, "skill rank purchase")
	check(not target.purchase("rank", "fireball").ok, "skill rank cap enforced")
	var skilled := CrawlProgressionCatalog.skills(target.profile)
	check(skilled.fireball.power == 19 and CrawlCombatContent.skills().fireball.power == 10, "upgrades clone party skill definitions")
	check(target.purchase("rank", "attack").ok, "basic attack rank purchased")
	var chosen: Array = ["rogue", "warrior", "cleric", "mage", "warrior", "mage"]
	check(target.start_run(definition(), 3, chosen).ok, "six-member purchased party starts")
	check(target.active.session.party[0].known_skills.has("poison_strike"), "unlocked skill available to associated class")
	check(target.active.session.party[1].id != target.active.session.party[4].id, "duplicate classes have unique actor IDs")
	var enemy_group := EnemyGroup.new()
	enemy_group.initialize_group(load("res://data/enemies/koboldfighter.tres"), 1)
	var engine := CrawlCombatEngine.new()
	engine.configure(target.active.session.party, [enemy_group], 0, target.active.session.skill_definitions)
	check(engine.choose_action(enemy_group.units[0]).skill.power == 0 and engine.skills.attack.power == 2, "party attack upgrades do not buff enemies")
	check(not target.purchase("rank", "attack").ok, "hub purchases blocked with active run")
	var reloaded := CrawlProgressionController.new()
	check(reloaded.initialize(target.store.directory) and reloaded.active != null, "profile and active run reload")
	check(reloaded.profile.party_slots == 6 and reloaded.profile.skills.has("poison_strike"), "unlocks and cap persist")


func _test_reward_reload() -> void:
	var target := controller("rewards")
	if not start(target): return
	var flow := target.active
	var floor_state := flow.session.floor_state
	for coords in floor_state.rooms:
		if floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
			floor_state.current = coords
			floor_state._visit()
	check(flow.open_chest() and target.checkpoint().ok, "pending chest offer saved")
	var before: Array = []
	for item in flow.pending_offer.items: before.append(item.id)
	var resumed := CrawlProgressionController.new()
	check(resumed.initialize(target.store.directory) and resumed.active != null, "pending offer reload")
	if resumed.active == null: return
	var after: Array = []
	for item in resumed.active.pending_offer.items: after.append(item.id)
	check(before == after and resumed.active.phase == "reward", "reload cannot reroll pending three-choice offer")
	var offer_id: String = resumed.active.pending_offer.id
	var hero_id: String = resumed.active.session.party[0].id
	check(resumed.active.claim(offer_id, 0, hero_id).ok and resumed.checkpoint().ok, "chosen gear and owner saved")
	var saved_stat := resumed.active.session.party[0].attack
	var final := CrawlProgressionController.new()
	check(final.initialize(target.store.directory) and final.active != null, "claimed offer reload")
	if final.active == null: return
	check(final.active.inventory.size() == 1 and final.active.inventory[0].equipped_to == hero_id and final.active.session.party[0].attack == saved_stat, "equipment restored without double-applying bonuses")
	check(not final.active.claim(offer_id, 1, "").ok and not final.active.open_chest(), "claimed reward and chest stay consumed after reload")
	check(final.active.open_camp(), "camp after reload")
	var actor := final.active.session.party[0]
	actor.hp = 1
	check(final.active.camp_action(actor.id, "heal").ok and final.checkpoint().ok, "camp resource mutation saved")
	var camp_reload := CrawlProgressionController.new()
	check(camp_reload.initialize(target.store.directory) and camp_reload.active.phase == "camp" and camp_reload.active.supplies == 5, "camp location and spent supplies persist")


func _test_terminal_reload() -> void:
	var target := controller("results")
	if not start(target): return
	var flow := target.active
	var floor_state := flow.session.floor_state
	var destination: Vector2i = floor_state.rooms[floor_state.current].doors[0].connected_room_coords
	check(floor_state.move_to(destination).ok and flow.session.begin(), "enter encounter")
	check(not target.checkpoint().ok, "mid-combat snapshot is explicitly unsupported")
	for index in range(1000):
		if flow.session.result_pending: break
		flow.session.advance()
	check(flow.session.combat.outcome == "victory" and target.checkpoint().ok, "terminal results saved before reward acknowledgement")
	var restored := CrawlProgressionController.new()
	check(restored.initialize(target.store.directory) and restored.active != null, "terminal results reload")
	if restored.active == null: return
	check(restored.active.session.result_pending and restored.active.session.run_gold == 0, "unclaimed gold remains unearned after reload")
	var result := restored.active.session.acknowledge()
	restored.active.after_combat(result)
	check(result.gold == 10 and restored.checkpoint().ok, "acknowledged gold saves")
	var again := CrawlProgressionController.new()
	check(again.initialize(target.store.directory) and again.active.session.run_gold == 10 and not again.active.session.result_pending, "acknowledged results cannot reappear and duplicate gold")
	check(again.active.session.claimed_rewards.has(again.active.session.encounter_id()), "stable encounter reward ID survives reload")


func _test_settlement() -> void:
	for outcome in ["victory", "defeat", "abandon"]:
		var target := controller("settle_" + outcome)
		if not start(target): continue
		target.active.session.run_gold = 123
		var flow := target.active
		var run_id := flow.run_id
		if outcome != "abandon": flow._end_run(outcome)
		check(target.checkpoint().ok, "pre-settlement checkpoint saved")
		var stale: String = FileAccess.get_file_as_string(target.store.directory.path_join("run.json"))
		check(target.settle(outcome).ok and target.profile.gold == 123, "earned gold banked on " + outcome)
		check(not target.settle(outcome).ok and target.profile.gold == 123, "duplicate settlement cannot bank twice")
		# Simulate power loss after the atomic profile commit, before run cleanup.
		var file := FileAccess.open(target.store.directory.path_join("run.json"), FileAccess.WRITE)
		file.store_string(stale)
		file.close()
		var reboot := CrawlProgressionController.new()
		check(reboot.initialize(target.store.directory) and reboot.active == null and reboot.profile.gold == 123 and reboot.profile.settled.has(run_id), "stale run ignored by durable settlement ledger")
		check(reboot.start_run(definition(), 9, reboot.profile.loadout).ok and reboot.active.session.run_gold == 0 and reboot.active.inventory.is_empty(), "new run retains bank but clears temporary state")
	check(CrawlProgressionCatalog.profile_error({"version": 1, "gold": -1}) != "", "negative profile values rejected")


func _test_recovery() -> void:
	var target := controller("recovery")
	fund(target, 500)
	check(target.purchase("class", "rogue").ok, "saved update creates previous valid backup")
	var path := target.store.directory.path_join("profile.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("damaged primary")
	file.close()
	var recovered := CrawlProgressionController.new()
	check(recovered.initialize(target.store.directory) and recovered.notice.contains("backup") and recovered.profile.gold == 500, "corrupted profile visibly falls back to last valid backup")
	var protected := controller("future")
	var payload := CrawlProgressionCatalog.fresh_profile()
	var body := JSON.stringify(payload)
	var envelope := {"format": "crawl-save", "kind": "profile", "schema": 99, "body": body, "digest": body.sha256_text()}
	file = FileAccess.open(protected.store.directory.path_join("profile.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	var future := CrawlProgressionController.new()
	check(not future.initialize(protected.store.directory) and future.blocked, "future schemas block mutations and retain files")
	check(not future.purchase("slot").ok, "unsupported save cannot be overwritten by purchase")
	var run_target := controller("run_recovery")
	if not start(run_target): return
	run_target.active.session.party[0].hp = 90
	check(run_target.checkpoint().ok, "run update preserves a valid backup")
	file = FileAccess.open(run_target.store.directory.path_join("run.json"), FileAccess.WRITE)
	file.store_string("broken run")
	file.close()
	var run_recovery := CrawlProgressionController.new()
	check(run_recovery.initialize(run_target.store.directory) and run_recovery.active != null and run_recovery.notice.contains("backup"), "corrupt run visibly restores previous checkpoint")
	var payload_run := CrawlRunCodec.pack(run_recovery.active, run_recovery.active_definition, run_recovery.run_skill_ranks)
	payload_run.party[0].hp = -1
	check(CrawlRunCodec.error(payload_run) != "", "negative saved actor resources rejected")
	payload_run = CrawlRunCodec.pack(run_recovery.active, run_recovery.active_definition, run_recovery.run_skill_ranks)
	payload_run.content = 999
	check(CrawlRunCodec.error(payload_run).begins_with("Unsupported"), "unknown content versions are protected")


func _test_write_failures() -> void:
	var target := controller("write_failure")
	fund(target, 500)
	var good_directory := target.store.directory
	var file_path := root_path.path_join("not_a_directory")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string("write-failure fixture")
	file.close()
	target.store.directory = file_path
	check(not target.purchase("class", "rogue").ok and target.profile.gold == 500 and not target.profile.classes.has("rogue"), "failed profile write cannot spend gold or grant upgrade")
	target.store.directory = good_directory
	check(target.purchase("class", "rogue").ok and target.profile.gold == 380, "purchase can retry after storage recovers")
	if not start(target): return
	target.active.session.run_gold = 77
	target.active._end_run("defeat")
	target.store.directory = file_path
	check(not target.settle("defeat").ok and target.active != null and target.profile.gold == 380, "failed banking retains active run and balance")
	target.store.directory = good_directory
	check(target.settle("defeat").ok and target.profile.gold == 457, "banking retry commits once after storage recovers")
	file = FileAccess.open(good_directory.path_join("profile.json"), FileAccess.WRITE)
	file.store_string("corrupt profile immediately after bank")
	file.close()
	var receipt_recovery := CrawlProgressionController.new()
	check(receipt_recovery.initialize(good_directory) and receipt_recovery.profile.gold == 457 and receipt_recovery.active == null, "settlement receipt restores bank deposit missing from recovered profile backup")
	var second_boot := CrawlProgressionController.new()
	check(second_boot.initialize(good_directory) and second_boot.profile.gold == 457, "receipt reconciliation cannot deposit twice")
