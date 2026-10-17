class_name CrawlTacticRule
extends Resource

@export var id: String = ""
@export var enabled: bool = true
@export_enum("always", "self_hp_percent", "self_hp", "lowest_ally_hp_percent", "lowest_ally_hp", "self_mp_percent", "enemy_group_count") var metric: String = "always"
@export_enum("below", "above", "at_most", "at_least") var comparator: String = "below"
@export var threshold: float = 40.0
@export var skill_id: String = "attack"
@export_enum("self", "lowest_hp", "highest_hp", "lowest_hp_percent", "backline", "highest_count") var selector: String = "lowest_hp"
@export var reserve_mp: int = 0
@export var min_group_count: int = 0
