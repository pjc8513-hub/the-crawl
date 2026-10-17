class_name CrawlEnemyValidation
extends RefCounted


static func dice_info(formula: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^\\s*(\\d+)d(\\d+)\\s*([+-]\\s*\\d+)?\\s*$")
	var matched := pattern.search(formula)
	if matched == null:
		return {}
	var count := matched.get_string(1).to_int()
	var faces := matched.get_string(2).to_int()
	var bonus := matched.get_string(3).replace(" ", "").replace("\t", "").to_int()
	if count < 1 or faces < 1 or count > 100 or faces > 1000:
		return {}
	return {"count": count, "faces": faces, "bonus": bonus, "min": count + bonus, "max": count * faces + bonus, "average": count * (faces + 1) / 2.0 + bonus}


static func errors(data: EnemyResource) -> Array[String]:
	var result: Array[String] = []
	if data == null:
		result.append("Missing enemy definition.")
		return result
	if data.id == "" or data.display_name == "":
		result.append("Enemy requires an ID and name.")
	var hp_dice := dice_info(data.hit_dice_formula)
	var spawn_dice := dice_info(data.spawn_dice_formula)
	if hp_dice.is_empty():
		result.append("%s: invalid HP dice '%s'." % [data.id, data.hit_dice_formula])
	elif hp_dice.min < 1 or hp_dice.min != data.min_hp or hp_dice.max != data.max_hp or not is_equal_approx(hp_dice.average, data.avg_hp):
		result.append("%s: HP bounds/average disagree with %s (expected %d-%d, avg %.1f)." % [data.id, data.hit_dice_formula, hp_dice.min, hp_dice.max, hp_dice.average])
	if spawn_dice.is_empty():
		result.append("%s: invalid spawn dice '%s'." % [data.id, data.spawn_dice_formula])
	elif spawn_dice.min < 1 or spawn_dice.min != data.min_group_count or spawn_dice.max != data.max_group_count:
		result.append("%s: spawn bounds disagree with %s (expected %d-%d)." % [data.id, data.spawn_dice_formula, spawn_dice.min, spawn_dice.max])
	if data.gold < 0 or data.xp < 0:
		result.append("%s: negative rewards." % data.id)
	return result


static func roll(formula: String, rng: RandomNumberGenerator) -> int:
	var dice := dice_info(formula)
	if dice.is_empty():
		return 0
	var value: int = dice.bonus
	for index in range(dice.count):
		value += rng.randi_range(1, dice.faces)
	return value
