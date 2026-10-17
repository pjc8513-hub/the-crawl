class_name EnemyGroup
extends RefCounted
## Individual state is authoritative; count and leading HP are derived.

var id: String = "enemy_group"
var enemy_data: EnemyResource
var position_row: String = "Front"
var units: Array[CrawlCombatant] = []
var current_count: int:
	get:
		return living_units().size()
var current_unit_hp: int:
	get:
		var living := living_units()
		return living[0].hp if not living.is_empty() else 0


func initialize_group(data: EnemyResource, rolled_count: int, rng: RandomNumberGenerator = null, group_id: String = "enemy_group") -> bool:
	units.clear()
	if not CrawlEnemyValidation.errors(data).is_empty() or rolled_count < 1 or rolled_count > 100:
		return false
	id = group_id
	enemy_data = data
	position_row = "Back" if data.subtype_class in ["Wizard", "Cleric"] else "Middle" if data.subtype_class == "Ninja" else "Front"
	for index in range(rolled_count):
		var unit := CrawlCombatant.new()
		unit.id = "%s:%03d" % [id, index]
		unit.group_id = id
		unit.side = "enemy"
		unit.display_name = data.display_name
		unit.row = position_row
		unit.enemy_data = data
		unit.max_hp = CrawlEnemyValidation.roll(data.hit_dice_formula, rng) if rng != null else data.max_hp
		unit.hp = unit.max_hp
		unit.attack = maxi(0, 1 + data.base_strength + data.bonus_damage_base)
		unit.magic = maxi(0, data.base_wisdom + data.magic_amp_base)
		unit.armor = maxi(0, floori(data.base_endurance / 2.0))
		unit.initiative = data.base_dexterity + data.initiative_bonus
		unit.potions = 0
		if data.subtype_class == "Wizard":
			unit.max_mp = 12
			unit.mp = 12
			unit.known_skills = ["attack", "dart", "defend"]
			unit.tactics = [CrawlCombatContent.rule("cast", "always", 0, "dart", "lowest_hp")]
		elif data.subtype_class == "Cleric":
			unit.max_mp = 12
			unit.mp = 12
			unit.known_skills = ["attack", "heal", "defend"]
			unit.tactics = [CrawlCombatContent.rule("heal", "lowest_ally_hp_percent", 40, "heal", "lowest_hp_percent")]
		units.append(unit)
	return true


func living_units() -> Array[CrawlCombatant]:
	var result: Array[CrawlCombatant] = []
	for unit in units:
		if unit.alive():
			result.append(unit)
	return result


func take_damage(amount: int, target_index: int = -1, cleave: bool = false) -> Dictionary:
	var slain := 0
	var remaining_damage := maxi(0, amount)
	for index in range(units.size()):
		var unit := units[index]
		if not unit.alive() or (target_index >= 0 and index != target_index):
			continue
		var dealt := mini(unit.hp, remaining_damage)
		unit.hp -= dealt
		remaining_damage -= dealt
		if not unit.alive():
			slain += 1
		if not cleave or remaining_damage <= 0:
			break
	return {"slain": slain, "remaining": current_count}


func take_group_damage(amount: int) -> void:
	for unit in living_units():
		unit.hp = maxi(0, unit.hp - maxi(0, amount))
