extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_camp()
	_test_offers()
	_test_full_inventory()
	_test_equipment()
	_test_boss()
	_test_rule_explanations()
	print("Room flow checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)


func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text)


func fixture(seed_value: int = 82) -> CrawlRoomFlow:
	var session := CrawlEncounterSession.new()
	session.floor_state = CrawlFloorGenerator.new().generate(FloorDefinition.new(), seed_value)
	session.party = CrawlCombatContent.party()
	var flow := CrawlRoomFlow.new()
	flow.session = session
	return flow


func chest(flow: CrawlRoomFlow) -> void:
	for coords in flow.session.floor_state.rooms:
		if flow.session.floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
			flow.session.floor_state.current = coords
			flow.session.floor_state._visit()
			return


func _test_camp() -> void:
	var flow := fixture()
	var hero := flow.session.party[0]
	var current: Vector2i = flow.session.floor_state.current
	check(flow.open_camp(), "camp opens from cleared room")
	check(flow.session.floor_state.movement_reason(current) != "", "camp blocks travel")
	check(not flow.camp_action(hero.id, "heal").ok and flow.supplies == 6, "full HP cannot waste supplies")
	hero.hp = 99
	check(flow.camp_action(hero.id, "heal").ok and hero.hp == 120 and flow.supplies == 5, "heal is clamped and spends one supply")
	check(not flow.camp_action(hero.id, "heal").ok and flow.supplies == 5, "repeat full heal rejected")
	hero.mp = 0
	check(flow.camp_action(hero.id, "restore_mp").ok and hero.mp == 12 and flow.supplies == 4, "MP restore clamps to max")
	hero.max_mp = 0
	hero.mp = 0
	check(not flow.camp_action(hero.id, "restore_mp").ok and flow.supplies == 4, "no-MP actor cannot spend supplies")
	hero.hp = 0
	hero.statuses.poison = {"turns": 2, "potency": 2}
	check(not flow.camp_action(hero.id, "heal").ok, "healing cannot revive")
	check(flow.camp_action(hero.id, "revive").ok and hero.hp == 30 and flow.supplies == 2 and hero.statuses.is_empty(), "revive costs two and restores 25%")
	check(not flow.camp_action(hero.id, "revive").ok and flow.supplies == 2, "standing actor cannot be revived twice")
	check(flow.close_camp() and flow.session.floor_state.current == current, "return preserves current room")
	check(not flow.close_camp(), "return cannot repeat")
	check(flow.open_camp() and flow.supplies == 2, "reopening camp does not replenish supplies")
	flow.supplies = 0
	check(not flow.camp_action(hero.id, "heal").ok, "empty supplies reject action")
	flow.close_camp()
	flow.session.floor_state.travel_block_reason = "Combat in progress."
	check(not flow.open_camp() and not flow.search().ok, "pending controller state blocks room actions")
	flow.session.floor_state.travel_block_reason = ""
	flow.session.result_pending = true
	check(not flow.open_camp(), "unacknowledged results block camp")


func _test_offers() -> void:
	var flow := fixture()
	chest(flow)
	check(flow.open_chest(), "chest opens once")
	var offer_id: String = flow.pending_offer.id
	var item_ids: Dictionary = {}
	for item in flow.pending_offer.items:
		item_ids[item.id] = true
	check(item_ids.size() == 3, "offer contains three distinct gear choices")
	check(not flow.open_chest() and not flow.open_camp() and not flow.search().ok, "pending reward blocks conflicting actions")
	check(not flow.session.floor_state.move_to(flow.session.floor_state.start).ok, "pending reward blocks travel")
	check(not flow.claim(offer_id, 3, "").ok and flow.inventory.is_empty(), "invalid choice cannot grant gear")
	var repeated := fixture()
	chest(repeated)
	repeated.open_chest()
	check(repeated.pending_offer.items[0].id == flow.pending_offer.items[0].id and repeated.pending_offer.items[2].id == flow.pending_offer.items[2].id, "same seed/source reproduces offer")
	var result := flow.claim(offer_id, 1, flow.session.party[1].id)
	check(result.ok and flow.inventory.size() == 1 and flow.phase == "room", "choose exactly one item")
	check(flow.inventory[0].equipped_to == flow.session.party[1].id, "explicit recipient receives gear")
	check(not flow.claim(offer_id, 0, "").ok and flow.inventory.size() == 1, "duplicate claim cannot grant another choice")
	check(not flow.open_chest(), "claimed chest cannot reroll")
	check(flow.session.floor_state.rooms[flow.session.floor_state.current].chests[0].is_triggered, "interactable consumed")
	check(flow.session.floor_state.travel_block_reason == "", "claim releases travel lock")


func _test_full_inventory() -> void:
	var flow := fixture()
	chest(flow)
	for index in range(6):
		flow.inventory.append({"id": "fixture:%d" % index, "item": CrawlRoomFlow.item_pool()[index], "equipped_to": ""})
	flow.open_chest()
	var offer_id: String = flow.pending_offer.id
	check(not flow.claim(offer_id, 0, "").ok and flow.inventory.size() == 6, "full inventory rejects silent overwrite")
	check(not flow.claim(offer_id, 0, "", "unknown").ok, "unknown discard rejected")
	check(flow.claim(offer_id, 0, "", "fixture:2").ok and flow.inventory.size() == 6, "explicit discard makes space")
	check(flow.item_instance("fixture:2").is_empty(), "only chosen item discarded")


func _test_equipment() -> void:
	var flow := fixture()
	var first := flow.session.party[0]
	var second := flow.session.party[1]
	var first_attack := first.attack
	var second_attack := second.attack
	flow.inventory.append({"id": "iron", "item": CrawlRoomFlow.item_pool()[0], "equipped_to": ""})
	flow.inventory.append({"id": "swift", "item": CrawlRoomFlow.item_pool()[5], "equipped_to": ""})
	check(not flow.equip("iron", first.id), "equipment changes require camp")
	flow.open_camp()
	check(flow.equip("iron", first.id) and first.attack == first_attack + 5, "equipped item modifies battle stat")
	check(flow.equip("iron", first.id) and first.attack == first_attack + 5, "same assignment cannot stack stat")
	check(flow.equip("iron", second.id) and first.attack == first_attack and second.attack == second_attack + 5, "transfer removes old bonus")
	check(flow.equip("swift", second.id) and second.attack == second_attack + 3 and flow.item_instance("iron").equipped_to == "", "replacement parks previous item")
	flow.equip("swift", "")
	check(second.attack == second_attack, "putting in pack removes bonus")
	flow.inventory.append({"id": "hp", "item": CrawlRoomFlow.item_pool()[3], "equipped_to": ""})
	first.hp = 50
	flow.equip("hp", first.id)
	check(first.max_hp == 140 and first.hp == 50, "max HP gear does not grant free healing")
	first.hp = 135
	flow.equip("hp", first.id)
	check(first.hp == 135, "same assignment cannot clamp away health")
	flow.equip("hp", "")
	check(first.max_hp == 120 and first.hp == 120, "unequip safely clamps HP")
	check(flow.inventory[0].item.attack == 5, "authored gear definition remains immutable")


func _test_boss() -> void:
	var flow := fixture()
	var floor_state := flow.session.floor_state
	floor_state.current = floor_state.boss
	floor_state.encounters[floor_state.boss] = [{"enemy": load("res://data/enemies/koboldfighter.tres"), "count": 1, "formation": "Front"}]
	for actor in flow.session.party:
		actor.attack = 100
		actor.initiative = 100
	flow.session.begin()
	for index in range(100):
		if flow.session.result_pending:
			break
		flow.session.advance()
	check(flow.session.combat.outcome == "victory", "boss fixture wins")
	var result := flow.session.acknowledge()
	flow.after_combat(result)
	check(flow.phase == "reward" and flow.pending_offer.source == "boss", "boss acknowledgement opens mandatory offer")
	check(not flow.open_camp(), "boss reward cannot be bypassed through camp")
	var offer_id: String = flow.pending_offer.id
	flow.claim(offer_id, 0, flow.session.party[0].id)
	check(flow.phase == "ended" and flow.end_outcome == "victory", "boss choice completes the floor run")
	check(flow.inventory.is_empty() and flow.supplies == 0 and not flow.final_loadout.is_empty(), "run end clears gear and supplies with final summary")
	check(not flow.open_camp() and not flow.claim(offer_id, 2, "").ok, "ended run cannot camp or duplicate reward")
	flow.after_combat(result)
	check(flow.phase == "ended", "repeated result callback cannot reopen ended run")
	var fresh := fixture()
	check(fresh.inventory.is_empty() and fresh.supplies == 6 and fresh.session.party[0].attack == 16, "new run starts fresh")


func _test_rule_explanations() -> void:
	var engine := CrawlCombatEngine.new()
	var actor := CrawlCombatContent.party()[0]
	var enemy := EnemyGroup.new()
	enemy.initialize_group(load("res://data/enemies/koboldfighter.tres"), 1)
	engine.configure([actor], [enemy], 0)
	var rule := CrawlCombatContent.rule("test", "self_hp", 40, "potion", "self")
	actor.hp = 39
	check(engine.inspect_rule(actor, rule).reason == "", "absolute HP condition supported")
	actor.potions = 0
	check(engine.inspect_rule(actor, rule).reason.contains("potions"), "diagnostic explains depleted item")
	rule.metric = "self_mp_percent"
	actor.max_mp = 0
	actor.mp = 0
	check(engine.inspect_rule(actor, rule).reason.contains("no MP"), "diagnostic explains no-MP pool")
	rule.enabled = false
	check(engine.inspect_rule(actor, rule).reason == "Disabled.", "diagnostic explains disabled rule")
