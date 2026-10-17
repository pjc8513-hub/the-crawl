extends SceneTree

var failures := 0


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)


func _initialize() -> void:
	var profile := CrawlProgressionCatalog.fresh_profile()
	profile.skills = ["intimidate", "battle_harden", "blood_lust", "giant_slayer", "berserk", "aegis"]
	var warrior := CrawlProgressionCatalog.party(profile, ["warrior"])[0]
	var group := EnemyGroup.new()
	check(group.initialize_group(load("res://data/enemies/koboldfighter.tres"), 2, null, "test:enemies"), "group setup")
	var skill_defs := CrawlCombatContent.skills()
	skill_defs["intimidate"].power = 100
	skill_defs["aegis"].power = 100
	var engine := CrawlCombatEngine.new()
	engine.configure([warrior], [group], 42, skill_defs)
	check(warrior.battle_armor == 2, "battle harden counts front enemies")
	check(group.units[0].statuses.has("fear") and group.units[1].statuses.has("fear"), "intimidate reaches each front enemy")
	var before_hp := warrior.hp
	group.units[0].attack = 100
	check(engine.perform(group.units[0], engine.enemy_skills["attack"], warrior), "enemy attack executes")
	check(warrior.hp == before_hp, "aegis blocks incoming hit")
	check(engine.events.any(func(event: Dictionary) -> bool: return event.type == "block"), "block event emitted")
	warrior.attack = 100
	check(engine.perform(warrior, engine.skills["attack"], group.units[0]), "warrior attack executes")
	check(warrior.bloodlust_bonus == 1, "blood lust grows after party kill")
	warrior.hp = 60
	var powered := engine._power(warrior, engine.skills["attack"], group.units[1])
	check(powered > warrior.attack + warrior.bloodlust_bonus, "berserk increases physical damage")
	warrior.hp = 1
	var giant_damage := engine._power(warrior, engine.skills["attack"], group.units[1])
	warrior.known_skills.erase("giant_slayer")
	var ordinary_damage := engine._power(warrior, engine.skills["attack"], group.units[1])
	check(giant_damage > ordinary_damage, "giant slayer scales against higher current HP")
	group.units[1].statuses["fear"] = {"turns": 100, "potency": 100}
	for turn in range(4):
		engine.step()
	check(engine.events.any(func(event: Dictionary) -> bool: return event.type == "skip" and event.reason == "feared"), "fear can skip an enemy turn")
	print("Warrior passive checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
