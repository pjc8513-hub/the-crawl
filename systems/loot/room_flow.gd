class_name CrawlRoomFlow
extends RefCounted
## Validated room/camp/reward transitions. Screens submit intents to this model.

const GEAR_CAPACITY: int = 6
const STARTING_SUPPLIES: int = 6
const CAMP_HEAL: int = 40
const CAMP_MP: int = 15
var session: CrawlEncounterSession
var phase: String = "room" # room, camp, reward, ended
var supplies: int = STARTING_SUPPLIES
var inventory: Array[Dictionary] = [] # {id, item: ItemDefinition, equipped_to}
var pending_offer: Dictionary = {}
var claimed_offers: Dictionary = {}
var offers: Dictionary = {}
var end_outcome: String = ""
var final_loadout: Array[String] = []


static func item_pool() -> Array[CrawlItemDefinition]:
	var result: Array[CrawlItemDefinition] = []
	for spec in [
		["iron_edge", "Iron Edge", "weapon", "A dependable blade for the front line.", {"attack": 5}],
		["ember_staff", "Ember Staff", "weapon", "A staff that strengthens spells and expands mana.", {"magic": 5, "max_mp": 6}],
		["ward_mail", "Ward Mail", "armor", "Reinforced links for a sturdier defender.", {"armor": 2, "max_hp": 12}],
		["bloodstone", "Bloodstone Charm", "charm", "A deep reserve of vitality.", {"max_hp": 20}],
		["focus", "Focus Charm", "charm", "A talisman for longer spell rotations.", {"max_mp": 10, "magic": 2}],
		["swift_blade", "Swift Blade", "weapon", "Strike harder and earlier in the round.", {"attack": 3, "initiative": 2}]
	]:
		var item := CrawlItemDefinition.new()
		item.id = spec[0]
		item.display_name = spec[1]
		item.slot = spec[2]
		item.description = spec[3]
		for stat in spec[4]:
			item.set(stat, spec[4][stat])
		result.append(item)
	return result


func room_reason() -> String:
	if session == null or session.floor_state == null:
		return "No active run."
	if phase != "room":
		return "Finish the current screen before using room actions."
	if session.result_pending or (session.combat != null and session.combat.outcome == "ongoing"):
		return "Resolve combat and its results first."
	if session.floor_state.travel_block_reason != "":
		return session.floor_state.travel_block_reason
	if not session.floor_state.rooms[session.floor_state.current].is_cleared:
		return "Clear this room first."
	return ""


func search() -> Dictionary:
	var reason := room_reason()
	if reason != "":
		return {"ok": false, "reason": reason}
	return session.floor_state.search_current_room()


func activate_switch(switch_id: String) -> bool:
	return room_reason() == "" and session.floor_state.activate_switch(switch_id)


func open_camp() -> bool:
	if room_reason() != "":
		return false
	phase = "camp"
	session.floor_state.travel_block_reason = "Return from camp before travelling."
	return true


func close_camp() -> bool:
	if phase != "camp":
		return false
	phase = "room"
	session.floor_state.travel_block_reason = ""
	return true


func actor_by_id(actor_id: String) -> CrawlCombatant:
	for actor in session.party:
		if actor.id == actor_id:
			return actor
	return null


func camp_reason(actor_id: String, action: String) -> String:
	if phase != "camp":
		return "Open camp in a cleared room first."
	var actor := actor_by_id(actor_id)
	if actor == null:
		return "Choose a party member."
	if action not in ["heal", "restore_mp", "revive"]:
		return "Unknown camp action."
	if supplies < (2 if action == "revive" else 1):
		return "Not enough camp supplies."
	if action == "revive":
		return "This member is already standing." if actor.alive() else ""
	if not actor.alive():
		return "Revive this member first."
	if action == "heal" and actor.hp >= actor.max_hp:
		return "HP is already full."
	if action == "restore_mp" and actor.max_mp == 0:
		return "This member has no MP pool."
	if action == "restore_mp" and actor.mp >= actor.max_mp:
		return "MP is already full."
	return ""


func camp_action(actor_id: String, action: String) -> Dictionary:
	var reason := camp_reason(actor_id, action)
	if reason != "":
		return {"ok": false, "reason": reason}
	var actor := actor_by_id(actor_id)
	supplies -= 2 if action == "revive" else 1
	match action:
		"heal": actor.hp = mini(actor.max_hp, actor.hp + CAMP_HEAL)
		"restore_mp": actor.mp = mini(actor.max_mp, actor.mp + CAMP_MP)
		"revive":
			actor.hp = maxi(1, floori(actor.max_hp * 0.25))
			actor.statuses.clear()
	return {"ok": true, "reason": "%s is ready. %d camp supplies remain." % [actor.display_name, supplies]}


func chest_reason() -> String:
	var reason := room_reason()
	if reason != "":
		return reason
	var floor_state := session.floor_state
	var room: DungeonRoomData = floor_state.rooms[floor_state.current]
	if room.node_type != DungeonEnums.RoomNodeType.CHEST_ROOM and room.chests.is_empty():
		return "There is no chest in this room."
	if claimed_offers.has(_offer_id("chest")):
		return "This chest has already been claimed."
	return ""


func open_chest() -> bool:
	if chest_reason() != "":
		return false
	_open_offer("chest")
	return true


func _offer_id(source: String) -> String:
	var floor_state := session.floor_state
	return "%s:%d:%s" % [source, floor_state.floor_depth, floor_state.current]


func _open_offer(source: String) -> void:
	var offer_id := _offer_id(source)
	if not offers.has(offer_id):
		var rng := RandomNumberGenerator.new()
		rng.seed = ("loot:v1:%d:%s" % [session.floor_state.loot_seed, offer_id]).hash()
		var available := item_pool()
		var items: Array[CrawlItemDefinition] = []
		for index in range(3):
			var chosen := rng.randi_range(0, available.size() - 1)
			items.append(available[chosen])
			available.remove_at(chosen)
		offers[offer_id] = {"id": offer_id, "source": source, "items": items}
	pending_offer = offers[offer_id]
	phase = "reward"
	session.floor_state.travel_block_reason = "Choose one gear reward before travelling."


func after_combat(result: Dictionary) -> void:
	if not result.get("ok", false) or phase != "room":
		return
	if result.outcome != "victory":
		_end_run(result.outcome)
	elif session.floor_state.current == session.floor_state.boss:
		_open_offer("boss")


func item_instance(item_id: String) -> Dictionary:
	for entry in inventory:
		if entry.id == item_id:
			return entry
	return {}


func claim_reason(offer_id: String, index: int, recipient: String, discard_id: String = "") -> String:
	if phase != "reward" or pending_offer.is_empty() or pending_offer.id != offer_id or claimed_offers.has(offer_id):
		return "This offer is no longer available."
	if index < 0 or index >= pending_offer.items.size() or not pending_offer.items[index].is_valid():
		return "Choose one of the three offered items."
	if recipient != "" and actor_by_id(recipient) == null:
		return "Choose a valid party member or the backpack."
	if discard_id != "" and item_instance(discard_id).is_empty():
		return "The item selected for discard is no longer present."
	if inventory.size() + 1 - (1 if discard_id != "" else 0) > GEAR_CAPACITY:
		return "Gear inventory is full. Choose an item to discard."
	return ""


func claim(offer_id: String, index: int, recipient: String, discard_id: String = "") -> Dictionary:
	var reason := claim_reason(offer_id, index, recipient, discard_id)
	if reason != "":
		return {"ok": false, "reason": reason}
	if discard_id != "":
		_remove_item(discard_id)
	var item: CrawlItemDefinition = pending_offer.items[index]
	var instance_id := "%s:%d" % [offer_id, index]
	inventory.append({"id": instance_id, "item": item, "equipped_to": ""})
	if recipient != "":
		_equip(instance_id, recipient)
	claimed_offers[offer_id] = true
	var source: String = pending_offer.source
	for chest in session.floor_state.rooms[session.floor_state.current].chests:
		chest.is_triggered = true
	pending_offer = {}
	phase = "room"
	session.floor_state.travel_block_reason = ""
	if source == "boss":
		_end_run("victory")
	return {"ok": true, "reason": "Claimed %s." % item.display_name}


func equip(item_id: String, recipient: String) -> bool:
	if phase != "camp" or item_instance(item_id).is_empty() or (recipient != "" and actor_by_id(recipient) == null):
		return false
	_equip(item_id, recipient)
	return true


func _apply(actor: CrawlCombatant, item: CrawlItemDefinition, sign_value: int) -> void:
	for stat in item.bonuses():
		actor.set(stat, actor.get(stat) + item.bonuses()[stat] * sign_value)
	actor.hp = clampi(actor.hp, 0, actor.max_hp)
	actor.mp = clampi(actor.mp, 0, actor.max_mp)


func _unequip(entry: Dictionary) -> void:
	if entry.equipped_to != "":
		var actor := actor_by_id(entry.equipped_to)
		_apply(actor, entry.item, -1)
		actor.equipment.erase(entry.item.slot)
		entry.equipped_to = ""


func _equip(item_id: String, recipient: String) -> void:
	var entry := item_instance(item_id)
	if entry.equipped_to == recipient:
		return
	_unequip(entry)
	if recipient == "":
		return
	for existing in inventory:
		if existing.equipped_to == recipient and existing.item.slot == entry.item.slot:
			_unequip(existing)
	var actor := actor_by_id(recipient)
	entry.equipped_to = recipient
	actor.equipment[entry.item.slot] = entry.item
	_apply(actor, entry.item, 1)


func _remove_item(item_id: String) -> void:
	for index in range(inventory.size()):
		if inventory[index].id == item_id:
			_unequip(inventory[index])
			inventory.remove_at(index)
			return


func _end_run(outcome: String) -> void:
	phase = "ended"
	end_outcome = outcome
	session.floor_state.travel_block_reason = "Run complete. Start a new run to play again." if outcome == "victory" else "The run has ended. Start a new run to play again."
	for entry in inventory:
		final_loadout.append(entry.item.display_name)
		_unequip(entry)
	inventory.clear()
	supplies = 0
