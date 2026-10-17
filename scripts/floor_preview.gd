extends Node2D
## Run-screen coordinator. Models validate combat, rewards and room actions.

var floor_state: CrawlFloorState
var generator := CrawlFloorGenerator.new()
var definition := FloorDefinition.new()
var map: CrawlDungeonMap
var seed_input: LineEdit
var details: Label
var message: Label
var search_button: Button
var session: CrawlEncounterSession
var combat_panel: CrawlCombatPanel
var tactics_panel: CrawlTacticsPanel
var tactics_button: Button
var exploration_content: HBoxContainer
var combat_clock: float = 0.0
var legend: Label
var flow: CrawlRoomFlow
var results_panel: CrawlResultsPanel
var reward_panel: CrawlRewardPanel
var camp_panel: CrawlCampPanel
var end_panel: ScrollContainer
var end_body: VBoxContainer
var camp_button: Button
var chest_button: Button
var switch_buttons: VBoxContainer
var resource_header: Label
var title: Label
var current_view: String = "map"


func _ready() -> void:
	get_window().min_size = Vector2i(960, 600)
	$World/ExplorationContainer.hide()
	$World/CombatContainer.hide()
	$HudLayer/HudRoot/CanvasLayer/ScreenFilter.hide()
	_build_ui()
	# Validate every authored enemy before it can enter the encounter pool.
	for filename in ["koboldfighter", "koboldskeleton", "koboldknight", "koboldwizard", "goblincleric", "goblinninja", "goblinzombie"]:
		var enemy: EnemyResource = load("res://data/enemies/%s.tres" % filename)
		var errors := CrawlEnemyValidation.errors(enemy)
		if not errors.is_empty():
			push_error("\n".join(errors))
			continue
		var option := EnemyGroupResource.new()
		option.enemy = enemy
		option.min_count = enemy.min_group_count
		option.max_count = enemy.max_group_count
		option.formation = "Back" if enemy.subtype_class in ["Wizard", "Cleric"] else "Middle" if enemy.subtype_class == "Ninja" else "Front"
		definition.standard_enemy_pool.append(option)
	_generate()


func _process(delta: float) -> void:
	if session == null or session.combat == null or session.result_pending or session.combat.outcome != "ongoing" or combat_panel.paused:
		return
	combat_clock += delta * combat_panel.playback_speed
	var steps := 0
	while combat_clock >= 0.18 and not session.result_pending and steps < 32:
		combat_clock -= 0.18
		session.advance()
		steps += 1
	if steps > 0:
		combat_panel.render()
		if session.result_pending:
			_show_results()
			_refresh()
		_refresh_header()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color("080e19")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var margin := MarginContainer.new()
	margin.theme = CrawlGameTheme.make()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layer.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	title = Label.new()
	title.text = "CRAWL  /  THE CATACOMBS"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	resource_header = Label.new()
	resource_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	resource_header.add_theme_color_override("font_color", CrawlGameTheme.GOLD)
	column.add_child(resource_header)
	var seed_row := HBoxContainer.new()
	column.add_child(seed_row)
	seed_input = LineEdit.new()
	seed_input.text = "1042"
	seed_input.placeholder_text = "Integer seed"
	seed_input.custom_minimum_size.x = 180
	seed_row.add_child(seed_input)
	var generate_button := Button.new()
	generate_button.text = "New run"
	generate_button.pressed.connect(_generate)
	seed_row.add_child(generate_button)
	tactics_button = Button.new()
	tactics_button.text = "Party tactics"
	tactics_button.pressed.connect(_toggle_tactics)
	seed_row.add_child(tactics_button)
	seed_input.text_submitted.connect(func(_text: String) -> void: _generate())
	legend = Label.new()
	legend.text = "GREEN: party    YELLOW: available    RED: blocked    BLUE: explored    • visited marker"
	legend.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(legend)
	var content := HBoxContainer.new()
	exploration_content = content
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	column.add_child(content)
	map = CrawlDungeonMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.room_clicked.connect(_move)
	content.add_child(map)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 260
	content.add_child(sidebar)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(detail_scroll)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(details)
	search_button = Button.new()
	search_button.text = "Search room"
	search_button.pressed.connect(_search)
	sidebar.add_child(search_button)
	chest_button = CrawlGameTheme.button(sidebar, "Open chest", _open_chest)
	camp_button = CrawlGameTheme.button(sidebar, "Camp & equipment", _open_camp)
	switch_buttons = VBoxContainer.new()
	sidebar.add_child(switch_buttons)
	combat_panel = CrawlCombatPanel.new()
	combat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	combat_panel.results_acknowledged.connect(_show_results)
	column.add_child(combat_panel)
	combat_panel.hide()
	tactics_panel = CrawlTacticsPanel.new()
	tactics_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tactics_panel)
	tactics_panel.hide()
	results_panel = CrawlResultsPanel.new()
	results_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_panel.accepted.connect(_acknowledge_results)
	results_panel.log_requested.connect(func() -> void: _show_view("combat"))
	column.add_child(results_panel)
	results_panel.hide()
	reward_panel = CrawlRewardPanel.new()
	reward_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reward_panel.claim_requested.connect(_claim_reward)
	column.add_child(reward_panel)
	reward_panel.hide()
	camp_panel = CrawlCampPanel.new()
	camp_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camp_panel.returned.connect(_close_camp)
	camp_panel.action_requested.connect(_camp_action)
	camp_panel.equip_requested.connect(_equip_item)
	column.add_child(camp_panel)
	camp_panel.hide()
	end_panel = ScrollContainer.new()
	end_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	end_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	end_body = VBoxContainer.new()
	end_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_body.add_theme_constant_override("separation", 12)
	end_panel.add_child(end_body)
	column.add_child(end_panel)
	end_panel.hide()
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 42
	column.add_child(message)


func _generate() -> void:
	if not seed_input.text.is_valid_int():
		message.text = "Enter an integer seed."
		return
	floor_state = generator.generate(definition, seed_input.text.to_int())
	session = CrawlEncounterSession.new()
	session.floor_state = floor_state
	session.party = CrawlCombatContent.party()
	flow = CrawlRoomFlow.new()
	flow.session = session
	combat_clock = 0.0
	tactics_panel.bind(session.party)
	_show_view("map")
	map.floor_state = floor_state
	map.selected_room = floor_state.current
	message.text = "Choose an available room. Search for a key, claim chest gear, and use camp supplies between battles."
	_refresh()


func _move(coords: Vector2i) -> void:
	var result := floor_state.move_to(coords)
	if not result.ok:
		message.text = result.reason
	elif result.get("encounter_required", false):
		if session.begin():
			combat_clock = 0.0
			_show_view("combat")
			combat_panel.bind(session.combat)
			message.text = "Combat is automatic. Pause to inspect, or change playback speed."
		else:
			message.text = session.error_message
	else:
		message.text = "Travel complete. Cleared rooms do not repeat encounters."
	map.selected_room = floor_state.current
	_refresh()


func _acknowledge_results() -> void:
	var result := session.acknowledge()
	if not result.ok:
		return
	flow.after_combat(result)
	if flow.phase == "reward":
		reward_panel.bind(flow)
		_show_view("reward")
		message.text = "The guardian is defeated. Choose one piece of gear to complete the run."
	elif flow.phase == "ended":
		_show_end()
	else:
		_show_view("map")
		message.text = "Collected %d gold. Search, open camp, or choose your next room." % result.gold
	_refresh()


func _toggle_tactics() -> void:
	if tactics_button.disabled:
		return
	_show_view("map" if current_view == "tactics" else "tactics")
	if current_view == "tactics":
		tactics_panel.bind(session.party)
	message.text = "Edit rule thresholds, targets, reserves and priority order. Changes apply to this run."


func _search() -> void:
	message.text = flow.search().reason
	_refresh()


func _refresh() -> void:
	var room: DungeonRoomData = floor_state.rooms[floor_state.current]
	var visited := 0
	for known_room in floor_state.rooms.values():
		if known_room.is_explored:
			visited += 1
	var text := "THE CATACOMBS · FLOOR %d\n%d / %d rooms explored\n\n%s\nKeyring: %s\n" % [floor_state.floor_depth, visited, floor_state.rooms.size(), "Room secured" if room.is_cleared else "Encounter unresolved", "Standard key" if not floor_state.keys.is_empty() else "Empty"]
	if floor_state.current == floor_state.boss:
		text += "\nBOSS ROOM\n"
	elif room.node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
		text += "\nA sealed chest awaits.\n"
	for actor in session.party:
		text += "\n%s: HP %d/%d · MP %d/%d\nPotions: %d" % [actor.display_name, actor.hp, actor.max_hp, actor.mp, actor.max_mp, actor.potions]
	details.text = text
	var reason := flow.room_reason()
	search_button.disabled = reason != "" or floor_state.interaction_consumed.has(floor_state.current)
	search_button.tooltip_text = reason if reason != "" else "Already searched." if floor_state.interaction_consumed.has(floor_state.current) else "Search once for a key."
	camp_button.disabled = reason != ""
	camp_button.tooltip_text = reason
	chest_button.visible = room.node_type == DungeonEnums.RoomNodeType.CHEST_ROOM or not room.chests.is_empty()
	chest_button.disabled = flow.chest_reason() != ""
	chest_button.tooltip_text = flow.chest_reason()
	chest_button.text = "Chest claimed" if flow.claimed_offers.has(flow._offer_id("chest")) else "Open chest"
	for child in switch_buttons.get_children():
		switch_buttons.remove_child(child)
		child.queue_free()
	for lever in room.switches:
		CrawlGameTheme.button(switch_buttons, "Use " + lever.name, func() -> void:
			message.text = "Switch activated." if flow.activate_switch(lever.id) else "Switch cannot be used."
			_refresh()
		, "Already activated." if lever.is_triggered else reason)
	_refresh_header()
	map.queue_redraw()


func _refresh_header() -> void:
	var standing := 0
	for actor in session.party:
		standing += 1 if actor.alive() else 0
	resource_header.text = "GOLD %d   ·   SUPPLIES %d   ·   GEAR %d/%d   ·   PARTY %d/%d standing" % [session.run_gold, flow.supplies, flow.inventory.size(), CrawlRoomFlow.GEAR_CAPACITY, standing, session.party.size()]


func _show_view(view: String) -> void:
	current_view = view
	var panels := {"map": exploration_content, "combat": combat_panel, "tactics": tactics_panel, "results": results_panel, "reward": reward_panel, "camp": camp_panel, "end": end_panel}
	for name_key in panels:
		panels[name_key].visible = view == name_key
	legend.visible = view == "map"
	title.text = "CRAWL  /  " + {"map": "THE CATACOMBS", "combat": "BATTLE", "tactics": "PARTY TACTICS", "results": "AFTERMATH", "reward": "SPOILS", "camp": "CAMP", "end": "RUN COMPLETE"}.get(view, "THE CATACOMBS")
	tactics_button.text = "Back to dungeon" if view == "tactics" else "Party tactics"
	tactics_button.disabled = view not in ["map", "tactics"] or flow.room_reason() != ""


func _show_results() -> void:
	if not session.result_pending:
		return
	results_panel.bind(session)
	_show_view("results")
	message.text = "Review the outcome. Rewards and travel stay locked until you continue."


func _open_chest() -> void:
	if not flow.open_chest():
		message.text = flow.chest_reason()
		return
	reward_panel.bind(flow)
	_show_view("reward")
	message.text = "Choose one item and its destination. Compare it with the equipped slot before claiming."
	_refresh()


func _claim_reward(offer_id: String, index: int, recipient: String, discard_id: String) -> void:
	var result := flow.claim(offer_id, index, recipient, discard_id)
	message.text = result.reason
	if result.ok:
		if flow.phase == "ended":
			_show_end()
		else:
			_show_view("map")
	else:
		if flow.phase == "reward":
			reward_panel.bind(flow)
	_refresh()


func _open_camp() -> void:
	if not flow.open_camp():
		message.text = flow.room_reason()
		return
	camp_panel.bind(flow)
	_show_view("camp")
	message.text = "Camp supplies are limited for this run. Hover a disabled action to see why."
	_refresh()


func _close_camp() -> void:
	if flow.close_camp():
		_show_view("map")
		message.text = "Camp packed. Your party remains in the same room."
		_refresh()


func _camp_action(actor_id: String, action: String) -> void:
	var result := flow.camp_action(actor_id, action)
	message.text = result.reason
	camp_panel.bind(flow)
	_refresh()


func _equip_item(item_id: String, recipient: String) -> void:
	message.text = "Equipment updated. Replaced gear remains in your pack." if flow.equip(item_id, recipient) else "Equipment can only be changed at camp."
	camp_panel.bind(flow)
	_refresh()


func _show_end() -> void:
	for child in end_body.get_children():
		end_body.remove_child(child)
		child.queue_free()
	CrawlGameTheme.label(end_body, "FLOOR CLEARED" if flow.end_outcome == "victory" else "YOUR EXPEDITION ENDS", true)
	CrawlGameTheme.label(CrawlGameTheme.card(end_body), "Gold earned: %d\nFinal gear: %s\n\nThis run's gear and supplies have been cleared." % [session.run_gold, ", ".join(flow.final_loadout) if not flow.final_loadout.is_empty() else "None"])
	CrawlGameTheme.button(end_body, "Begin a new run", _generate)
	_show_view("end")
	message.text = "The expedition is complete." if flow.end_outcome == "victory" else "Regroup and try another route or tactic."
	_refresh()
