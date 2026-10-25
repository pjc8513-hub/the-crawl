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
var skill_class_selector: OptionButton
var skill_rows: VBoxContainer
var selected_skill_class: String = ""


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
	var previous_scroll := scroll_vertical
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
				selector.add_item(CrawlContent.classes()[class_id].display_name)
				selector.set_item_metadata(selector.item_count - 1, class_id)
				if class_id == selected: selector.select(selector.item_count - 1)
			card.add_child(selector)
			selectors.append(selector)
		CrawlGameTheme.button(body, "Begin expedition with selected party", func() -> void: run_requested.emit())
	upgrades_heading = CrawlGameTheme.label(body, "PERMANENT UPGRADES · %d banked gold" % int(profile.gold), true)
	_row("Party capacity · %d / %d" % [int(profile.party_slots), controller.economy.maximum_slots], "slot", "")
	for class_id in controller.economy.class_costs:
		_row("Unlock " + CrawlContent.classes()[class_id].display_name, "class", class_id)
	CrawlGameTheme.label(body, "CLASS SKILLS", true)
	var class_picker := HBoxContainer.new()
	body.add_child(class_picker)
	CrawlGameTheme.label(class_picker, "Choose class")
	skill_class_selector = OptionButton.new()
	skill_class_selector.custom_minimum_size.x = 220
	class_picker.add_child(skill_class_selector)
	if not profile.classes.has(selected_skill_class):
		selected_skill_class = str(profile.classes[0])
	for definition in CrawlContent.CATALOG.classes:
		if not profile.classes.has(definition.id):
			continue
		skill_class_selector.add_item(definition.display_name)
		skill_class_selector.set_item_metadata(skill_class_selector.item_count - 1, definition.id)
		if definition.id == selected_skill_class:
			skill_class_selector.select(skill_class_selector.item_count - 1)
	skill_class_selector.item_selected.connect(func(index: int) -> void:
		selected_skill_class = str(skill_class_selector.get_item_metadata(index))
		_show_skill_rows()
	)
	skill_rows = VBoxContainer.new()
	skill_rows.add_theme_constant_override("separation", 8)
	body.add_child(skill_rows)
	_show_skill_rows()
	call_deferred("_restore_scroll", previous_scroll)


func _restore_scroll(value: int) -> void:
	scroll_vertical = value


func _show_skill_rows() -> void:
	for child in skill_rows.get_children():
		skill_rows.remove_child(child)
		child.queue_free()
	var class_definition: CrawlClassDefinition = CrawlContent.classes().get(selected_skill_class)
	if class_definition == null:
		return
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for upgrade in progression.economy.upgrades:
		if upgrade.kind not in ["skill", "rank"]:
			continue
		var skill_id: String = upgrade.skill.id
		var belongs := false
		if progression.economy.skill_unlocks.has(skill_id):
			belongs = progression.economy.skill_unlocks[skill_id]["class"] == selected_skill_class
		else:
			belongs = class_definition.skill_ids().has(skill_id)
		if not belongs or seen.has(skill_id):
			continue
		seen[skill_id] = true
		records.append({"id": skill_id, "name": upgrade.skill.display_name, "maxed": _skill_maxed(skill_id)})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.maxed != b.maxed:
			return not a.maxed
		return str(a.name).to_lower() < str(b.name).to_lower()
	)
	for record in records:
		var skill_id: String = record.id
		if progression.economy.skill_unlocks.has(skill_id) and not progression.profile.skills.has(skill_id):
			_row("%s · Locked" % record.name, "skill", skill_id, skill_rows)
		elif progression.economy.rank_costs.has(skill_id):
			var rank := int(progression.profile.ranks.get(skill_id, 0))
			var summary := ""
			for upgrade in progression.economy.upgrades:
				if upgrade.kind == "rank" and upgrade.skill.id == skill_id:
					summary = upgrade.rank_summary()
					break
			_row("%s · rank %d / %d · %s" % [record.name, rank, progression.economy.maximum_skill_rank, summary], "rank", skill_id, skill_rows)
		else:
			_row("%s · Unlocked" % record.name, "skill", skill_id, skill_rows)


func _skill_maxed(skill_id: String) -> bool:
	if progression.economy.skill_unlocks.has(skill_id) and not progression.profile.skills.has(skill_id):
		return false
	if progression.economy.rank_costs.has(skill_id):
		return int(progression.profile.ranks.get(skill_id, 0)) >= progression.economy.maximum_skill_rank
	return true


func _row(label_text: String, kind: String, id: String, parent: Node = null) -> void:
	var row := HBoxContainer.new()
	(parent if parent != null else body).add_child(row)
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
