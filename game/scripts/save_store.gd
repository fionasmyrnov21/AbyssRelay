extends RefCounted

const Sim = preload("res://scripts/simulation.gd")
static var prefix = "user://relay_"

static func encoded_snapshot(sim) -> String:
	var payload=JSON.stringify(sim.snapshot())
	return JSON.stringify({"checksum":payload.sha256_text(),"payload":payload})

static func save_game(sim, slot: String = "auto") -> Error:
	if slot not in ["auto", "1", "2", "3"]:
		return ERR_INVALID_PARAMETER
	var path = prefix + slot + ".json"
	var envelope=encoded_snapshot(sim)
	if prefix=="user://relay_" and Engine.has_singleton("RelayLifecycle"):
		var success=Engine.get_singleton("RelayLifecycle").write_snapshot("relay_"+slot+".json",envelope)
		if success:sim.needs_save=false
		return OK if success else ERR_FILE_CANT_WRITE
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(envelope); file.flush(); file.close()
	if _read(path + ".tmp").is_empty():
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		var backup_error = DirAccess.rename_absolute(path, path + ".bak")
		if backup_error != OK:
			return backup_error
	var result = DirAccess.rename_absolute(path + ".tmp", path)
	if result == OK:
		sim.needs_save = false
	return result

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var envelope = parser.data
	if not envelope is Dictionary or not envelope.get("payload") is String:
		return {}
	if envelope.get("checksum", "") != str(envelope.payload).sha256_text():
		return {}
	if parser.parse(envelope.payload) != OK:
		return {}
	var data = parser.data
	return data if data is Dictionary else {}

static func load_game(sim, slot: String = "auto") -> bool:
	if slot not in ["auto", "1", "2", "3"]:
		return false
	var path = prefix + slot + ".json"
	for candidate in [path, path + ".bak"]:
		var data = _read(candidate)
		if not data.is_empty() and sim.restore(data):
			return true
	return false

static func exists(slot: String = "auto") -> bool:
	return not _read(prefix + slot + ".json").is_empty() or not _read(prefix + slot + ".json.bak").is_empty()
