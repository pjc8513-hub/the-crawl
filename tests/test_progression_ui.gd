extends SceneTree

var checks: int = 0
var failures: int = 0
var scene: Node
var directory: String


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label_text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label_text)


func boot() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://scenes/main.tscn").instantiate()
	scene.save_directory = directory
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	check(scene.current_view == "hub", "startup enters the lodge")
	check(not scene.progression.blocked, "isolated save loads: " + scene.progression.notice)


func capture(name_key: String, resolution: Vector2i) -> void:
	for index in range(6): await process_frame
	await RenderingServer.frame_post_draw
	check(scene.message.get_global_rect().end.y <= root.get_visible_rect().size.y, "persistent UI footer fits")
	check(root.get_texture().get_image().save_png("res://tests/preview_%s_%dx%d.png" % [name_key, resolution.x, resolution.y]) == OK, "persistent UI screenshot saved")


func _run() -> void:
	var base := "res://.godot/progression_ui/%d" % Time.get_ticks_usec()
	for resolution in [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		directory = base.path_join("%dx%d" % [resolution.x, resolution.y])
		root.size = resolution
		root.content_scale_size = resolution
		await boot()
		check(scene.hub_panel.selectors.size() == 3, "three starting party slots shown")
		var funded: Dictionary = scene.progression.profile.duplicate(true)
		funded.gold = 5000
		check(scene.progression._commit(funded).ok, "fixture balance saved")
		scene._show_hub()
		scene.hub_panel.purchase_requested.emit("class", "rogue")
		scene.hub_panel.purchase_requested.emit("slot", "")
		scene.hub_panel.purchase_requested.emit("skill", "poison_strike")
		scene.hub_panel.purchase_requested.emit("rank", "attack")
		check(scene.progression.profile.party_slots == 4 and scene.hub_panel.selectors.size() == 4, "purchased slot updates preparation UI")
		var selector: OptionButton = scene.hub_panel.selectors[0]
		for index in range(selector.item_count):
			if selector.get_item_metadata(index) == "rogue": selector.select(index)
		await capture("hub", resolution)
		scene.hub_panel.scroll_vertical = int(scene.hub_panel.upgrades_heading.position.y)
		await capture("upgrades", resolution)
		scene.hub_panel.scroll_vertical = 0
		# A simple authored spawn pool isolates persistence from encounter balance.
		scene.definition.standard_enemy_pool.clear()
		var option := EnemyGroupResource.new()
		option.enemy = load("res://data/enemies/koboldfighter.tres")
		option.min_count = 1
		option.max_count = 1
		scene.definition.standard_enemy_pool.append(option)
		scene.definition.max_encounter_groups = 1
		scene.hub_panel.run_requested.emit()
		check(scene.current_view == "map" and scene.session.party.size() == 4, "hub starts selected upgraded party")
		check(scene.session.party[0].class_id == "rogue" and scene.session.party[0].known_skills.has("poison_strike"), "selected class and skill unlock apply")
		check(scene.session.skill_definitions.attack.power == 2, "purchased rank changes new run skill power")
		scene._toggle_tactics()
		scene.session.party[0].tactics[0].threshold = 17
		scene._toggle_tactics()
		var actor: CrawlCombatant = scene.session.party[0]
		actor.hp = actor.max_hp - 1
		scene._open_camp()
		scene._camp_action(actor.id, "heal")
		scene._close_camp()
		check(scene.flow.supplies == 5, "camp mutation autosaved")
		await boot()
		check(scene.progression.active != null, "saved run is offered on reboot")
		scene.hub_panel.resume_requested.emit()
		check(scene.current_view == "map" and scene.flow.supplies == 5 and scene.session.party[0].tactics[0].threshold == 17, "resume preserves resources and tactic changes")
		var before: Vector2i = scene.floor_state.current
		var destination := before
		for coords in scene.floor_state.discovered:
			if scene.floor_state.movement_reason(coords) == "":
				destination = coords
				break
		scene._move(destination)
		check(scene.session.combat != null and scene.session.combat.outcome == "ongoing", "room entry starts combat without a mid-turn save")
		await boot()
		scene._resume_run()
		check(scene.floor_state.current == before, "closing in combat resumes at the last pre-encounter checkpoint")
		scene._move(destination)
		for index in range(1000):
			if scene.session.result_pending: break
			scene._process(0.18)
		check(scene.current_view == "results", "completed battle enters saved result boundary")
		await boot()
		scene._resume_run()
		check(scene.current_view == "results" and scene.session.result_pending, "pending result screen restored without replaying battle")
		scene.results_panel.continue_button.pressed.emit()
		scene._acknowledge_results()
		check(scene.session.run_gold == 10, "repeated result acknowledgement cannot duplicate earned gold")
		var expected_bank: int = int(scene.progression.profile.gold) + 10
		scene._hub_or_abandon()
		check(scene.current_view == "hub" and scene.progression.active == null and scene.progression.profile.gold == expected_bank, "explicit abandon banks earned gold and returns to lodge")
		await boot()
		check(scene.progression.profile.gold == expected_bank and scene.progression.active == null, "bank and settled-run cleanup survive reboot")
		check(scene.progression.profile.presets.rogue[0].threshold == 17, "class strategy preset survives between runs")
		scene._purchase("slot", "")
		scene._purchase("slot", "")
		check(scene.hub_panel.selectors.size() == 6, "six-slot preparation remains available")
		await capture("hub_six", resolution)
		scene._generate()
		check(scene.session.party.size() == 6 and scene.flow.supplies == 6 and scene.session.run_gold == 0 and scene.flow.inventory.is_empty(), "new run retains purchases with fresh temporary resources")
		walk_to_boss()
		check(scene.current_view == "reward" and scene.flow.pending_offer.source == "boss", "persistent boss victory opens required gear reward")
		var final_bank: int = int(scene.progression.profile.gold) + scene.session.run_gold
		var completed_id: String = scene.flow.run_id
		scene.reward_panel.buttons[0].pressed.emit()
		check(scene.current_view == "end" and scene.progression.active == null and scene.progression.profile.gold == final_bank, "boss reward finishes and banks gold through the real end screen")
		check(scene.progression.profile.settled.has(completed_id) and scene.flow.inventory.is_empty(), "completed run records settlement and clears gear")
		await capture("banked", resolution)
		scene._hub_or_abandon()
		var file := FileAccess.open(directory.path_join("profile.json"), FileAccess.WRITE)
		file.store_string("corrupt primary fixture")
		file.close()
		await boot()
		check(scene.save_notice.visible and scene.save_notice.text.contains("backup"), "backup recovery is disclosed in the real hub UI")
		await capture("recovery", resolution)
	print("Persistent UI checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)


func walk_to_boss() -> void:
	var floor_state: CrawlFloorState = scene.floor_state
	var queue: Array[Vector2i] = [floor_state.current]
	var parents: Dictionary = {floor_state.current: floor_state.current}
	while not queue.is_empty():
		var coords: Vector2i = queue.pop_front()
		for door in floor_state.rooms[coords].doors:
			if door.state == DungeonEnums.DoorState.LOCKED: continue
			var target: Vector2i = door.connected_room_coords
			if not parents.has(target):
				parents[target] = coords
				queue.append(target)
	var path: Array[Vector2i] = []
	var point := floor_state.boss
	while point != floor_state.current:
		path.push_front(point)
		point = parents[point]
	for target in path:
		scene._move(target)
		for index in range(1000):
			if scene.session.result_pending: break
			scene._process(0.18)
		check(scene.session.combat.outcome == "victory", "one-creature persistence fixture wins encounter")
		scene._acknowledge_results()
