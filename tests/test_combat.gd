extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_content()
	_test_damage()
	_test_reach()
	_test_rules()
	_test_statuses()
	_test_termination()
	_test_session()
	_test_action_effects()
	for seed_value in range(30):
		var first := _run_fixture(seed_value)
		var second := _run_fixture(seed_value)
		check(first.events == second.events, "deterministic event stream seed %d" % seed_value)
		check(first.outcome in ["victory", "defeat", "stalemate"], "bounded fixture seed %d" % seed_value)
		for actor in first.actors:
			check(actor.hp >= 0 and actor.hp <= actor.max_hp and actor.mp >= 0 and actor.mp <= actor.max_mp, "resource bounds seed %d" % seed_value)
	print("Combat checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)


func check(condition: bool, label_text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label_text)


func actor(actor_id: String = "party:test") -> CrawlCombatant:
	var unit := CrawlCombatant.new()
	unit.id = actor_id
	unit.group_id = actor_id
	unit.display_name = actor_id
	unit.max_mp = 30
	unit.mp = 30
	unit.attack = 0
	unit.magic = 0
	unit.known_skills = ["attack", "potion", "heal", "fireball", "dart", "cleave", "defend", "poison_strike", "stun_strike"]
	return unit


func group(count: int = 3, group_id: String = "enemy:test", row: String = "Front") -> EnemyGroup:
	var result := EnemyGroup.new()
	result.initialize_group(load("res://data/enemies/koboldfighter.tres"), count, null, group_id)
	result.position_row = row
	for unit in result.units:
		unit.max_hp = 10
		unit.hp = 10
		unit.row = row
		unit.armor = 0
		unit.attack = 0
		unit.enemy_data = null
	return result


func battle(unit: CrawlCombatant, enemies: Array[EnemyGroup]) -> CrawlCombatEngine:
	var result := CrawlCombatEngine.new()
	result.configure([unit], enemies, 123)
	return result


func _test_content() -> void:
	for path in DirAccess.get_files_at("res://data/enemies"):
		if path.ends_with(".tres"):
			var data: EnemyResource = load("res://data/enemies/" + path)
			check(CrawlEnemyValidation.errors(data).is_empty(), "content validates: " + path)
	var bad: EnemyResource = load("res://data/enemies/koboldfighter.tres").duplicate()
	bad.max_group_count = 5
	check(not CrawlEnemyValidation.errors(bad).is_empty(), "contradictory dice rejected")
	check(CrawlEnemyValidation.dice_info("invalid").is_empty(), "malformed dice rejected")
	check(CrawlEnemyValidation.dice_info("2d6 - 1").min == 1, "negative dice modifier supported")
	var rejected := EnemyGroup.new()
	check(not rejected.initialize_group(bad, 3), "invalid data not instantiated")


func _test_damage() -> void:
	var enemies := group()
	enemies.take_damage(40)
	check(enemies.current_count == 2 and enemies.units[1].hp == 10, "ordinary overkill kills one only")
	enemies = group()
	enemies.take_damage(25, -1, true)
	check(enemies.current_count == 1 and enemies.units[2].hp == 5, "explicit group cleave spills")
	enemies = group()
	enemies.units[0].hp = 5
	var hero := actor()
	var engine := battle(hero, [enemies])
	var aoe: CrawlCombatSkill = engine.skills.fireball.duplicate()
	aoe.power = 6
	check(engine.perform(hero, aoe, enemies.units[0]), "group AoE legal")
	check(enemies.current_count == 2 and enemies.units[1].hp == 4 and enemies.units[2].hp == 4, "AoE applies independently to every living member")
	check(hero.mp == 24, "AoE cost paid once")
	var before := hero.mp
	check(not engine.perform(hero, aoe, enemies.units[0]) and hero.mp == before, "dead target rejects without cost")
	var negative: CrawlCombatSkill = aoe.duplicate()
	negative.power = -1
	check(not engine.perform(hero, negative, enemies.units[1]) and hero.mp == before, "negative skill power rejected")
	var other := group(1, "other")
	engine = battle(actor(), [group(2), other])
	engine.perform(engine.party[0], engine.skills.fireball, engine.groups[0].units[0])
	check(other.units[0].hp == 10, "AoE does not affect another group")
	enemies = group(2)
	enemies.units[0].enemy_data = load("res://data/enemies/koboldwizard.tres")
	engine = battle(actor(), [enemies])
	engine.perform(engine.party[0], aoe, enemies.units[0])
	check(enemies.units[0].hp == 7 and enemies.units[1].hp == 4, "fire resistance applies per unit")


func _test_reach() -> void:
	var hero := actor()
	var front := group(1, "front")
	var back := group(2, "back", "Back")
	var engine := battle(hero, [front, back])
	check(not engine.eligible_targets(hero, engine.skills.attack).has(back.units[0]), "front blocks melee")
	check(engine.eligible_targets(hero, engine.skills.dart).has(back.units[0]), "ranged reaches back")
	hero.tactics = [CrawlCombatContent.rule("back", "always", 0, "attack", "backline")]
	check(engine.choose_action(hero).target == front.units[0], "backline selector respects melee reach")
	hero.attack = 20
	engine.perform(hero, engine.skills.attack, front.units[0])
	check(engine.eligible_targets(hero, engine.skills.attack).has(back.units[0]), "reach updates after front dies")
	hero.tactics[0].selector = "highest_count"
	check(engine.choose_action(hero).target.group_id == "back", "highest count selection")
	back.units[0].hp = 0
	check(engine.choose_action(hero).target == back.units[1], "selector never retains dead target")


func _test_rules() -> void:
	var hero := actor()
	var engine := battle(hero, [group()])
	hero.hp = 40
	hero.tactics = [CrawlCombatContent.rule("heal", "self_hp_percent", 40, "heal", "self")]
	check(engine.choose_action(hero).skill.id == "attack", "strict below threshold at exactly 40%")
	hero.hp = 39
	check(engine.choose_action(hero).skill.id == "heal", "heal below threshold")
	hero.mp = 3
	check(engine.choose_action(hero).skill.id == "attack", "unaffordable heal falls through")
	hero.mp = 4
	hero.tactics[0].reserve_mp = 1
	check(engine.choose_action(hero).skill.id == "attack", "MP reserve respected")
	hero.tactics = [CrawlCombatContent.rule("potion", "always", 0, "potion", "self"), CrawlCombatContent.rule("heal", "always", 0, "heal", "self")]
	hero.potions = 0
	check(engine.choose_action(hero).skill.id == "heal", "missing potion falls through to heal")
	check(hero.mp == 4 and hero.potions == 0, "choosing action consumes nothing")
	hero.tactics.reverse()
	check(engine.choose_action(hero).rule == "heal", "priority order used")
	hero.max_mp = 0
	hero.mp = 0
	hero.tactics = [CrawlCombatContent.rule("cast", "self_mp_percent", -1, "fireball", "highest_count")]
	check(not engine._condition(hero, hero.tactics[0]), "no MP pool percentage is false")
	hero.tactics[0].enabled = false
	check(engine.choose_action(hero).skill.id == "attack", "disabled rule falls through")
	hero.known_skills = ["defend"]
	check(engine.choose_action(hero).skill.id == "defend", "defend fallback")
	var ally := actor("party:ally")
	ally.max_hp = 200
	ally.hp = 50
	hero.hp = 30
	hero.max_mp = 30
	hero.mp = 30
	hero.known_skills.append("heal")
	engine.configure([hero, ally], [group()], 123)
	hero.tactics = [CrawlCombatContent.rule("heal", "lowest_ally_hp_percent", 40, "heal", "lowest_hp_percent")]
	check(engine.choose_action(hero).target == ally, "percentage selector differs from absolute HP")
	check(engine._select(engine.eligible_targets(hero, engine.skills.heal), "lowest_hp", hero) == hero, "absolute HP selector")
	ally.hp = 0
	check(engine.choose_action(hero).target == hero, "healing excludes dead allies")


func _test_statuses() -> void:
	var hero := actor()
	hero.initiative = 100
	var enemies := group(1)
	var engine := battle(hero, [enemies])
	hero.statuses.stun = {"turns": 1, "potency": 0}
	engine.step()
	check(not hero.statuses.has("stun") and engine.events[-1].type == "skip", "stun expires after skipping owner turn")
	hero.statuses.poison = {"turns": 2, "potency": 3}
	engine.step() # Enemy opportunity.
	engine.step() # Hero opportunity next round.
	check(hero.hp == 97 and hero.statuses.poison.turns == 1, "poison ticks at start of owner turn")
	var poisoned := actor()
	poisoned.hp = 2
	poisoned.initiative = 100
	poisoned.statuses.poison = {"turns": 1, "potency": 3}
	engine = battle(poisoned, [group(1)])
	engine.step()
	check(engine.outcome == "defeat" and poisoned.hp == 0, "poison death ends fight before action")
	hero = actor()
	hero.attack = 0
	enemies = group(1)
	engine = battle(hero, [enemies])
	engine.perform(hero, engine.skills.poison_strike, enemies.units[0])
	check(enemies.units[0].statuses.has("poison"), "status skill attaches independent state")
	engine.perform(hero, engine.skills.defend, hero)
	check(hero.defending, "defend buff active")


func _test_termination() -> void:
	var hero := actor()
	var engine := battle(hero, [group(1)])
	engine.round_limit = 2
	for index in range(20):
		engine.step()
	check(engine.outcome == "stalemate" and engine.reward_gold() == 0, "stalemate bounded without rewards")
	var event_count := engine.events.size()
	engine.step()
	check(engine.events.size() == event_count, "terminal steps are idempotent")
	var enemies := group(1)
	enemies.units[0].enemy_data = load("res://data/enemies/koboldfighter.tres")
	hero.attack = 100
	engine = battle(hero, [enemies])
	engine.perform(hero, engine.skills.attack, enemies.units[0])
	check(engine.outcome == "victory" and engine.reward_gold() == 10, "victory reward per slain individual")
	var invalid := actor()
	invalid.id = hero.id
	engine.configure([hero, invalid], [group(1)], 0)
	check(engine.outcome == "invalid", "duplicate actor IDs rejected")


func _run_fixture(seed_value: int) -> CrawlCombatEngine:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var enemies: Array[EnemyGroup] = []
	for filename in ["koboldfighter", "koboldwizard"]:
		var enemy_group := EnemyGroup.new()
		enemy_group.initialize_group(load("res://data/enemies/%s.tres" % filename), 4, rng, "enemy:" + filename)
		enemies.append(enemy_group)
	var engine := CrawlCombatEngine.new()
	engine.configure(CrawlCombatContent.party(), enemies, seed_value)
	for index in range(10000):
		if engine.outcome != "ongoing":
			break
		engine.step()
	return engine


func _test_session() -> void:
	var definition := FloorDefinition.new()
	var floor_state := CrawlFloorGenerator.new().generate(definition, 1)
	var destination: Vector2i = floor_state.rooms[floor_state.current].doors[0].connected_room_coords
	check(floor_state.move_to(destination).ok, "session entry reachable")
	var option: EnemyResource = load("res://data/enemies/koboldfighter.tres")
	floor_state.encounters[destination] = [{"enemy": option, "count": 1, "formation": "Front"}]
	var session := CrawlEncounterSession.new()
	session.floor_state = floor_state
	var hero := actor()
	hero.attack = 100
	hero.initiative = 100
	session.party = [hero]
	check(session.begin(), "session starts encounter")
	check(not session.begin(), "duplicate session start rejected")
	check(floor_state.travel_block_reason != "", "combat blocks travel")
	session.advance()
	check(session.result_pending and not floor_state.rooms[destination].is_cleared, "results pending before clearing room")
	check(not floor_state.search_current_room().ok, "pending results block searches")
	check(session.acknowledge().gold == 10 and session.run_gold == 10, "acknowledgement grants reward once")
	check(not session.acknowledge().ok and session.run_gold == 10, "double acknowledgement cannot duplicate gold")
	check(floor_state.rooms[destination].is_cleared and floor_state.travel_block_reason == "", "victory releases travel lock")
	check(not session.begin(), "cleared room cannot restart encounter")
	check(hero.mp == 30 and hero.hp == 100, "party state not reset on results")


func _test_action_effects() -> void:
	var hero := actor()
	var enemies := group(3)
	var engine := battle(hero, [enemies])
	hero.hp = 90
	check(engine.perform(hero, engine.skills.potion, hero), "potion usable when injured")
	check(hero.hp == 100 and hero.potions == 1 and hero.mp == 30, "potion clamps heal and consumes one item")
	check(not engine.perform(hero, engine.skills.potion, hero) and hero.potions == 1, "full health potion is not wasted")
	hero.hp = 50
	check(engine.perform(hero, engine.skills.heal, hero) and hero.hp == 68 and hero.mp == 26, "spell heals and pays exact MP")
	hero.max_mp = 20
	hero.mp = 7
	var spell_rule := CrawlCombatContent.rule("cast", "self_mp_percent", 35, "fireball", "highest_count")
	check(not engine._condition(hero, spell_rule), "strict MP above at exactly 35% is false")
	hero.mp = 8
	check(engine._condition(hero, spell_rule), "MP above threshold is true")
	hero.attack = 0
	var cleave: CrawlCombatSkill = engine.skills.cleave.duplicate()
	cleave.power = 25
	cleave.mp_cost = 0
	for unit in enemies.units:
		unit.armor = 5
	engine.perform(hero, cleave, enemies.units[0])
	check(enemies.units[0].hp == 0 and enemies.units[1].hp == 5 and enemies.units[2].hp == 10, "cleave spends mitigation before overflow")
	# Choose at execution time: the next actor must not retain the first actor's victim.
	var first := actor("party:first")
	var second := actor("party:second")
	first.attack = 100
	second.attack = 100
	first.initiative = 100
	second.initiative = 99
	enemies = group(2)
	engine.configure([first, second], [enemies], 5)
	engine.step()
	engine.step()
	check(enemies.current_count == 0 and engine.outcome == "victory", "successive actors retarget after previous kill")
