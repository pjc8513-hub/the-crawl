class_name CrawlProgressionDefinition
extends Resource
## Initial economy values; purchases are validated against this definition.

@export var starting_slots: int = 3
@export var maximum_slots: int = 6
@export var slot_costs: Array[int] = [150, 350, 700]
@export var class_costs: Dictionary = {"rogue": 120}
@export var skill_unlocks: Dictionary = {
	"cleave": {"class": "warrior", "cost": 120},
	"poison_strike": {"class": "rogue", "cost": 100},
	"stun_strike": {"class": "rogue", "cost": 160}
}
@export var rank_costs: Dictionary = {"attack": 60, "heal": 80, "fireball": 100, "cleave": 100, "poison_strike": 80, "stun_strike": 100}
@export var maximum_skill_rank: int = 3
@export var power_per_rank: Dictionary = {"attack": 2, "heal": 4, "fireball": 3, "cleave": 3, "poison_strike": 2, "stun_strike": 2}
