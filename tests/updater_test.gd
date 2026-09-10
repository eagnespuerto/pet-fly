extends SceneTree

## Checks the update logic against the real feed that tools/build.ps1 produced,
## so the parser is verified against Velopack's actual output rather than a
## hand-written fixture.

var check := Check.new()

func _init() -> void:
	_versions()
	_feed()
	quit(check.finish("updater"))

func _versions() -> void:
	check.that(Updater.compare_versions("1.1.0", "1.0.0") == 1, "1.1.0 > 1.0.0")
	check.that(Updater.compare_versions("1.0.0", "1.0.1") == -1, "1.0.0 < 1.0.1")
	check.that(Updater.compare_versions("1.0.0", "1.0.0") == 0, "equal versions")
	check.that(Updater.compare_versions("2.0.0", "1.9.9") == 1, "2.0.0 > 1.9.9")
	check.that(Updater.compare_versions("1.2.0-beta", "1.2.0") == 0, "prerelease suffix ignored")
	print("version compare ok")

func _feed() -> void:
	var path := "res://dist/releases.win.json"
	var abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs):
		print("no feed at %s - run tools/build.ps1 first" % abs)
		return
	var f := FileAccess.open(abs, FileAccess.READ)
	var raw := f.get_as_text()
	f.close()

	var up := Updater.new()
	get_root().add_child(up)
	var seen := {"version": "", "hit": false}
	up.update_available.connect(func(v: String, _n: String) -> void:
		seen["version"] = v
		seen["hit"] = true)

	# Same version as the running build: nothing should be offered.
	up._handle_feed(raw.to_utf8_buffer())
	print("feed parsed, current=%s offered=%s" % [Updater.current_version(), seen["hit"]])
	check.that(not seen["hit"], "no update offered for the running version")

	# Now pretend the feed advertises a newer build. Edit it through JSON
	# rather than string replacement: Velopack writes the feed compact, so
	# matching on spacing would silently do nothing.
	var doc: Dictionary = JSON.parse_string(raw)
	for a: Dictionary in doc["Assets"]:
		a["Version"] = "1.4.2"
		a["FileName"] = "PetFly-1.4.2-full.nupkg"
	up._handle_feed(JSON.stringify(doc).to_utf8_buffer())
	print("newer feed -> offered=%s version=%s" % [seen["hit"], seen["version"]])
	check.that(seen["hit"], "newer version is offered")
	check.that(seen["version"] == "1.4.2", "offered version is 1.4.2")
	check.that(str(up._pending.get("FileName", "")) == "PetFly-1.4.2-full.nupkg", "staged the right package")
	print("pending package: %s" % up._pending.get("FileName"))
