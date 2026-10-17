class_name CrawlClassDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var max_hp: int = 100
@export var max_mp: int = 0
@export var attack: int = 10
@export var magic: int = 0
@export var armor: int = 0
@export var initiative: int = 5
@export_enum("Front", "Middle", "Back") var formation: String = "Front"
@export var skill_ids: Array[String] = ["attack", "potion", "defend"]
@export var tactics: Array[CrawlTacticRule] = []
