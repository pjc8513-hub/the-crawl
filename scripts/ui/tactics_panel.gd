class_name CrawlTacticsPanel
extends ScrollContainer

var party: Array[CrawlCombatant] = []
var list: VBoxContainer
var preview: CrawlCombatEngine
var serial: int = 0


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	add_child(list)


func bind(members: Array[CrawlCombatant]) -> void:
	party = members
	var enemies: Array[EnemyGroup] = []
	for filename in ["koboldfighter", "koboldwizard"]:
		var group := EnemyGroup.new()
		group.initialize_group(load("res://data/enemies/%s.tres" % filename), 4, null, "preview:" + filename)
		enemies.append(group)
	preview = CrawlCombatEngine.new()
	preview.configure(party, enemies, 0)
	rebuild()


func rebuild() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	CrawlGameTheme.label(list, "The first usable rule wins. Below and above are strict comparisons.\nAvailability preview: front fighters and backline mages, using your current party HP, MP and supplies.")
	for actor in party:
		var header := HBoxContainer.new()
		list.add_child(header)
		var name_label := CrawlGameTheme.label(header, actor.display_name, true)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		CrawlGameTheme.button(header, "Add rule", func() -> void:
			serial += 1
			actor.tactics.append(CrawlCombatContent.rule("custom:%s:%d" % [actor.id, serial], "always", 0, "attack", "lowest_hp"))
			call_deferred("rebuild")
		)
		for index in range(actor.tactics.size()):
			_build_rule(actor, index)


func _build_rule(actor: CrawlCombatant, index: int) -> void:
	var rule := actor.tactics[index]
	var block := CrawlGameTheme.card(list)
	var row := HBoxContainer.new()
	block.add_child(row)
	var enabled := CheckBox.new()
	enabled.button_pressed = rule.enabled
	enabled.text = "%d." % [index + 1]
	row.add_child(enabled)
	var action := _options(row, actor.known_skills, rule.skill_id)
	action.custom_minimum_size.x = 180
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for direction in [-1, 1]:
		var button := CrawlGameTheme.button(row, "↑" if direction < 0 else "↓", func() -> void:
			var other: int = index + int(direction)
			actor.tactics[index] = actor.tactics[other]
			actor.tactics[other] = rule
			call_deferred("rebuild")
		, "Already at the end of the priority list." if index + direction < 0 or index + direction >= actor.tactics.size() else "")
		button.tooltip_text = "Move rule up" if direction < 0 else "Move rule down"
	CrawlGameTheme.button(row, "Remove", func() -> void:
		actor.tactics.erase(rule)
		call_deferred("rebuild")
	)
	var condition_row := HBoxContainer.new()
	block.add_child(condition_row)
	var metric := _options(condition_row, ["always", "self_hp_percent", "self_hp", "lowest_ally_hp_percent", "lowest_ally_hp", "self_mp_percent", "enemy_group_count"], rule.metric)
	var comparator := _options(condition_row, ["below", "above", "at_most", "at_least"], rule.comparator)
	var threshold := _number(condition_row, rule.threshold, 0, 9999)
	var units := CrawlGameTheme.label(condition_row, "")
	var targeting := HBoxContainer.new()
	block.add_child(targeting)
	CrawlGameTheme.label(targeting, "Target")
	var selector := _options(targeting, ["self", "lowest_hp", "highest_hp", "lowest_hp_percent", "backline", "highest_count"], rule.selector)
	CrawlGameTheme.label(targeting, "MP reserve")
	var reserve := _number(targeting, rule.reserve_mp, 0, 999)
	CrawlGameTheme.label(targeting, "Min group")
	var count := _number(targeting, rule.min_group_count, 0, 100)
	var diagnostic := CrawlGameTheme.label(block, "")
	diagnostic.add_theme_color_override("font_color", CrawlGameTheme.MUTED)
	var refresh := func() -> void:
		units.text = "%" if rule.metric.ends_with("percent") else "HP" if rule.metric in ["self_hp", "lowest_ally_hp"] else "creatures" if rule.metric == "enemy_group_count" else ""
		comparator.disabled = rule.metric == "always"
		threshold.editable = rule.metric != "always"
		var inspection := preview.inspect_rule(actor, rule)
		diagnostic.text = "Ready in this preview; earlier rules may take priority." if inspection.reason == "" else inspection.reason
	enabled.toggled.connect(func(value: bool) -> void:
		rule.enabled = value
		refresh.call()
	)
	action.item_selected.connect(func(selected: int) -> void:
		rule.skill_id = action.get_item_metadata(selected)
		refresh.call()
	)
	metric.item_selected.connect(func(selected: int) -> void:
		rule.metric = metric.get_item_metadata(selected)
		refresh.call()
	)
	comparator.item_selected.connect(func(selected: int) -> void:
		rule.comparator = comparator.get_item_metadata(selected)
		refresh.call()
	)
	threshold.value_changed.connect(func(value: float) -> void:
		rule.threshold = value
		refresh.call()
	)
	selector.item_selected.connect(func(selected: int) -> void:
		rule.selector = selector.get_item_metadata(selected)
		refresh.call()
	)
	reserve.value_changed.connect(func(value: float) -> void:
		rule.reserve_mp = int(value)
		refresh.call()
	)
	count.value_changed.connect(func(value: float) -> void:
		rule.min_group_count = int(value)
		refresh.call()
	)
	refresh.call()


func _options(parent: Control, values: Array, selected: String) -> OptionButton:
	var control := OptionButton.new()
	var labels := {"always": "Always", "self_hp_percent": "Self HP (%)", "self_hp": "Self HP (value)", "lowest_ally_hp_percent": "Lowest ally HP (%)", "lowest_ally_hp": "Lowest ally HP (value)", "self_mp_percent": "Self MP (%)", "enemy_group_count": "Enemy group count", "lowest_hp": "Lowest HP", "highest_hp": "Highest HP", "lowest_hp_percent": "Lowest HP (%)", "at_most": "At most", "at_least": "At least"}
	var skills := CrawlCombatContent.skills()
	for value in values:
		control.add_item(skills[value].display_name if skills.has(value) else labels.get(value, value.replace("_", " ").capitalize()))
		control.set_item_metadata(control.item_count - 1, value)
		if value == selected:
			control.select(control.item_count - 1)
	parent.add_child(control)
	return control


func _number(parent: Control, value: float, low: float, high: float) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = low
	control.max_value = high
	control.value = value
	parent.add_child(control)
	return control
