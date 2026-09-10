extends SceneTree

## End-to-end check against the real GitHub release feed: HTTPRequest must
## follow GitHub's 302 to its asset host, parse the feed, and decide correctly.

var check := Check.new()

func _init() -> void:
	_run()

func _run() -> void:
	var up := Updater.new()
	get_root().add_child(up)
	await process_frame

	print("feed: %s" % up.feed_url)
	check.that(up.feed_url != "", "update feed is configured in project.godot")
	if up.feed_url == "":
		quit(check.finish("live feed"))
		return

	var done := {"hit": false, "found": false, "version": ""}
	up.check_finished.connect(func(found: bool) -> void:
		done["hit"] = true
		done["found"] = found)
	up.update_available.connect(func(v: String, _n: String) -> void:
		done["version"] = v)

	up.check(true)
	var waited := 0.0
	while not done["hit"] and waited < 40.0:
		await process_frame
		waited += 0.016

	check.that(done["hit"], "feed request completed (waited %.1fs)" % waited)
	print("running version : %s" % Updater.current_version())
	print("feed offered    : found=%s version=%s" % [done["found"], done["version"]])

	# The published release is the same version this build reports, so the
	# correct answer is "no update", not "no connection".
	check.that(up.live_reachable, "GitHub feed was reachable and parsed")
	check.that(not done["found"], "no update offered when already on the latest")

	# Positive path, against the bytes GitHub actually served: pretend the
	# published release is newer and confirm it would be offered for download.
	await _offer_path(up)
	quit(check.finish("live feed"))


func _offer_path(up: Updater) -> void:
	var http := HTTPRequest.new()
	get_root().add_child(http)
	http.request(up.feed_url.rstrip("/") + "/releases.win.json")
	var res: Array = await http.request_completed
	if int(res[1]) != 200:
		check.that(false, "could re-fetch the published feed")
		return

	var raw: PackedByteArray = res[3]
	var doc: Dictionary = JSON.parse_string(raw.get_string_from_utf8())
	for a: Dictionary in doc["Assets"]:
		a["Version"] = "9.9.9"
		a["FileName"] = "PetFly-9.9.9-full.nupkg"

	var offered := {"v": ""}
	up.update_available.connect(func(v: String, _n: String) -> void: offered["v"] = v)
	up._handle_feed(JSON.stringify(doc).to_utf8_buffer())
	print("published feed, version bumped -> offered %s" % offered["v"])
	check.that(offered["v"] == "9.9.9", "a newer published release would be offered")
	check.that(str(up._pending.get("FileName", "")) == "PetFly-9.9.9-full.nupkg",
			"the right package is staged for download")
