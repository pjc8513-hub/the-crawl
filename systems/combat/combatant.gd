class_name CrawlCombatant
extends RefCounted

var id: String
var class_id: String = ""
var display_name: String
var side: String = "party"
var group_id: String
var row: String = "Front"
var max_hp: int = 100
var hp: int = 100
var max_mp: int = 0
var mp: int = 0
var attack: int = 10
var magic: int = 0
var armor: int = 0
var initiative: int = 5
var potions: int = 2
var known_skills: Array[String] = ["attack", "potion", "defend"]
var tactics: Array[CrawlTacticRule] = []
var statuses: Dictionary = {} # ID -> {turns, potency}; tick at start of owner's turn.
var defending: bool = false
var fled: bool = false
var status_chance_bonus: int = 0
var freeze_thaw_penalty: int = 0
var meditation_percent: int = 0
var focus_percent: int = 0
var battle_armor: int = 0
var bloodlust_bonus: int = 0
var enemy_data: EnemyResource
var equipment: Dictionary = {} # Slot -> immutable ItemDefinition; inventory owns instances.


func alive() -> bool:
	return hp > 0 and not fled


func hp_percent() -> float:
	return 100.0 * hp / max_hp if max_hp > 0 else 0.0


func from_class(definition: CrawlClassDefinition, actor_id: String) -> void:
	id = actor_id
	class_id = definition.id
	group_id = actor_id
	display_name = definition.display_name
	max_hp = maxi(1, definition.max_hp)
	hp = max_hp
	max_mp = maxi(0, definition.max_mp)
	mp = max_mp
	attack = maxi(0, definition.attack)
	magic = maxi(0, definition.magic)
	armor = maxi(0, definition.armor)
	initiative = definition.initiative
	row = definition.formation
	known_skills = definition.skill_ids()
	tactics.clear()
	for rule in definition.tactics:
		tactics.append(rule.duplicate(true))
