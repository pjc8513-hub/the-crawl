extends SceneTree
## Snapshot captured from the code-authored definitions before resource migration.

var checks: int = 0
var failures: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/content_baseline.json"))
	check(CrawlContent.CATALOG.errors().is_empty(), "Authored catalog validates: " + str(CrawlContent.CATALOG.errors()))
	_compare_definitions(baseline)
	_test_isolation()
	_test_validation()
	_compare_battles(baseline)
	print("Content checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)


func _compare_definitions(baseline: Dictionary) -> void:
	var skills := CrawlContent.skills()
	var items := CrawlProgressionCatalog.items()
	var classes := CrawlContent.classes()
	check(skills.size() == baseline.skills.size(), "All skills migrated")
	check(items.size() == baseline.items.size(), "All items migrated")
	check(classes.size() == baseline.classes.size(), "All classes migrated")
	for pair in [[baseline.skills, skills], [baseline.items, items]]:
		for record in pair[0]:
			for field in record:
				check(pair[1][record.id].get(field) == record[field], "%s.%s unchanged" % [record.id, field])
	for record in baseline.classes:
		var definition: CrawlClassDefinition = classes[record.id]
		for field in record:
			if field == "skill_ids":
				check(definition.skill_ids() == record[field], "Class skills unchanged: " + record.id)
			elif field == "tactics":
				check(definition.tactics.size() == record.tactics.size(), "Class tactic count unchanged")
				for index in range(definition.tactics.size()):
					check(JSON.parse_string(JSON.stringify(CrawlProgressionCatalog.pack_rule(definition.tactics[index]))) == record.tactics[index], "Class tactic unchanged")
			else:
				check(definition.get(field) == record[field], "%s.%s unchanged" % [record.id, field])
	for field in baseline.economy:
		check(JSON.parse_string(JSON.stringify(CrawlContent.economy().get(field))) == baseline.economy[field], "Economy unchanged: " + field)
	for index in range(baseline.enemies.size()):
		check(CrawlContent.CATALOG.enemies[index].resource_path.get_file() == baseline.enemies[index] + ".tres", "Enemy catalog order unchanged")
	var profile := CrawlProgressionCatalog.fresh_profile()
	for id in baseline.economy.rank_costs:
		profile.ranks[id] = 3
	var ranked := CrawlProgressionCatalog.skills(profile)
	for id in baseline.economy.rank_costs:
		check(ranked[id].power == skills[id].power + 3 * baseline.economy.power_per_rank[id], "Rank power unchanged: " + id)
		var bonus := 30 if id in ["sleep", "freezing_wind", "charming_potion", "earthquake"] else 0
		check(ranked[id].status_chance == mini(100, skills[id].status_chance + bonus), "Rank chance unchanged: " + id)
	profile.classes.append("rogue")
	profile.skills = CrawlContent.economy().skill_unlocks.keys()
	check(CrawlProgressionCatalog.profile_error(profile) == "", "All authored unlocks fit in a valid profile")
	for actor in CrawlProgressionCatalog.party(profile, profile.classes):
		for upgrade in CrawlContent.economy().upgrades:
			if upgrade.kind == "skill" and upgrade.class_definition.id == actor.class_id:
				check(actor.known_skills.has(upgrade.skill.id), "Class receives authored unlock: " + upgrade.skill.id)


func _test_isolation() -> void:
	var one := CrawlContent.skills()
	var two := CrawlContent.skills()
	one.fireball.power = 999
	check(two.fireball.power == 10, "Skill factories are independent")
	check(load("res://data/skills/fireball.tres").power == 10, "Shared skill asset is unchanged")
	var profile := CrawlProgressionCatalog.fresh_profile()
	profile.skills = ["freezing_wind"]
	profile.ranks = {"fireball": 3}
	CrawlProgressionCatalog.skills(profile)
	check(CrawlContent.skills().fireball.power == 10, "Ranks do not leak to enemies or later runs")
	var actors := CrawlProgressionCatalog.party(profile, ["mage", "mage"])
	actors[0].tactics[0].threshold = 99
	actors[0].known_skills.clear()
	actors[0].hp = 1
	check(actors[1].tactics[0].threshold == 25 and not actors[1].known_skills.is_empty() and actors[1].hp == 75, "Duplicate classes own independent state")
	check(CrawlContent.classes().mage.tactics[0].threshold == 25, "Shared class tactic is unchanged")
	var unlocked := actors[0].tactics[actors[0].tactics.size() - 2]
	unlocked.threshold = 99
	check(actors[1].tactics[actors[1].tactics.size() - 2].threshold == 3, "Unlocked tactics are independent")
	var later := CrawlProgressionCatalog.party(profile, ["mage"])[0]
	check(later.tactics[later.tactics.size() - 2].threshold == 3, "Upgrade tactic asset is unchanged")
	var pool := CrawlRoomFlow.item_pool()
	pool.clear()
	check(CrawlRoomFlow.item_pool().size() == 8, "Loot pool membership is independent")
	var fresh := CrawlProgressionCatalog.fresh_profile()
	fresh.classes.clear()
	check(fresh.loadout.size() == 3 and CrawlContent.economy().starting_slots == 3, "Profile arrays do not alias defaults")


func _test_validation() -> void:
	var catalog: CrawlContentCatalog = CrawlContent.CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	check(catalog.errors().is_empty(), "Deeply copied composition validates")
	catalog.skills.append(catalog.skills[0])
	check(not catalog.errors().is_empty(), "Duplicate content IDs rejected")
	catalog = CrawlContent.CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var foreign := CrawlCombatSkill.new()
	foreign.id = "unregistered"
	catalog.classes[0].skills.append(foreign)
	check(not catalog.errors().is_empty(), "Unregistered class skill rejected")
	catalog = CrawlContent.CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	catalog.classes[0].tactics[0].skill_id = "unregistered"
	check(not catalog.errors().is_empty(), "Invalid class tactic rejected")
	catalog = CrawlContent.CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	catalog.progression.upgrades.append(catalog.progression.upgrades[0])
	check(not catalog.errors().is_empty(), "Duplicate purchases rejected")
	catalog = CrawlContent.CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	catalog.progression.slot_costs.clear()
	check(not catalog.errors().is_empty(), "Invalid slot costs rejected")
	catalog = CrawlContent.CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	catalog.progression.upgrades[0].class_definition = null
	check(not catalog.errors().is_empty(), "Missing upgrade reference rejected")
	check(CrawlContent.CATALOG.errors().is_empty(), "Validation fixtures leave authored content unchanged")


func _compare_battles(baseline: Dictionary) -> void:
	for fixture in baseline.events:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(fixture.seed)
		var groups: Array[EnemyGroup] = []
		for enemy_id in ["koboldfighter", "koboldwizard", "goblincleric"]:
			var group := EnemyGroup.new()
			group.initialize_group(load("res://data/enemies/%s.tres" % enemy_id), 3, rng, enemy_id)
			groups.append(group)
		var engine := CrawlCombatEngine.new()
		engine.configure(CrawlCombatContent.party(), groups, int(fixture.seed))
		while engine.outcome == "ongoing":
			engine.step()
		check(JSON.stringify(engine.events).sha256_text() == fixture.hash, "Pre-migration combat event stream unchanged: %d" % fixture.seed)
