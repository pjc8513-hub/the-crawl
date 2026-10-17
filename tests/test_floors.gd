extends SceneTree

var checks: int = 0
var failures: int = 0
var generator := CrawlFloorGenerator.new()
var definition := FloorDefinition.new()


func _initialize() -> void:
	for seed_value in range(100):
		var floor_state := generator.generate(definition, seed_value)
		check(generator.validate(floor_state, definition).is_empty(), "valid graph seed %d" % seed_value)
		check(floor_state.rooms.size() >= 10 and floor_state.rooms.size() <= 14, "room count seed %d" % seed_value)
		check(floor_state.layout_signature() == generator.generate(definition, seed_value).layout_signature(), "reproducible seed %d" % seed_value)
		check(floor_state.encounter_seed != floor_state.layout_seed and floor_state.encounter_seed != floor_state.loot_seed, "separate streams seed %d" % seed_value)
		check(floor_state.rooms[floor_state.start].is_explored and floor_state.map_state(floor_state.start) == "current", "start state seed %d" % seed_value)
		_exercise_floor(floor_state, seed_value)
	_test_locked_key()
	_test_switch_chain()
	_test_encounters()
	_test_fallback()
	print("Floor checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, label_text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label_text)


func _exercise_floor(floor_state: CrawlFloorState, seed_value: int) -> void:
	check(not floor_state.move_to(Vector2i(999, 999)).ok, "reject invalid movement %d" % seed_value)
	var locked_origin := Vector2i.ZERO
	var chest := Vector2i.ZERO
	for coords in floor_state.rooms:
		if floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
			chest = coords
			locked_origin = floor_state.rooms[coords].doors[0].connected_room_coords
	var key_room: Vector2i = floor_state.key_pickups.keys()[0]
	# Walk to key using actual legal movement; debug clearing is the victory integration hook.
	_walk(floor_state, key_room)
	check(floor_state.search_current_room().ok, "collect key %d" % seed_value)
	check(not floor_state.search_current_room().ok, "search once %d" % seed_value)
	_walk(floor_state, locked_origin)
	check(floor_state.map_state(chest) == "available", "key makes locked destination available %d" % seed_value)
	check(floor_state.move_to(chest).ok, "unlock entry %d" % seed_value)
	check(floor_state.door_between(chest, locked_origin).state == DungeonEnums.DoorState.OPEN and floor_state.door_between(locked_origin, chest).state == DungeonEnums.DoorState.OPEN, "symmetric unlock %d" % seed_value)
	check(floor_state.map_state(chest) == "current", "current precedence %d" % seed_value)
	floor_state.resolve_current_encounter()
	check(floor_state.move_to(locked_origin).ok, "backtrack %d" % seed_value)
	check(floor_state.map_state(chest) == "available" and floor_state.rooms[chest].is_explored, "visited and available overlap %d" % seed_value)
	var revisit := floor_state.move_to(chest)
	check(revisit.ok and not revisit.encounter_required, "no encounter replay %d" % seed_value)
	floor_state.travel_block_reason = "Pending reward."
	check(not floor_state.move_to(locked_origin).ok, "pending action blocks travel %d" % seed_value)
	floor_state.travel_block_reason = ""
	_walk(floor_state, floor_state.boss)
	check(floor_state.current == floor_state.boss, "boss reachable %d" % seed_value)


func _walk(floor_state: CrawlFloorState, destination: Vector2i) -> void:
	var queue: Array[Vector2i] = [floor_state.current]
	var parent: Dictionary = {floor_state.current: floor_state.current}
	while not queue.is_empty():
		var coords := queue.pop_front() as Vector2i
		for door in floor_state.rooms[coords].doors:
			if door.state == DungeonEnums.DoorState.LOCKED and not floor_state._can_unlock(door):
				continue
			var target: Vector2i = door.connected_room_coords
			if not parent.has(target):
				parent[target] = coords
				queue.append(target)
	if not parent.has(destination):
		check(false, "walk destination unreachable")
		return
	var path: Array[Vector2i] = []
	var step := destination
	while step != floor_state.current:
		path.push_front(step)
		step = parent[step]
	for target in path:
		floor_state.resolve_current_encounter()
		var result := floor_state.move_to(target)
		check(result.ok, "walk legal edge")
		if result.get("encounter_required", false):
			check(not floor_state.move_to(parent[target]).ok, "uncleared room blocks movement")
		floor_state.resolve_current_encounter()


func _test_locked_key() -> void:
	var floor_state := generator.generate(definition, 55)
	var chest := Vector2i.ZERO
	for coords in floor_state.rooms:
		if floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
			chest = coords
	var origin: Vector2i = floor_state.rooms[chest].doors[0].connected_room_coords
	_walk(floor_state, origin)
	check(floor_state.map_state(chest) == "blocked", "locked neighbor is red")
	check(not floor_state.move_to(chest).ok, "keyless movement rejected")
	floor_state.key_pickups.clear()
	floor_state.key_pickups[chest] = DungeonEnums.KeyType.STANDARD_KEY
	check(not generator.validate(floor_state, definition).is_empty(), "reject key behind own lock")


func _test_switch_chain() -> void:
	var floor_state := generator.generate(definition, 77)
	var key_room: Vector2i = floor_state.key_pickups.keys()[0]
	var edge_id := ""
	for room in floor_state.rooms.values():
		for door in room.doors:
			if door.state == DungeonEnums.DoorState.LOCKED:
				door.unlock_switch_id = "lever_a"
				edge_id = door.id
	var lever := RoomInteractable.new()
	lever.id = "lever_a"
	lever.type = "Switch"
	lever.target_door_id = edge_id
	floor_state.rooms[key_room].switches.append(lever)
	check(generator.validate(floor_state, definition).is_empty(), "reachable switch validates")
	check(not floor_state.activate_switch("unknown"), "unknown switch rejected")
	_walk(floor_state, key_room)
	check(floor_state.activate_switch("lever_a"), "activate local switch")
	check(not floor_state.activate_switch("lever_a"), "switch consumed once")
	for room in floor_state.rooms.values():
		for door in room.doors:
			if door.id == edge_id:
				check(door.state == DungeonEnums.DoorState.OPEN, "switch opens reciprocal edge")
	# Add another lock whose switch is behind the first: fixed-point validation must follow both.
	var chain := CrawlFloorState.new()
	for coords in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)]:
		generator._add_room(chain, coords)
	chain.boss = Vector2i(5, 0)
	chain.key_pickups[Vector2i.ZERO] = DungeonEnums.KeyType.STANDARD_KEY
	for index in range(5):
		generator._connect(chain, Vector2i(index, 0), Vector2i(index + 1, 0), index == 0 or index == 3)
	var second_lever := RoomInteractable.new()
	second_lever.id = "second"
	chain.rooms[Vector2i(2, 0)].switches.append(second_lever)
	for room in chain.rooms.values():
		for door in room.doors:
			if door.id == chain.door_between(Vector2i(3, 0), Vector2i(4, 0)).id:
				door.unlock_switch_id = "second"
	var small := FloorDefinition.new()
	small.min_rooms = 6
	small.max_rooms = 6
	check(generator.validate(chain, small).is_empty(), "multi-lock key then switch chain reachable")
	chain.rooms[Vector2i(2, 0)].switches.clear()
	chain.rooms[Vector2i(5, 0)].switches.append(second_lever)
	check(not generator.validate(chain, small).is_empty(), "reject self-locked switch chain")


func _test_encounters() -> void:
	var pool_definition := FloorDefinition.new()
	var option := EnemyGroupResource.new()
	option.enemy = load("res://data/enemies/goblinzombie.tres")
	option.min_count = 9
	option.max_count = 10
	pool_definition.standard_enemy_pool.append(option)
	var first := generator.generate(pool_definition, 121)
	var second := generator.generate(pool_definition, 121)
	var empty := generator.generate(definition, 121)
	check(first.layout_signature() == empty.layout_signature(), "encounter content does not alter layout")
	for coords in first.encounters:
		var spent := 0
		var groups: Array = first.encounters[coords]
		for index in range(groups.size()):
			var group: Dictionary = groups[index]
			spent += group.count * option.unit_budget_cost
			check(group.count >= 9 and group.count <= 10, "authored larger horde preserved")
			check(group.count == second.encounters[coords][index].count, "encounter rolls deterministic")
		check(spent <= pool_definition.encounter_budget, "encounter budget respected")
	check(option.enemy.max_group_count == 10, "definition remains immutable")


func _test_fallback() -> void:
	var fallback := generator._build(definition, -5, 0, true)
	check(generator.validate(fallback, definition).is_empty(), "known-valid fallback")
	var malformed := generator.generate(definition, 22)
	malformed.rooms[malformed.start].doors[0].direction = Vector2i.ZERO
	check(not generator.validate(malformed, definition).is_empty(), "reject corrupt edge direction")
