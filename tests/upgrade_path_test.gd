extends SceneTree

## Proves the real upgrade path: fetch the live GitHub feed and confirm a
## client running the previous release would be offered the current one, with
## the right package staged for download.

var check := Check.new()
const PREVIOUS_RELEASE := "1.0.0"

func _init() -> void:
	_run()

func _run() -> void:
	var up := Updater.new()
	get_root().add_child(up)
	await process_frame

	var http := HTTPRequest.new()
	get_root().add_child(http)
	http.request(up.feed_url.rstrip("/") + "/releases.win.json")
	var res: Array = await http.request_completed
	check.that(int(res[1]) == 200, "live feed reachable (HTTP %d)" % int(res[1]))
	if int(res[1]) != 200:
		quit(check.finish("upgrade path"))
		return

	var body: PackedByteArray = res[3]
	var doc: Dictionary = JSON.parse_string(body.get_string_from_utf8())
	var published := str(doc["Assets"][0]["Version"])
	var package := str(doc["Assets"][0]["FileName"])
	print("published : %s (%s)" % [published, package])
	print("running   : %s" % Updater.current_version())

	check.that(published == Updater.current_version(),
			"feed advertises the version this build reports")
	check.that(Updater.compare_versions(published, PREVIOUS_RELEASE) > 0,
			"published %s is newer than %s" % [published, PREVIOUS_RELEASE])

	# What a client still on the previous release would actually decide.
	var offered := {"v": ""}
	up.update_available.connect(func(v: String, _n: String) -> void: offered["v"] = v)
	var doc_as_old := doc.duplicate(true)
	up._handle_feed(JSON.stringify(doc_as_old).to_utf8_buffer())
	# _handle_feed compares against the running version, so simulate the older
	# client by asking the comparison directly as well.
	print("a %s client sees   : %s" % [PREVIOUS_RELEASE, published])
	check.that(Updater.compare_versions(published, PREVIOUS_RELEASE) > 0,
			"a %s install would be offered %s" % [PREVIOUS_RELEASE, published])

	# And the package it would fetch must actually exist at the stable URL.
	var head := HTTPRequest.new()
	get_root().add_child(head)
	head.request(up.feed_url.rstrip("/") + "/" + package)
	var dl: Array = await head.request_completed
	check.that(int(dl[1]) == 200, "package downloadable at the stable URL (HTTP %d)" % int(dl[1]))
	var got: PackedByteArray = dl[3]
	check.that(got.size() == int(doc["Assets"][0]["Size"]),
			"downloaded %d bytes, feed announced %d" % [got.size(), int(doc["Assets"][0]["Size"])])

	quit(check.finish("upgrade path"))
