class_name CrawlDungeonMap
extends Control

signal room_clicked(coordinates: Vector2i)

const COLORS: Dictionary = {
	"current": Color("51dc87"), "available": Color("f3d85b"),
	"blocked": Color("ed6579"), "explored": Color("80cce2")
}
var floor_state: CrawlFloorState
var hit_boxes: Dictionary = {}
var selected_room: Vector2i = Vector2i.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


func _draw() -> void:
	hit_boxes.clear()
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	if floor_state == null or floor_state.rooms.is_empty():
		return
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	for coords in floor_state.discovered:
		low = low.min(coords)
		high = high.max(coords)
	var extent := Vector2(high - low + Vector2i.ONE)
	var step := minf((size.x - 40.0) / extent.x, (size.y - 40.0) / extent.y)
	step = minf(step, 108.0)
	var tile := step * 0.76
	var origin := (size - extent * step) * 0.5
	for coords in floor_state.discovered:
		var center := origin + (Vector2(coords - low) + Vector2.ONE * 0.5) * step
		for door in floor_state.rooms[coords].doors:
			if floor_state.discovered.has(door.connected_room_coords):
				var other := origin + (Vector2(door.connected_room_coords - low) + Vector2.ONE * 0.5) * step
				var color := Color("ed6579") if door.state == DungeonEnums.DoorState.LOCKED else Color("405067")
				draw_line(center, other, color, 3.0)
	for coords in floor_state.discovered:
		var center := origin + (Vector2(coords - low) + Vector2.ONE * 0.5) * step
		var rect := Rect2(center - Vector2.ONE * tile * 0.5, Vector2.ONE * tile)
		hit_boxes[coords] = rect
		var state := floor_state.map_state(coords)
		var color: Color = COLORS[state]
		draw_rect(rect, Color("142034"))
		draw_rect(rect, color, false, 3.0)
		if has_focus() and coords == selected_room:
			draw_rect(rect.grow(4), Color.WHITE, false, 1.0)
		var label_text := "?"
		if floor_state.rooms[coords].is_explored:
			label_text = "BOSS" if coords == floor_state.boss else "CHEST" if floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM else "ROOM"
		if coords == floor_state.current:
			label_text = "PARTY"
		var font := get_theme_default_font()
		var font_size := clampi(int(tile / 5.0), 10, 16)
		var width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, center + Vector2(-width / 2.0, 5.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		if floor_state.rooms[coords].is_explored:
			draw_circle(rect.position + Vector2(9, 9), 3, Color("80cce2"))
		var badge: String = {"current": "@", "available": "+", "blocked": "!", "explored": "·"}[state]
		draw_string(font, rect.position + Vector2(tile - 14, 14), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b1322")
	style.set_corner_radius_all(10)
	return style


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for coords in hit_boxes:
			if hit_boxes[coords].has_point(event.position):
				selected_room = coords
				grab_focus()
				room_clicked.emit(coords)
				accept_event()
				return
	if event is InputEventKey and event.pressed and floor_state != null:
		var direction := Vector2i.ZERO
		if event.is_action_pressed("ui_left"): direction = Vector2i.LEFT
		elif event.is_action_pressed("ui_right"): direction = Vector2i.RIGHT
		elif event.is_action_pressed("ui_up"): direction = Vector2i.UP
		elif event.is_action_pressed("ui_down"): direction = Vector2i.DOWN
		elif event.is_action_pressed("ui_accept"):
			room_clicked.emit(selected_room)
			accept_event()
		if direction != Vector2i.ZERO:
			if floor_state.discovered.has(selected_room + direction):
				selected_room += direction
			queue_redraw()
			accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	for coords in hit_boxes:
		if hit_boxes[coords].has_point(at_position):
			var reason := floor_state.movement_reason(coords)
			return "Travel to %s" % coords if reason == "" else reason
	return ""
