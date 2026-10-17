class_name CrawlSaveStore
extends RefCounted
## Two independent versioned documents; each replacement is a same-directory rename.

const SCHEMA: int = 1
const MAX_BYTES: int = 8 * 1024 * 1024
var directory: String = "user://progression"
var revisions: Dictionary = {}


func _path(kind: String) -> String:
	return directory.path_join(kind + ".json")


func _read(path: String, kind: String, validator: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": true, "reason": "Save does not exist."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {"ok": false, "reason": "Save is unreadable or exceeds the size limit."}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK: return {"ok": false, "reason": "Save JSON is malformed."}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.get("format") != "crawl-save" or parsed.get("kind") != kind:
		return {"ok": false, "reason": "Invalid save envelope."}
	if not CrawlProgressionCatalog.integer(parsed.get("schema"), 1, 100000): return {"ok": false, "reason": "Invalid save schema field."}
	if parsed.schema != SCHEMA:
		return {"ok": false, "protected": true, "reason": "Unsupported save schema. Original files were retained."}
	if not CrawlProgressionCatalog.integer(parsed.get("revision"), 1, 2000000000): return {"ok": false, "reason": "Invalid save revision."}
	if not parsed.get("body") is String or not parsed.get("digest") is String or parsed.body.sha256_text() != parsed.digest:
		return {"ok": false, "reason": "Save checksum failed."}
	parser = JSON.new()
	if parser.parse(parsed.body) != OK: return {"ok": false, "reason": "Save payload JSON is malformed."}
	var payload: Variant = parser.data
	if not payload is Dictionary:
		return {"ok": false, "reason": "Invalid save payload."}
	var reason: String = validator.call(payload)
	if reason != "":
		return {"ok": false, "reason": reason, "protected": reason.begins_with("Unsupported")}
	return {"ok": true, "payload": payload, "revision": int(parsed.get("revision", 0))}


func load_document(kind: String, validator: Callable) -> Dictionary:
	var primary := _read(_path(kind), kind, validator)
	if primary.ok:
		revisions[kind] = primary.revision
		primary["notice"] = ""
		return primary
	if primary.get("protected", false):
		return primary
	var backup := _read(_path(kind) + ".bak", kind, validator)
	if backup.ok:
		revisions[kind] = backup.revision
		backup["notice"] = "%s save restored from its last valid backup. %s" % [kind.capitalize(), primary.reason]
		return backup
	if primary.get("missing", false) and backup.get("missing", false):
		return {"ok": false, "missing": true, "reason": "No saved %s yet." % kind}
	return {"ok": false, "reason": "%s save and backup could not be loaded. %s Files were retained." % [kind.capitalize(), primary.reason]}


func write_document(kind: String, payload: Dictionary, validator: Callable) -> Dictionary:
	var validation: String = validator.call(payload)
	if validation != "":
		return {"ok": false, "reason": validation}
	var folder_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if folder_error != OK:
		return {"ok": false, "reason": "Could not create save directory (%d)." % folder_error}
	var path := _path(kind)
	var previous := _read(path, kind, validator)
	if previous.get("protected", false):
		return previous
	var revision := maxi(int(revisions.get(kind, 0)), int(previous.get("revision", 0))) + 1
	var body := JSON.stringify(payload)
	var envelope := {"format": "crawl-save", "schema": SCHEMA, "kind": kind, "revision": revision, "body": body, "digest": body.sha256_text()}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "Could not open temporary save file (%d)." % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or not _read(path + ".tmp", kind, validator).ok:
		return {"ok": false, "reason": "Temporary save failed validation or flush."}
	if previous.ok:
		var copy_error := DirAccess.copy_absolute(path, path + ".bak.tmp")
		if copy_error != OK or DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			return {"ok": false, "reason": "Could not preserve the previous valid save."}
	var rename_error := DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK:
		return {"ok": false, "reason": "Could not atomically replace save (%d)." % rename_error}
	revisions[kind] = revision
	if not FileAccess.file_exists(path + ".bak"):
		DirAccess.copy_absolute(path, path + ".bak")
	return {"ok": true, "revision": revision, "reason": ""}
