class_name EnemyGroupResource
extends Resource
## Authored spawn option, never a mutable battle group.

@export var enemy: EnemyResource
@export_range(1, 100) var min_count: int = 3
@export_range(1, 100) var max_count: int = 8
@export_range(1, 100) var unit_budget_cost: int = 1
@export_enum("Front", "Middle", "Back") var formation: String = "Front"
