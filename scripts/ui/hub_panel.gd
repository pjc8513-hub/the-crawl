class_name CrawlHubPanel
extends ScrollContainer

signal purchase_requested(kind: String, id: String)
signal run_requested
signal resume_requested
signal abandon_requested

var body: VBoxContainer
var selectors: Array[OptionButton] = []
var progression: CrawlProgressionController
var upgrades_heading: Label


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)


func selections() -> Array:
	var result: Array = []
	for selector in selectors:
		if is_instance_valid(selector): result.append(selector.get_selected_metadata())
	return result


func bind(controller: CrawlProgressionController) -> void:
	var chosen := selections()
	progression = controller
	selectors.clear()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var profile := controller.profile
	CrawlGameTheme.label(body, "THE WAYFARERS' LODGE", true)
	CrawlGameTheme.label(body, "Banked gold survives the expedition. Gear and camp supplies belong to one run. Prepare your party, then enter the catacombs.")
	if controller.blocked:
		CrawlGameTheme.label(CrawlGameTheme.card(body), controller.notice)
		return
	if controller.active != null:
		var saved := controller.active
		var card := CrawlGameTheme.card(body)
		CrawlGameTheme.label(card, "SAVED EXPEDITION", true)
		CrawlGameTheme.label(card, "Seed %d · %d earned gold not yet banked\nResume the checkpoint, or explicitly bank earned gold and abandon this run." % [saved.session.floor_state.run_seed, saved.session.run_gold])
		var actions := HBoxContainer.new()
		card.add_child(actions)
		CrawlGameTheme.button(actions, "Resume saved run", func() -> void: resume_requested.emit())
		CrawlGameTheme.button(actions, "Bank & abandon", func() -> void: abandon_requested.emit())
	else:
		CrawlGameTheme.label(body, "PARTY PREPARATION · %d / %d slots" % [int(profile.party_slots), controller.economy.maximum_slots], true)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 10)
		body.add_child(grid)
		for index in range(int(profile.party_slots)):
			var card := CrawlGameTheme.card(grid)
			CrawlGameTheme.label(card, "Party slot %d" % (index + 1))
			var selector := OptionButton.new()
			selector.custom_minimum_size.x = 180
			var selected: String = chosen[index] if index < chosen.size() and profile.classes.has(chosen[index]) else profile.loadout[index]
			for class_id in profile.classes:
				selector.add_item(class_id.capitalize())
				selector.set_item_metadata(selector.item_count - 1, class_id)
				if class_id == selected: selector.select(selector.item_count - 1)
			card.add_child(selector)
			selectors.append(selector)
		CrawlGameTheme.button(body, "Begin expedition with selected party", func() -> void: run_requested.emit())
	upgrades_heading = CrawlGameTheme.label(body, "PERMANENT UPGRADES · %d banked gold" % int(profile.gold), true)
	_row("Party capacity · %d / %d" % [int(profile.party_slots), controller.economy.maximum_slots], "slot", "")
	for class_id in controller.economy.class_costs:
		_row("Unlock " + class_id.capitalize(), "class", class_id)
	var skills := CrawlCombatContent.skills()
	for skill_id in controller.economy.skill_unlocks:
		var owner: String = controller.economy.skill_unlocks[skill_id]["class"]
		_row("Unlock %s · %s" % [skills[skill_id].display_name, owner.capitalize()], "skill", skill_id)
	for skill_id in controller.economy.rank_costs:
		var rank_effect: String = "+10% effect chance per rank" if skill_id in ["sleep", "freezing_wind", "charming_potion", "earthquake"] else "+%d power per rank" % controller.economy.power_per_rank[skill_id]
		if skill_id in ["freezing_wind", "earthquake"]:
			rank_effect += ", +%d power" % controller.economy.power_per_rank[skill_id]
		_row("%s · rank %d / %d · %s" % [skills[skill_id].display_name, int(profile.ranks.get(skill_id, 0)), controller.economy.maximum_skill_rank, rank_effect], "rank", skill_id)


func _row(label_text: String, kind: String, id: String) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var label := CrawlGameTheme.label(row, label_text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost := progression.price(kind, id)
	var reason := progression.purchase_reason(kind, id)
	var owned: bool = (kind == "class" and progression.profile.classes.has(id)) or (kind == "skill" and progression.profile.skills.has(id))
	var capped: bool = (kind == "slot" and int(progression.profile.party_slots) >= progression.economy.maximum_slots) or (kind == "rank" and int(progression.profile.ranks.get(id, 0)) >= progression.economy.maximum_skill_rank)
	var caption := "Unlocked" if owned else "Maxed" if capped else "%d gold" % cost
	var button := CrawlGameTheme.button(row, caption, func() -> void: purchase_requested.emit(kind, id), reason)
	button.custom_minimum_size.x = 150
