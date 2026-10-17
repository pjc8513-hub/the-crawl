extends SceneTree
## Render smoke check. Run with a rendering driver (without --headless).

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false) # Drive the same playback method with controlled frame deltas.
	await process_frame
	for resolution in [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		root.content_scale_size = resolution
		scene._generate()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		_verify(scene.map.size.x > 200 and scene.map.size.y > 200, "map has room at %s" % resolution)
		_verify(scene.details.get_global_rect().end.x <= root.get_visible_rect().size.x, "sidebar fits at %s" % resolution)
		_verify(scene.message.get_global_rect().end.y <= root.get_visible_rect().size.y, "message fits at %s" % resolution)
		_verify(root.get_texture().get_image().save_png("res://tests/preview_%dx%d.png" % [resolution.x, resolution.y]) == OK, "map screenshot saved")
		scene._toggle_tactics()
		await process_frame
		await RenderingServer.frame_post_draw
		_verify(scene.tactics_panel.list.get_combined_minimum_size().x <= scene.tactics_panel.size.x, "tactic controls fit at %s" % resolution)
		_verify(root.get_texture().get_image().save_png("res://tests/preview_tactics_%dx%d.png" % [resolution.x, resolution.y]) == OK, "tactics screenshot saved")
		scene._toggle_tactics()
		await process_frame
		# Exercise map input through its real handler; state remains authoritative.
		var current: Vector2i = scene.floor_state.current
		for coords in scene.floor_state.discovered:
			if scene.floor_state.movement_reason(coords) == "":
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = true
				event.position = scene.map.hit_boxes[coords].get_center()
				scene.map._gui_input(event)
				_verify(scene.floor_state.current == coords, "map click moves party")
				break
		_verify(scene.floor_state.current != current, "available map click handled")
		_verify(scene.session.combat != null and scene.combat_panel.visible, "room entry starts automatic combat")
		var event_count: int = scene.session.combat.events.size()
		scene.combat_panel.paused = true
		scene._process(10.0)
		_verify(scene.session.combat.events.size() == event_count, "paused playback cannot advance model")
		scene.combat_panel.paused = false
		for index in range(10):
			scene._process(0.18)
		await process_frame
		await RenderingServer.frame_post_draw
		_verify(scene.message.get_global_rect().end.y <= root.get_visible_rect().size.y, "message still fits after encounter at %s" % resolution)
		_verify(scene.combat_panel.log_view.get_global_rect().end.y <= root.get_visible_rect().size.y, "combat log fits at %s" % resolution)
		var path := "res://tests/preview_combat_%dx%d.png" % [resolution.x, resolution.y]
		var save_error := root.get_texture().get_image().save_png(path)
		_verify(save_error == OK, "screenshot saved: %s" % path)
		for index in range(10000):
			if scene.session.result_pending:
				break
			scene._process(0.18)
		_verify(scene.session.result_pending, "combat completes for result review")
		_verify(scene.floor_state.travel_block_reason != "", "results block travel")
		var gold: int = scene.session.combat.reward_gold()
		var won: bool = scene.session.combat.outcome == "victory"
		scene._acknowledge_results()
		scene._acknowledge_results()
		_verify(scene.session.run_gold == gold, "reward claim idempotent through UI")
		_verify(scene.floor_state.rooms[scene.floor_state.current].is_cleared == won, "room clears only on victory")
	var slow := _playback(scene, 1.0)
	var fast := _playback(scene, 4.0)
	_verify(slow == fast, "1x and 4x playback produce identical events")
	# Deliberately large fixture: 32 creatures must still produce four group entries.
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	scene._generate()
	for coords in scene.floor_state.discovered:
		if scene.floor_state.movement_reason(coords) == "":
			var specs: Array = []
			for filename in ["koboldfighter", "koboldwizard", "goblincleric", "goblinninja"]:
				specs.append({"enemy": load("res://data/enemies/%s.tres" % filename), "count": 8, "formation": "Back" if filename in ["koboldwizard", "goblincleric"] else "Front"})
			scene.floor_state.encounters[coords] = specs
			scene._move(coords)
			break
	_verify(scene.session.combat.actors.size() == 35 and scene.combat_panel.enemy_labels.size() == 4, "32 enemies plus party collapse to four enemy entries")
	await process_frame
	await RenderingServer.frame_post_draw
	_verify(root.get_texture().get_image().save_png("res://tests/preview_horde_1280x720.png") == OK, "horde screenshot saved")
	print("Preview smoke check: %d failures" % failures)
	quit(1 if failures else 0)


func _verify(condition: bool, label_text: String) -> void:
	if not condition:
		failures += 1
		push_error(label_text)


func _playback(scene: Node, speed: float) -> Array:
	scene._generate()
	for coords in scene.floor_state.discovered:
		if scene.floor_state.movement_reason(coords) == "":
			scene._move(coords)
			break
	scene.combat_panel.playback_speed = speed
	for index in range(50000):
		if scene.session.result_pending:
			break
		scene._process(0.05)
	_verify(scene.session.result_pending, "speed fixture terminates")
	return scene.session.combat.events.duplicate(true)
