extends SceneTree

var failures: int = 0
var checks: int = 0
var scene: Node
var resolution: Vector2i


func _initialize() -> void:
	call_deferred("_run")


func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	for size_value in [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		resolution = size_value
		root.size = resolution
		root.content_scale_size = resolution
		scene._generate()
		for actor in scene.session.party:
			actor.attack = 500
			actor.magic = 500
			actor.initiative = 100
		# Enter an actual connected room; preserve combat and results transition.
		for coords in scene.floor_state.discovered:
			if scene.floor_state.movement_reason(coords) == "":
				scene._move(coords)
				break
		finish_fight()
		verify(scene.current_view == "results", "terminal fight shows a separate results screen")
		await capture("results")
		scene.results_panel.continue_button.pressed.emit()
		verify(scene.current_view == "map", "results continue leads to room actions")
		var key_room: Vector2i = scene.floor_state.key_pickups.keys()[0]
		walk_to(key_room)
		scene._search()
		verify(not scene.floor_state.keys.is_empty(), "search obtains reachable key")
		var chest_room := Vector2i.ZERO
		for coords in scene.floor_state.rooms:
			if scene.floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
				chest_room = coords
		walk_to(chest_room)
		verify(scene.floor_state.current == chest_room, "key allows actual travel into chest room")
		# Fill all six slots so the reward UI must resolve inventory capacity explicitly.
		for index in range(6):
			scene.flow.inventory.append({"id": "fixture:%d" % index, "item": CrawlRoomFlow.item_pool()[index], "equipped_to": ""})
		scene._open_chest()
		verify(scene.current_view == "reward" and scene.reward_panel.buttons.size() == 3, "chest shows exactly three choices")
		verify(scene.reward_panel.buttons[0].disabled, "full inventory disables reward claim until discard chosen")
		scene._open_camp()
		verify(scene.current_view == "reward" and scene.flow.phase == "reward", "pending reward rejects camp without leaving the reward screen")
		scene.message.text = "Choose one item and its destination. Select an explicit discard when inventory is full."
		scene.reward_panel.recipient.select(1)
		scene.reward_panel.recipient.item_selected.emit(1)
		scene.reward_panel.discard.select(1)
		scene.reward_panel.discard.item_selected.emit(1)
		verify(not scene.reward_panel.buttons[1].disabled, "explicit discard enables claim")
		await capture("loot")
		var old_button: Button = scene.reward_panel.buttons[1]
		var offer_id: String = scene.flow.pending_offer.id
		old_button.pressed.emit()
		old_button.pressed.emit()
		verify(scene.flow.inventory.size() == 6 and scene.current_view == "map", "double-click grants one item and returns to map")
		verify(scene.flow.claimed_offers.has(offer_id), "chosen offer is marked consumed")
		var origin: Vector2i = scene.floor_state.current
		scene._open_camp()
		var hero: CrawlCombatant = scene.session.party[0]
		hero.hp = hero.max_hp - 1
		# Include the no-MP edge case in the real camp screen.
		var no_mp: CrawlCombatant = scene.session.party[2]
		no_mp.max_mp = 0
		no_mp.mp = 0
		scene.camp_panel.bind(scene.flow)
		verify(scene.camp_panel.action_buttons[7].disabled, "camp correctly disables restore for no-MP member")
		var supply_count: int = scene.flow.supplies
		var heal_button: Button = scene.camp_panel.action_buttons[0]
		heal_button.pressed.emit()
		heal_button.pressed.emit()
		verify(hero.hp == hero.max_hp and scene.flow.supplies == supply_count - 1, "repeated heal cannot spend supplies after reaching full HP")
		await capture("camp")
		scene.camp_panel.returned.emit()
		verify(scene.current_view == "map" and scene.floor_state.current == origin, "camp returns to same room")
		var parent: Vector2i = scene.floor_state.rooms[chest_room].doors[0].connected_room_coords
		scene._move(parent)
		scene._move(chest_room)
		verify(scene.flow.chest_reason() != "" and scene.chest_button.disabled, "cleared revisit preserves consumed chest")
		# Test a boss encounter through the same movement/combat/results/reward flow.
		walk_to(scene.floor_state.boss, true)
		verify(scene.current_view == "reward" and scene.flow.pending_offer.source == "boss", "boss results lead to three-choice spoils")
		scene.reward_panel.discard.select(1)
		scene.reward_panel.discard.item_selected.emit(1)
		scene.reward_panel.buttons[0].pressed.emit()
		verify(scene.current_view == "end" and scene.flow.inventory.is_empty(), "boss gear choice finishes run and clears inventory")
		await capture("complete")
		scene._generate()
		verify(scene.flow.supplies == 6 and scene.flow.inventory.is_empty() and scene.session.run_gold == 0, "new run has no old run inventory or resources")
	await test_tactics_and_keyboard()
	await test_stress_display()
	print("Full UI flow: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func capture(name_key: String) -> void:
	for frame_index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	verify(scene.message.get_global_rect().end.y <= root.get_visible_rect().size.y, "%s footer fits at %s (actual %s)" % [name_key, resolution, scene.message.get_global_rect()])
	var panel: Control = {"results": scene.results_panel, "loot": scene.reward_panel, "camp": scene.camp_panel, "complete": scene.end_panel}[name_key]
	verify(panel.get_combined_minimum_size().x <= panel.size.x, "%s panel fits width at %s" % [name_key, resolution])
	var body: Control = scene.end_body if name_key == "complete" else panel.body
	verify(body.get_combined_minimum_size().x <= panel.size.x, "%s contents fit width at %s" % [name_key, resolution])
	verify(root.get_texture().get_image().save_png("res://tests/preview_%s_%dx%d.png" % [name_key, resolution.x, resolution.y]) == OK, "screenshot saved")


func finish_fight() -> void:
	for index in range(10000):
		if scene.session.result_pending:
			return
		scene._process(0.18)
	verify(false, "fixture combat did not terminate")


func walk_to(destination: Vector2i, allow_boss: bool = false) -> void:
	var floor_state: CrawlFloorState = scene.floor_state
	var queue: Array[Vector2i] = [floor_state.current]
	var parents: Dictionary = {floor_state.current: floor_state.current}
	while not queue.is_empty():
		var coords: Vector2i = queue.pop_front()
		for door in floor_state.rooms[coords].doors:
			var target: Vector2i = door.connected_room_coords
			if parents.has(target) or (target == floor_state.boss and not allow_boss):
				continue
			if door.state == DungeonEnums.DoorState.LOCKED and not floor_state._can_unlock(door):
				continue
			parents[target] = coords
			queue.append(target)
	if not parents.has(destination):
		verify(false, "walk target unreachable")
		return
	var path: Array[Vector2i] = []
	var step := destination
	while step != floor_state.current:
		path.push_front(step)
		step = parents[step]
	for target in path:
		if not floor_state.rooms[target].is_cleared:
			floor_state.encounters[target] = [{"enemy": load("res://data/enemies/koboldfighter.tres"), "count": 1, "formation": "Front"}]
		scene._move(target)
		verify(floor_state.current == target, "movement commits connected edge")
		if scene.session.combat != null and scene.session.combat.outcome == "ongoing":
			finish_fight()
			scene._acknowledge_results()


func test_tactics_and_keyboard() -> void:
	scene._generate()
	scene._toggle_tactics()
	var actor: CrawlCombatant = scene.session.party[0]
	var number_fields: Array[Node] = scene.tactics_panel.list.find_children("*", "SpinBox", true, false)
	number_fields[0].value = 17
	verify(actor.tactics[0].threshold == 17, "tactics threshold control updates the live per-run rule")
	var action_fields: Array[Node] = scene.tactics_panel.list.find_children("*", "OptionButton", true, false)
	var action: OptionButton = action_fields[0]
	for index in range(action.item_count):
		if action.get_item_metadata(index) == "defend":
			action.select(index)
			action.item_selected.emit(index)
			break
	verify(actor.tactics[0].skill_id == "defend", "action selector changes the learned skill")
	var count := actor.tactics.size()
	for button in scene.tactics_panel.list.find_children("*", "Button", true, false):
		if button.text == "Add rule":
			button.pressed.emit()
			break
	await process_frame
	verify(actor.tactics.size() == count + 1, "add rule control creates a rule")
	var first: CrawlTacticRule = actor.tactics[0]
	for button in scene.tactics_panel.list.find_children("*", "Button", true, false):
		if button.text == "↓" and not button.disabled:
			button.pressed.emit()
			break
	await process_frame
	verify(actor.tactics[1] == first, "priority button reorders rules")
	scene._generate()
	scene.map.selected_room = scene.floor_state.current
	var destination: Vector2i = scene.floor_state.current
	for coords in scene.floor_state.discovered:
		if scene.floor_state.movement_reason(coords) == "":
			destination = coords
			break
	var direction: Vector2i = destination - scene.floor_state.current
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = {Vector2i.LEFT: KEY_LEFT, Vector2i.RIGHT: KEY_RIGHT, Vector2i.UP: KEY_UP, Vector2i.DOWN: KEY_DOWN}[direction]
	scene.map._gui_input(key)
	verify(scene.map.selected_room == destination, "arrow key selects a visible room")
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ENTER
	scene.map._gui_input(key)
	verify(scene.floor_state.current == destination, "Enter submits movement through the controller")


func test_stress_display() -> void:
	root.size = Vector2i(960, 600)
	root.content_scale_size = root.size
	scene._generate()
	var group := EnemyGroup.new()
	group.initialize_group(load("res://data/enemies/goblinzombie.tres"), 64, null, "stress:horde")
	group.enemy_data = group.enemy_data.duplicate()
	group.enemy_data.display_name = "Restless Guardians of the Forgotten Catacombs"
	var hero: CrawlCombatant = scene.session.party[0]
	hero.display_name = "Alessandra, Warden of the Northern Gate"
	hero.statuses = {"poison": {"turns": 2, "potency": 1}, "stun": {"turns": 1, "potency": 0}, "Blessing": {"turns": 2, "potency": 0}, "Ward": {"turns": 2, "potency": 0}, "Haste": {"turns": 2, "potency": 0}}
	hero.defending = true
	hero.max_mp = 0
	hero.mp = 0
	var engine := CrawlCombatEngine.new()
	engine.configure(scene.session.party, [group], 0)
	for index in range(300):
		engine._emit("round")
	scene.combat_panel.bind(engine)
	scene._show_view("combat")
	for frame_index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	verify(scene.combat_panel.log_lines.size() == 120, "fast combat log stays bounded")
	verify(scene.combat_panel.enemy_labels.size() == 1 and group.current_count == 64, "large authored horde stays one enemy entry")
	verify(scene.combat_panel.log_view.get_global_rect().end.y <= root.get_visible_rect().size.y, "long names and many statuses do not push log beyond window")
	verify(root.get_texture().get_image().save_png("res://tests/preview_stress_960x600.png") == OK, "stress screenshot saved")
