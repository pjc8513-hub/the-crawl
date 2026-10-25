class_name CrawlCombatPanel
extends VBoxContainer

signal results_acknowledged

var engine: CrawlCombatEngine
var paused: bool = false
var playback_speed: float = 1.0
var heading: Label
var enemy_list: VBoxContainer
var party_list: VBoxContainer
var log_view: RichTextLabel
var pause_button: Button
var continue_button: Button
var enemy_labels: Dictionary = {}
var party_widgets: Dictionary = {}
var names: Dictionary = {}
var log_lines: Array[String] = []
var event_cursor: int = 0


func _ready() -> void:
	resized.connect(func() -> void: if engine != null: render())
	add_theme_constant_override("separation", 8)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(heading)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.pressed.connect(func() -> void:
		paused = not paused
		pause_button.text = "Resume" if paused else "Pause"
	)
	toolbar.add_child(pause_button)
	var speed := OptionButton.new()
	for label_text in ["1x speed", "2x speed", "4x speed"]:
		speed.add_item(label_text)
	speed.item_selected.connect(func(index: int) -> void: playback_speed = [1.0, 2.0, 4.0][index])
	toolbar.add_child(speed)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.pressed.connect(func() -> void: results_acknowledged.emit())
	toolbar.add_child(continue_button)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	add_child(columns)
	enemy_list = _scroll_column(columns, "ENEMY GROUPS")
	party_list = _scroll_column(columns, "PARTY")
	log_view = RichTextLabel.new()
	log_view.custom_minimum_size.y = 80
	log_view.scroll_following = true
	log_view.bbcode_enabled = false
	add_child(log_view)


func _scroll_column(parent: Control, title_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)
	var title := Label.new()
	title.text = title_text
	section.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return list


func bind(combat: CrawlCombatEngine) -> void:
	engine = combat
	paused = false
	pause_button.text = "Pause"
	event_cursor = 0
	log_lines.clear()
	enemy_labels.clear()
	party_widgets.clear()
	names.clear()
	for list in [enemy_list, party_list]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	for actor in engine.actors:
		names[actor.id] = actor.display_name
	for group in engine.groups:
		var row := HBoxContainer.new()
		enemy_list.add_child(row)
		if group.enemy_data.sprite_icon != null:
			var icon := TextureRect.new()
			icon.texture = group.enemy_data.sprite_icon
			icon.custom_minimum_size = Vector2(36, 36)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
		else:
			var icon := Label.new()
			icon.text = "◆"
			icon.add_theme_font_size_override("font_size", 28)
			row.add_child(icon)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		enemy_labels[group.id] = label
	for actor in engine.party:
		var box := VBoxContainer.new()
		party_list.add_child(box)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
		var hp := _bar(box, Color("51dc87"))
		var mp := _bar(box, Color("70b4ef"))
		party_widgets[actor.id] = {"label": label, "hp": hp, "mp": mp, "box": box}
	render()


func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 10
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func render() -> void:
	if engine == null:
		return
	heading.text = "Round %d · %s" % [engine.round_index, engine.outcome.capitalize()]
	continue_button.disabled = engine.outcome == "ongoing"
	pause_button.disabled = engine.outcome != "ongoing"
	var compact := size.y < 400
	enemy_list.add_theme_constant_override("separation", 6 if compact else 10)
	party_list.add_theme_constant_override("separation", 6 if compact else 10)
	for group in engine.groups:
		enemy_labels[group.id].add_theme_font_size_override("font_size", 14 if compact else 16)
		var hp := 0
		var statuses: Array[String] = []
		for unit in group.living_units():
			hp += unit.hp
			for status in unit.statuses:
				if not statuses.has(status):
					statuses.append(status)
		enemy_labels[group.id].text = "%s × %d / %d\n%s · %d total HP%s" % [group.enemy_data.display_name, group.current_count, group.units.size(), group.position_row, hp, " · " + ", ".join(statuses) if not statuses.is_empty() else ""]
	for actor in engine.party:
		var widgets: Dictionary = party_widgets[actor.id]
		widgets.label.add_theme_font_size_override("font_size", 13 if compact else 16)
		widgets.box.add_theme_constant_override("separation", 2 if compact else 4)
		widgets.hp.custom_minimum_size.y = 6 if compact else 10
		widgets.mp.custom_minimum_size.y = 6 if compact else 10
		var status_text := "Downed" if not actor.alive() else ", ".join(actor.statuses.keys())
		if actor.defending:
			status_text += " Defending"
		widgets.label.text = "%s · %s\nHP %d/%d · MP %d/%d · Potions %d  %s" % [actor.display_name, actor.row, actor.hp, actor.max_hp, actor.mp, actor.max_mp, actor.potions, status_text]
		widgets.hp.max_value = actor.max_hp
		widgets.hp.value = actor.hp
		widgets.mp.max_value = maxi(1, actor.max_mp)
		widgets.mp.value = actor.mp
	while event_cursor < engine.events.size():
		var event: Dictionary = engine.events[event_cursor]
		var line := _format_event(event)
		if line != "":
			log_lines.append(line)
		if log_lines.size() > 120:
			log_lines.pop_front()
		event_cursor += 1
	log_view.text = "\n".join(log_lines)
	if engine.outcome != "ongoing":
		heading.text += " · %d gold" % engine.reward_gold()


func _format_event(event: Dictionary) -> String:
	var source: String = names.get(event.get("actor", ""), event.get("actor", ""))
	var target: String = names.get(event.get("target", ""), event.get("target", ""))
	match event.type:
		"round": return "— Round %d —" % event.round
		"action": return "%s: %s → %s" % [source, engine.skills[event.skill].display_name, target]
		"damage": return "  %s takes %d damage (%d HP)." % [target, event.amount, event.hp]
		"critical": return "  Critical hit on %s! %d%% damage." % [target, event.multiplier]
		"heal": return "  %s recovers %d HP." % [target, event.amount]
		"resurrect": return "  %s returns with %d / %d HP." % [target, event.hp, event.max_hp]
		"balance": return "  %s is balanced to %d HP." % [target, event.hp]
		"defeat": return "  %s falls." % target
		"block": return "  %s blocks a hit on %s." % [source, target]
		"passive": return "  %s: %s bonus %d." % [source, event.skill.replace("_", " ").capitalize(), event.amount]
		"flee": return "  %s flees." % target
		"status": return "  %s: %s for %d turns." % [target, event.status, event.turns]
		"skip": return "%s skips a turn: %s." % [source, event.reason]
		"status_expired": return "%s: %s expires." % [target, event.status]
		"complete": return "%s. Gold earned: %d. Review results to continue." % [event.outcome.capitalize(), event.gold]
	return ""
