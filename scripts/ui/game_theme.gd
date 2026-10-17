class_name CrawlGameTheme
extends RefCounted

const INK := Color("e5e9ef")
const MUTED := Color("a3b2c5")
const GOLD := Color("e4c779")


static func panel(color: Color = Color("121f31")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("2b3e56")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(12)
	return style


static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color("718096"))
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, panel())
		theme.set_stylebox("hover", type_name, panel(Color("20334c")))
		theme.set_stylebox("pressed", type_name, panel(Color("304967")))
		theme.set_stylebox("disabled", type_name, panel(Color("0e1827")))
		var focus := panel(Color(0, 0, 0, 0))
		focus.border_color = GOLD
		theme.set_stylebox("focus", type_name, focus)
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("normal", "LineEdit", panel(Color("0b1524")))
	var bar_background := panel(Color("0a1220"))
	bar_background.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", bar_background)
	return theme


static func label(parent: Node, text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HBoxContainer else TextServer.AUTOWRAP_WORD_SMART
	if heading:
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", GOLD)
	parent.add_child(label)
	return label


static func button(parent: Node, text: String, action: Callable, reason: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = reason != ""
	button.tooltip_text = reason
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func card(parent: Node) -> VBoxContainer:
	var panel_node := PanelContainer.new()
	panel_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent is HBoxContainer:
		panel_node.custom_minimum_size.x = 200
	parent.add_child(panel_node)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel_node.add_child(column)
	return column
