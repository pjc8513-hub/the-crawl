class_name CrawlCampPanel
extends ScrollContainer

signal returned
signal action_requested(actor_id: String, action: String)
signal equip_requested(item_id: String, recipient: String)

var body: VBoxContainer
var flow: CrawlRoomFlow
var action_buttons: Array[Button] = []


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	add_child(body)


func bind(room_flow: CrawlRoomFlow) -> void:
	flow = room_flow
	action_buttons.clear()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var toolbar := HBoxContainer.new()
	body.add_child(toolbar)
	var heading := CrawlGameTheme.label(toolbar, "CAMP · %d supplies" % flow.supplies, true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CrawlGameTheme.button(toolbar, "Return to room", func() -> void: returned.emit())
	CrawlGameTheme.label(body, "Treat a party member, restore mana, or change equipment. Returning keeps your current room and floor.")
	for actor in flow.session.party:
		var card := CrawlGameTheme.card(body)
		CrawlGameTheme.label(card, "%s · HP %d/%d · MP %d/%d%s" % [actor.display_name, actor.hp, actor.max_hp, actor.mp, actor.max_mp, " · Downed" if not actor.alive() else ""])
		var actions := HBoxContainer.new()
		card.add_child(actions)
		for spec in [["heal", "Heal 40 HP · 1 supply"], ["restore_mp", "Restore 15 MP · 1 supply"], ["revive", "Revive · 2 supplies"]]:
			var button := CrawlGameTheme.button(actions, spec[1], func() -> void:
				action_requested.emit(actor.id, spec[0])
			, flow.camp_reason(actor.id, spec[0]))
			action_buttons.append(button)
	CrawlGameTheme.label(body, "EQUIPMENT · %d/%d slots" % [flow.inventory.size(), CrawlRoomFlow.GEAR_CAPACITY], true)
	if flow.inventory.is_empty():
		CrawlGameTheme.label(body, "No gear yet. Find a chest or defeat the floor boss.")
	for entry in flow.inventory:
		var row := HBoxContainer.new()
		body.add_child(row)
		var label := CrawlGameTheme.label(row, "%s · %s\n%s" % [entry.item.display_name, entry.item.slot.capitalize(), entry.item.summary()])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var recipient := OptionButton.new()
		recipient.fit_to_longest_item = false
		recipient.clip_text = true
		recipient.custom_minimum_size.x = 150
		recipient.add_item("Backpack")
		recipient.set_item_metadata(0, "")
		for actor in flow.session.party:
			recipient.add_item(actor.display_name)
			recipient.set_item_metadata(recipient.item_count - 1, actor.id)
			if entry.equipped_to == actor.id:
				recipient.select(recipient.item_count - 1)
		row.add_child(recipient)
		CrawlGameTheme.button(row, "Assign", func() -> void: equip_requested.emit(entry.id, recipient.get_selected_metadata()))
