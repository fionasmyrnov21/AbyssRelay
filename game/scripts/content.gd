extends RefCounted

static var db: Dictionary = {}

static func load_data() -> Dictionary:
	if db.is_empty():
		db = JSON.parse_string(FileAccess.get_file_as_string("res://assets/content.json"))
	return db

static func title(entry: Dictionary) -> String:
	return str(entry.get("name_en", entry.get("id", "")))

static func module(id: String) -> Dictionary:
	return load_data().modules.get(id, {})

