class_name Updater
extends Node

## In-game update checking, against a Velopack release feed.
##
## PetFly is packaged with Velopack (the same installer/updater Summer Engine
## itself uses). Velopack's Update.exe can apply and roll back packages, but
## checking and downloading are normally the job of the Velopack SDK, which has
## no GDScript binding. So this does those two steps directly - fetch the feed,
## compare versions, download the .nupkg - and then hands the package to
## Update.exe, which does the actual install and restart.
##
## Layout that Velopack installs into:
##
##   %LOCALAPPDATA%\PetFly\
##     Update.exe          <- the updater
##     packages\           <- downloaded .nupkg files land here
##     current\PetFly.exe  <- the running game
##
## The feed URL is read from application/config/update_feed in project.godot.
## It is empty by default: with no feed configured, update checks are simply
## skipped rather than pointed at a URL that does not exist.

signal update_available(version: String, notes: String)
signal update_progress(fraction: float)
signal update_ready()
signal update_failed(reason: String)
signal check_finished(found: bool)

const FEED_FILE := "releases.win.json"

var feed_url := ""
var _http: HTTPRequest
var _mode := ""                # "check" | "download"
var _pending: Dictionary = {}


func _ready() -> void:
	feed_url = str(ProjectSettings.get_setting("application/config/update_feed", "")).strip_edges()
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)


# -- environment -------------------------------------------------------------
static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func install_root() -> String:
	## The Velopack install directory, i.e. the parent of current\.
	if not OS.has_feature("editor"):
		var exe_dir := OS.get_executable_path().get_base_dir()
		return exe_dir.get_base_dir()
	return ""


static func update_exe() -> String:
	var root := install_root()
	if root == "":
		return ""
	var path := root.path_join("Update.exe")
	return path if FileAccess.file_exists(path) else ""


static func is_managed_install() -> bool:
	## True when running from a Velopack install that can actually self-update.
	return update_exe() != ""


static func compare_versions(a: String, b: String) -> int:
	## Semver-ish compare of the numeric parts. 1 if a > b, -1 if a < b, else 0.
	var pa := a.split("-")[0].split(".")
	var pb := b.split("-")[0].split(".")
	for i in 3:
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


# -- checking ----------------------------------------------------------------
func check() -> void:
	if feed_url == "":
		check_finished.emit(false)
		return
	if not is_managed_install():
		# Portable or editor run: nothing to update in place.
		check_finished.emit(false)
		return
	if _mode != "":
		return
	_mode = "check"
	var url := feed_url.rstrip("/") + "/" + FEED_FILE
	var err := _http.request(url, ["User-Agent: PetFly/%s" % current_version()])
	if err != OK:
		_mode = ""
		update_failed.emit("could not reach the update feed")
		check_finished.emit(false)


func _on_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var mode := _mode
	_mode = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if mode == "check":
			check_finished.emit(false)
		else:
			update_failed.emit("download failed (HTTP %d)" % code)
		return

	if mode == "check":
		_handle_feed(body)
	else:
		_handle_package(body)


func _handle_feed(body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		check_finished.emit(false)
		return

	# Velopack's feed lists assets; pick the newest full package.
	var assets: Array = parsed.get("Assets", parsed.get("assets", []))
	var best := {}
	var best_ver := current_version()
	for a: Dictionary in assets:
		var kind := str(a.get("Type", a.get("type", "Full")))
		if kind.to_lower() == "delta":
			continue
		var ver := str(a.get("Version", a.get("version", "")))
		if ver == "":
			continue
		if compare_versions(ver, best_ver) > 0:
			best_ver = ver
			best = a

	if best.is_empty():
		check_finished.emit(false)
		return
	_pending = best
	update_available.emit(best_ver, str(best.get("NotesMarkdown", "")))
	check_finished.emit(true)


# -- downloading and applying ------------------------------------------------
func download_and_apply() -> void:
	if _pending.is_empty():
		update_failed.emit("no update pending")
		return
	if _mode != "":
		return
	var name := str(_pending.get("FileName", _pending.get("fileName", "")))
	if name == "":
		update_failed.emit("update feed did not name a package")
		return
	_mode = "download"
	var url := feed_url.rstrip("/") + "/" + name
	var err := _http.request(url, ["User-Agent: PetFly/%s" % current_version()])
	if err != OK:
		_mode = ""
		update_failed.emit("could not start the download")


func _handle_package(body: PackedByteArray) -> void:
	var root := install_root()
	if root == "":
		update_failed.emit("not a managed install")
		return
	var packages := root.path_join("packages")
	DirAccess.make_dir_recursive_absolute(packages)
	var name := str(_pending.get("FileName", _pending.get("fileName", "package.nupkg")))
	var path := packages.path_join(name)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		update_failed.emit("could not write the downloaded package")
		return
	f.store_buffer(body)
	f.close()
	_pending["_local_path"] = path
	update_ready.emit()


func apply_now() -> void:
	## Hand off to Velopack, which swaps the install and relaunches the game.
	var exe := update_exe()
	var path := str(_pending.get("_local_path", ""))
	if exe == "" or path == "":
		update_failed.emit("nothing staged to apply")
		return
	var args := PackedStringArray([
		"apply", "--package", path, "--waitPid", str(OS.get_process_id()),
	])
	var pid := OS.create_process(exe, args)
	if pid <= 0:
		update_failed.emit("could not launch the updater")
		return
	# Update.exe waits for us to exit, then installs and restarts PetFly.
	get_tree().quit()
