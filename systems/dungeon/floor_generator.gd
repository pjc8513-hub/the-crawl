class_name CrawlFloorGenerator
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const VERSION: int = 1


func generate(definition: FloorDefinition, seed_value: int) -> CrawlFloorState:
	var failures: Array[String] = []
	for attempt in range(clampi(definition.generation_attempts, 1, 32)):
		var floor_state := _build(definition, seed_value, attempt, false)
		var errors := validate(floor_state, definition)
		if errors.is_empty():
			floor_state.diagnostics = failures
			_populate_encounters(floor_state, definition)
			floor_state.enter_start()
			return floor_state
		failures.append("Seed %d / generator %d / attempt %d: %s" % [seed_value, VERSION, attempt, str(errors)])
	var fallback := _build(definition, seed_value, 0, true)
	fallback.diagnostics = failures
	fallback.diagnostics.append("Used known-valid linear fallback for seed %d." % seed_value)
	_populate_encounters(fallback, definition)
	fallback.enter_start()
	return fallback


func _stream_seed(seed_value: int, depth: int, stream: String, attempt: int = 0) -> int:
	return ("crawl:%d:%d:%d:%s:%d" % [VERSION, seed_value, depth, stream, attempt]).hash()


func _build(definition: FloorDefinition, seed_value: int, attempt: int, linear: bool) -> CrawlFloorState:
	var floor_state := CrawlFloorState.new()
	floor_state.run_seed = seed_value
	floor_state.generator_version = VERSION
	floor_state.floor_depth = definition.floor_depth
	floor_state.layout_seed = _stream_seed(seed_value, definition.floor_depth, "layout", attempt)
	floor_state.encounter_seed = _stream_seed(seed_value, definition.floor_depth, "encounters")
	floor_state.loot_seed = _stream_seed(seed_value, definition.floor_depth, "loot")
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_state.layout_seed
	var low := clampi(definition.min_rooms, 6, 64)
	var count := rng.randi_range(low, clampi(definition.max_rooms, low, 64))
	var spine_count := clampi(definition.spine_rooms, 3, count - 2)
	_add_room(floor_state, Vector2i.ZERO)
	var tip := Vector2i.ZERO
	for index in range(1, spine_count):
		var candidates := _free_neighbors(floor_state, tip)
		if candidates.is_empty():
			return floor_state # Validator rejects incomplete spine; bounded retry follows.
		var next: Vector2i = tip + Vector2i.RIGHT if linear else candidates[rng.randi_range(0, candidates.size() - 1)]
		_add_room(floor_state, next)
		_connect(floor_state, tip, next)
		tip = next
	floor_state.boss = tip
	floor_state.rooms[tip].node_type = DungeonEnums.RoomNodeType.BOSS
	floor_state.rooms[tip].is_boss_room = true
	while floor_state.rooms.size() < count - 1:
		var origins: Array = []
		for coords in floor_state.rooms:
			if coords != floor_state.boss and not _free_neighbors(floor_state, coords).is_empty():
				origins.append(coords)
		var origin: Vector2i = origins[0] if linear else origins[rng.randi_range(0, origins.size() - 1)]
		var candidates := _free_neighbors(floor_state, origin)
		var next: Vector2i = candidates[0] if linear else candidates[rng.randi_range(0, candidates.size() - 1)]
		_add_room(floor_state, next)
		_connect(floor_state, origin, next)
	if not linear:
		for coords in floor_state.rooms:
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: Vector2i = coords + direction
				if floor_state.rooms.has(neighbor) and floor_state.door_between(coords, neighbor) == null and rng.randf() < definition.loop_chance:
					_connect(floor_state, coords, neighbor)
	# Add a gated leaf last, so loops cannot accidentally bypass its lock.
	var leaf_origins: Array = []
	for coords in floor_state.rooms:
		if coords != floor_state.boss and not _free_neighbors(floor_state, coords).is_empty():
			leaf_origins.append(coords)
	var leaf_origin: Vector2i = leaf_origins[0] if linear else leaf_origins[rng.randi_range(0, leaf_origins.size() - 1)]
	var free := _free_neighbors(floor_state, leaf_origin)
	var chest: Vector2i = free[0]
	_add_room(floor_state, chest)
	floor_state.rooms[chest].node_type = DungeonEnums.RoomNodeType.CHEST_ROOM
	floor_state.rooms[chest].is_cleared = true
	var chest_interactable := RoomInteractable.new()
	chest_interactable.id = "chest:%d:%s" % [definition.floor_depth, chest]
	chest_interactable.name = "Sealed Chest"
	chest_interactable.chest_loot_table_id = "starter_gear"
	floor_state.rooms[chest].chests.append(chest_interactable)
	_connect(floor_state, leaf_origin, chest, true)
	var key_rooms: Array = []
	for coords in floor_state.rooms:
		if coords != chest and coords != floor_state.boss:
			key_rooms.append(coords)
	floor_state.key_pickups[key_rooms[rng.randi_range(0, key_rooms.size() - 1)]] = DungeonEnums.KeyType.STANDARD_KEY
	return floor_state


func _add_room(floor_state: CrawlFloorState, coords: Vector2i) -> void:
	var room := DungeonRoomData.new()
	room.coordinates = coords
	floor_state.rooms[coords] = room


func _free_neighbors(floor_state: CrawlFloorState, coords: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		if not floor_state.rooms.has(coords + direction):
			result.append(coords + direction)
	return result


func _connect(floor_state: CrawlFloorState, a: Vector2i, b: Vector2i, locked: bool = false) -> void:
	var edge_id := "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]
	for endpoints in [[a, b], [b, a]]:
		var door := DoorData.new()
		var origin: Vector2i = endpoints[0]
		var destination: Vector2i = endpoints[1]
		door.id = edge_id
		door.direction = destination - origin
		door.connected_room_coords = destination
		door.state = DungeonEnums.DoorState.LOCKED if locked else DungeonEnums.DoorState.CLOSED
		door.required_key_type = DungeonEnums.KeyType.STANDARD_KEY if locked else DungeonEnums.KeyType.NONE
		floor_state.rooms[origin].doors.append(door)


func _populate_encounters(floor_state: CrawlFloorState, definition: FloorDefinition) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_state.encounter_seed
	for coords in floor_state.rooms:
		if coords == floor_state.start or floor_state.rooms[coords].node_type == DungeonEnums.RoomNodeType.CHEST_ROOM:
			continue
		var groups: Array = []
		var budget := maxi(0, definition.encounter_budget + (definition.floor_depth - 1) * 4)
		for index in range(clampi(definition.max_encounter_groups, 1, 4)):
			var eligible: Array[EnemyGroupResource] = []
			for option in definition.standard_enemy_pool:
				if option != null and option.enemy != null and option.min_count > 0 and option.max_count >= option.min_count and option.unit_budget_cost > 0 and option.min_count * option.unit_budget_cost <= budget:
					eligible.append(option)
			if eligible.is_empty():
				break
			var option := eligible[rng.randi_range(0, eligible.size() - 1)]
			var count := rng.randi_range(option.min_count, mini(option.max_count, budget / option.unit_budget_cost))
			groups.append({"enemy": option.enemy, "count": count, "formation": option.formation})
			budget -= count * option.unit_budget_cost
		floor_state.encounters[coords] = groups


func validate(floor_state: CrawlFloorState, definition: FloorDefinition) -> Array[String]:
	var errors: Array[String] = []
	var low := clampi(definition.min_rooms, 6, 64)
	if floor_state.rooms.size() < low or floor_state.rooms.size() > clampi(definition.max_rooms, low, 64):
		errors.append("Room count outside configured bounds.")
	if not floor_state.rooms.has(floor_state.start) or not floor_state.rooms.has(floor_state.boss) or floor_state.boss == floor_state.start:
		errors.append("Missing start-to-boss spine.")
	var edge_counts: Dictionary = {}
	for coords in floor_state.rooms:
		var destinations: Dictionary = {}
		if floor_state.rooms[coords].coordinates != coords:
			errors.append("Room coordinates disagree with graph key.")
		for door in floor_state.rooms[coords].doors:
			var target: Vector2i = door.connected_room_coords
			if destinations.has(target):
				errors.append("Duplicate door at %s." % coords)
			destinations[target] = true
			edge_counts[door.id] = edge_counts.get(door.id, 0) + 1
			if not floor_state.rooms.has(target) or not DIRECTIONS.has(target - coords) or door.direction != target - coords:
				errors.append("Invalid cardinal edge at %s." % coords)
				continue
			var reverse := floor_state.door_between(target, coords)
			if reverse == null or reverse.id != door.id or reverse.state != door.state or reverse.required_key_type != door.required_key_type or reverse.unlock_switch_id != door.unlock_switch_id:
				errors.append("Nonreciprocal door %s." % door.id)
	for edge_id in edge_counts:
		if edge_id == "" or edge_counts[edge_id] != 2:
			errors.append("Edge ID must identify exactly two directions: %s" % edge_id)
	# Monotone reachability: reusable keys/switches acquired in reachable rooms.
	# Assumes encounters in reachable rooms can be won; this validates topology, not balance.
	var reached: Dictionary = {floor_state.start: true}
	var acquired_keys: Dictionary = {}
	var activated: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		for coords in reached.keys():
			if not floor_state.rooms.has(coords):
				continue
			if floor_state.key_pickups.has(coords):
				var key_type: int = floor_state.key_pickups[coords]
				if not acquired_keys.has(key_type):
					acquired_keys[key_type] = true
					changed = true
			for lever in floor_state.rooms[coords].switches:
				if not activated.has(lever.id):
					activated[lever.id] = true
					changed = true
			for door in floor_state.rooms[coords].doors:
				var passable: bool = door.state != DungeonEnums.DoorState.LOCKED
				if not passable:
					passable = activated.has(door.unlock_switch_id) if door.unlock_switch_id != "" else acquired_keys.has(door.required_key_type)
				if passable and floor_state.rooms.has(door.connected_room_coords) and not reached.has(door.connected_room_coords):
					reached[door.connected_room_coords] = true
					changed = true
	if reached.size() != floor_state.rooms.size():
		errors.append("Some rooms cannot be reached with obtainable keys/switches.")
	return errors
