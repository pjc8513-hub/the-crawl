class_name CrawlRewardPanel
extends ScrollContainer

signal claim_requested(offer_id: String, index: int, recipient: String, discard_id: String)

var flow: CrawlRoomFlow
var body: VBoxContainer
var recipient: OptionButton
var discard: OptionButton
var buttons: Array[Button] = []
var comparisons: Array[Label] = []
var feedback: Label
var submitting: bool = false
var descriptions: Array[Label] = []
var item_headings: Array[Label] = []


func _ready() -> void:
	resized.connect(_density)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)


func bind(room_flow: CrawlRoomFlow) -> void:
	flow = room_flow
	submitting = false
	buttons.clear()
	comparisons.clear()
	descriptions.clear()
	item_headings.clear()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	CrawlGameTheme.label(body, "CHOOSE YOUR SPOILS", true)
	CrawlGameTheme.label(body, "Take one piece of gear. The other two are left behind. All gear belongs to this run.")
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	body.add_child(controls)
	CrawlGameTheme.label(controls, "Destination")
	recipient = OptionButton.new()
	recipient.fit_to_longest_item = false
	recipient.clip_text = true
	recipient.custom_minimum_size.x = 150
	recipient.add_item("Backpack")
	recipient.set_item_metadata(0, "")
	for actor in flow.session.party:
		recipient.add_item(actor.display_name)
		recipient.set_item_metadata(recipient.item_count - 1, actor.id)
	controls.add_child(recipient)
	CrawlGameTheme.label(controls, "Discard")
	discard = OptionButton.new()
	discard.fit_to_longest_item = false
	discard.clip_text = true
	discard.custom_minimum_size.x = 190
	discard.add_item("Keep every item")
	discard.set_item_metadata(0, "")
	for entry in flow.inventory:
		var owner := flow.actor_by_id(entry.equipped_to)
		discard.add_item(entry.item.display_name + (" · " + owner.display_name if owner != null else ""))
		discard.set_item_metadata(discard.item_count - 1, entry.id)
	controls.add_child(discard)
	discard.disabled = flow.inventory.is_empty()
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	body.add_child(cards)
	for index in range(flow.pending_offer.items.size()):
		var item: CrawlItemDefinition = flow.pending_offer.items[index]
		var card := CrawlGameTheme.card(cards)
		item_headings.append(CrawlGameTheme.label(card, item.display_name, true))
		CrawlGameTheme.label(card, item.slot.capitalize() + " · " + item.summary())
		var description := CrawlGameTheme.label(card, item.description)
		descriptions.append(description)
		card.tooltip_text = item.description
		var compare := CrawlGameTheme.label(card, "")
		compare.size_flags_vertical = Control.SIZE_EXPAND_FILL
		comparisons.append(compare)
		var choice := CrawlGameTheme.button(card, "Take this item", func() -> void:
			if submitting:
				return
			submitting = true
			for button in buttons:
				button.disabled = true
			claim_requested.emit(flow.pending_offer.id, index, recipient.get_selected_metadata(), discard.get_selected_metadata())
		)
		buttons.append(choice)
	feedback = CrawlGameTheme.label(body, "")
	recipient.item_selected.connect(func(_index: int) -> void: _refresh())
	discard.item_selected.connect(func(_index: int) -> void: _refresh())
	_refresh()
	_density()


func _refresh() -> void:
	var recipient_id: String = recipient.get_selected_metadata()
	var discard_id: String = discard.get_selected_metadata()
	var actor := flow.actor_by_id(recipient_id)
	var labels := {"attack": "Attack", "magic": "Magic", "armor": "Armor", "max_hp": "Max HP", "max_mp": "Max MP", "initiative": "Initiative"}
	for index in range(buttons.size()):
		var item: CrawlItemDefinition = flow.pending_offer.items[index]
		var text := "Store in the backpack. Equip or transfer gear at camp."
		if actor != null:
			var previous: CrawlItemDefinition = actor.equipment.get(item.slot)
			text = "Replacing: %s\n" % (previous.display_name if previous != null else "Empty slot")
			var deltas: Array[String] = []
			for stat in item.bonuses():
				var delta: int = item.bonuses()[stat] - (previous.bonuses()[stat] if previous != null else 0)
				if delta != 0:
					deltas.append("%+d %s" % [delta, labels[stat]])
			text += " · ".join(deltas) + "\n"
			var removed := flow.item_instance(discard_id)
			var discarding_previous: bool = previous != null and not removed.is_empty() and removed.equipped_to == recipient_id and removed.item.slot == item.slot
			text += "Old gear will be discarded." if discarding_previous else "Old gear moves to the pack." if previous != null else "Equip directly."
		comparisons[index].text = text
		var reason := flow.claim_reason(flow.pending_offer.id, index, recipient_id, discard_id)
		buttons[index].disabled = submitting or reason != ""
		buttons[index].tooltip_text = reason
	feedback.text = "Gear: %d/%d slots used (equipped + backpack). %s" % [flow.inventory.size(), CrawlRoomFlow.GEAR_CAPACITY, "Inventory full: choose an item to discard." if flow.inventory.size() >= CrawlRoomFlow.GEAR_CAPACITY and discard_id == "" else ""]


func _density() -> void:
	var compact := size.y < 450
	for index in range(descriptions.size()):
		descriptions[index].visible = not compact
		item_headings[index].add_theme_font_size_override("font_size", 18 if compact else 22)
