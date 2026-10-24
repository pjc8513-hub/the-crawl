class_name CrawlContent
extends RefCounted
## Shared authored assets are read-only. Factories copy mutable battle inputs.

const CATALOG: CrawlContentCatalog = preload("res://data/content.tres")


static func skills() -> Dictionary:
	var result: Dictionary = {}
	for definition in CATALOG.skills:
		result[definition.id] = definition.duplicate(true)
	return result


static func classes() -> Dictionary:
	var result: Dictionary = {}
	for definition in CATALOG.classes:
		result[definition.id] = definition
	return result


static func enemies() -> Dictionary:
	var result: Dictionary = {}
	for definition in CATALOG.enemies:
		result[definition.id] = definition
	return result


static func economy() -> CrawlProgressionDefinition:
	return CATALOG.progression
