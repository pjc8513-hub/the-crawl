class_name CrawlFloorState
extends RefCounted
## Owns newly created room resources. Authored .tres resources remain unchanged.

var run_seed: int
var generator_version: int = 1
var content_version: int = 3
var floor_depth: int = 1
var layout_seed: int
var encounter_seed: int
var loot_seed: int
var rooms: Dictionary = {}
var start: Vector2i = Vector2i.ZERO
var boss: Vector2i
var current: Vector2i = Vector2i.ZERO
var discovered: Dictionary = {}
var key_pickups: Dictionary = {} # Room coordinate -> key type.
var keys: Dictionary = {} # Reusable keyring: opening doors does not consume keys.
var switches: Dictionary = {} # Activated switch IDs.
var encounters: Dictionary = {} # Room coordinate -> rolled group dictionaries.
var interaction_consumed: Dictionary = {}
var diagnostics: Array[String] = []
var travel_block_reason: String = ""


func enter_start() -> void:
	current = start
	rooms[start].is_cleared = true
	_visit()


func _visit() -> void:
	rooms[current].is_explored = true
	discovered[current] = true
	for door in rooms[current].doors:
		discovered[door.connected_room_coords] = true


func door_between(origin: Vector2i, destination: Vector2i) -> DoorData:
	if not rooms.has(origin):
		return null
	for door in rooms[origin].doors:
		if door.connected_room_coords == destination:
			return door
	return null


func _can_unlock(door: DoorData) -> bool:
	if door.unlock_switch_id != "":
		return switches.has(door.unlock_switch_id)
	return door.required_key_type != DungeonEnums.KeyType.NONE and keys.has(door.required_key_type)


func movement_reason(destination: Vector2i) -> String:
	if travel_block_reason != "":
		return travel_block_reason
	if not rooms[current].is_cleared:
		return "Resolve this room's encounter first."
	if destination == current:
		return "Your party is here."
	if not rooms.has(destination) or not discovered.has(destination):
		return "Room has not been discovered."
	var door := door_between(current, destination)
	if door == null:
		return "No direct door from the current room."
	if door.state == DungeonEnums.DoorState.LOCKED and not _can_unlock(door):
		return "Requires switch: %s" % door.unlock_switch_id if door.unlock_switch_id != "" else "Requires a key."
	return ""


func move_to(destination: Vector2i) -> Dictionary:
	var reason := movement_reason(destination)
	if reason != "":
		return {"ok": false, "reason": reason}
	var door := door_between(current, destination)
	_set_edge_state(door.id, DungeonEnums.DoorState.OPEN)
	current = destination
	_visit()
	return {"ok": true, "encounter_required": not rooms[current].is_cleared}


func _set_edge_state(edge_id: String, state: DungeonEnums.DoorState) -> void:
	for room in rooms.values():
		for door in room.doors:
			if door.id == edge_id:
				door.state = state


func resolve_current_encounter() -> bool:
	## Integration hook: call only after a real victory (or the preview debug button).
	if rooms[current].is_cleared:
		return false
	rooms[current].is_cleared = true
	return true


func search_current_room() -> Dictionary:
	if not rooms[current].is_cleared or travel_block_reason != "":
		return {"ok": false, "reason": "Clear the room and resolve pending actions first."}
	if interaction_consumed.has(current):
		return {"ok": false, "reason": "This room was already searched."}
	interaction_consumed[current] = true
	if key_pickups.has(current):
		keys[key_pickups[current]] = true
		return {"ok": true, "reason": "Found a standard key. Locked doors can now be opened."}
	return {"ok": true, "reason": "Room searched. No key found."}


func activate_switch(switch_id: String) -> bool:
	if not rooms[current].is_cleared or travel_block_reason != "":
		return false
	for lever in rooms[current].switches:
		if lever.id == switch_id and not lever.is_triggered:
			lever.is_triggered = true
			switches[switch_id] = true
			for room in rooms.values():
				for door in room.doors:
					if door.unlock_switch_id == switch_id:
						_set_edge_state(door.id, DungeonEnums.DoorState.OPEN)
			return true
	return false


func map_state(coordinates: Vector2i) -> String:
	if not discovered.has(coordinates):
		return "hidden"
	if coordinates == current:
		return "current"
	if movement_reason(coordinates) == "":
		return "available"
	if door_between(current, coordinates) != null:
		return "blocked"
	return "explored" if rooms[coordinates].is_explored else "blocked"


func layout_signature() -> String:
	var result: Array = [run_seed, generator_version, content_version, floor_depth]
	# Insertion order is deterministic and is part of this generator version.
	for coords in rooms:
		var edges: Array = []
		for door in rooms[coords].doors:
			edges.append([door.id, door.connected_room_coords, door.state, door.required_key_type, door.unlock_switch_id])
		result.append([coords, rooms[coords].node_type, edges, key_pickups.get(coords, -1)])
	return str(result)
