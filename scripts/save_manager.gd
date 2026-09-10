class_name SaveManager
extends RefCounted

## Saving and loading the pet, so it keeps living between sessions.
##
## Writes go to a temp file first and are then renamed over the real one, so a
## crash or a power cut mid-save cannot leave a half-written pet behind.

const SCHEMA := 1
const SAVE_PATH := "user://pet.json"
const TEMP_PATH := "user://pet.json.tmp"


static func load_pet() -> Dictionary:
	## Returns {sim: Sim, returning: bool}.
	var sim := Sim.new()
	if not FileAccess.file_exists(SAVE_PATH):
		return {"sim": sim, "returning": false}

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("PetFly: could not open save file")
		return {"sim": sim, "returning": false}
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PetFly: save file unreadable, starting a new pet")
		return {"sim": sim, "returning": false}
	var data: Dictionary = parsed
	if int(data.get("schema", 0)) != SCHEMA:
		push_warning("PetFly: save schema mismatch, starting a new pet")
		return {"sim": sim, "returning": false}

	sim.from_dict(data.get("pet", {}))
	return {"sim": sim, "returning": true}


static func save_pet(sim: Sim) -> bool:
	var payload := {"schema": SCHEMA, "version": _version(), "pet": sim.to_dict()}
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("PetFly: could not write save file")
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(SAVE_PATH.get_file()):
		dir.remove(SAVE_PATH.get_file())
	var err := dir.rename(TEMP_PATH.get_file(), SAVE_PATH.get_file())
	return err == OK


static func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
