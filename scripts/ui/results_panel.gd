class_name CrawlResultsPanel
extends ScrollContainer

signal accepted
signal log_requested

var body: VBoxContainer
var continue_button: Button


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)


func bind(session: CrawlEncounterSession) -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var engine := session.combat
	var victory := engine.outcome == "victory"
	CrawlGameTheme.label(body, "VICTORY" if victory else engine.outcome.to_upper(), true)
	var downed: Array[String] = []
	for actor in engine.party:
		if not actor.alive():
			downed.append(actor.display_name)
	var text := "%d rounds · %d gold to collect\nDowned: %s" % [engine.round_index, engine.reward_gold(), "None" if downed.is_empty() else ", ".join(downed)]
	if victory:
		text += "\nChoose Continue to collect gold and return to room actions."
		text += "\nBoss spoils: choose one of three gear pieces next." if session.floor_state.current == session.floor_state.boss else "\nLoot: gold. Gear can be found in chests and boss spoils."
	else:
		text += "\nThe run ends here. No victory rewards are granted."
	CrawlGameTheme.label(CrawlGameTheme.card(body), text)
	for actor in engine.party:
		CrawlGameTheme.label(body, "%s · HP %d/%d · MP %d/%d · Potions %d" % [actor.display_name, actor.hp, actor.max_hp, actor.mp, actor.max_mp, actor.potions])
	var controls := HBoxContainer.new()
	body.add_child(controls)
	CrawlGameTheme.button(controls, "Review combat log", func() -> void: log_requested.emit())
	continue_button = CrawlGameTheme.button(controls, "Collect & continue" if victory else "Finish run", func() -> void:
		continue_button.disabled = true
		accepted.emit()
	)
