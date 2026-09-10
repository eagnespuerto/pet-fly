class_name VFB
extends Node

## Virtual Fly Brain data for PetFly.
##
## Two paths, deliberately:
##
##   Bundled - assets/data/vfb_brain.json, harvested at build time with the
##             vfb_connect Python API (see tools/harvest_vfb.py in the source
##             repo). Loads instantly and works with no network, so the game
##             always has a real brain.
##
##   Live    - queries virtualflybrain.org at runtime: Cypher against the public
##             Neo4j endpoint, plus Solr for free-text search. Godot's
##             HTTPRequest is async, so this never blocks a frame.

const NEO_ENDPOINT := "https://pdb.v4.virtualflybrain.org/db/data/transaction/commit"
const SOLR_ENDPOINT := "https://solr.virtualflybrain.org/solr/ontology/select"
const REPORT_URL := "https://virtualflybrain.org/reports/%s"
const SITE_URL := "https://virtualflybrain.org"
const BUNDLE_PATH := "res://assets/data/vfb_brain.json"
const LIVE_CACHE := "user://vfb_live.json"

const TIMEOUT_SEC := 25.0

## Stable, meaningful order for the brain panel.
const CIRCUIT_ORDER := [
	"sweet_taste", "bitter_taste", "water_taste", "clock",
	"sleep_homeostat", "reward", "memory", "navigation",
]

signal refresh_finished(circuit_key: String, ok: bool, message: String)

var bundle: Dictionary = {}
var source_note := "not loaded"
var live_status := "offline"

var _http: HTTPRequest
var _busy_key := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_load()


# -- loading -----------------------------------------------------------------
func _load() -> void:
	var text := ""
	if ResourceLoader.exists(BUNDLE_PATH) or FileAccess.file_exists(BUNDLE_PATH):
		var f := FileAccess.open(BUNDLE_PATH, FileAccess.READ)
		if f:
			text = f.get_as_text()
			f.close()
	if text.is_empty():
		bundle = {"circuits": {}, "instances": {}, "nt_tone": {}}
		source_note = "bundle missing"
		push_warning("PetFly: VFB bundle not found at %s" % BUNDLE_PATH)
		return

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		bundle = {"circuits": {}, "instances": {}, "nt_tone": {}}
		source_note = "bundle unreadable"
		return
	bundle = parsed
	var when := str(bundle.get("harvested_utc", "")).substr(0, 10)
	source_note = "VFB bundle %s" % when if when != "" else "VFB bundle"

	_overlay_live_cache()


func _overlay_live_cache() -> void:
	## Anything a previous session pulled live wins over the bundled snapshot.
	if not FileAccess.file_exists(LIVE_CACHE):
		return
	var f := FileAccess.open(LIVE_CACHE, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var saved: Dictionary = parsed.get("circuits", {})
	for key: String in saved:
		var neurons: Array = saved[key]
		if circuits().has(key) and not neurons.is_empty():
			circuits()[key]["neurons"] = neurons
			circuits()[key]["count"] = neurons.size()
			circuits()[key]["live"] = true


# -- accessors ---------------------------------------------------------------
func circuits() -> Dictionary:
	return bundle.get("circuits", {})


func circuit(key: String) -> Dictionary:
	return circuits().get(key, {})


func circuit_keys() -> Array:
	var keys: Array = []
	for k in CIRCUIT_ORDER:
		if circuits().has(k):
			keys.append(k)
	for k: String in circuits():
		if not keys.has(k):
			keys.append(k)
	return keys


func neuron_count() -> int:
	var n := 0
	for k: String in circuits():
		n += (circuits()[k].get("neurons", []) as Array).size()
	return n


func nt_counts() -> Dictionary:
	## Merged neurotransmitter tallies across the harvested predictions.
	var total := {}
	var tone: Dictionary = bundle.get("nt_tone", {})
	for k: String in tone:
		var counts: Dictionary = tone[k].get("counts", {})
		for nt: String in counts:
			total[nt] = int(total.get(nt, 0)) + int(counts[nt])
	return total


func attribution() -> String:
	return str(bundle.get("attribution", "Data from Virtual Fly Brain."))


func report_url(short_form: String) -> String:
	return REPORT_URL % short_form


# -- live refresh ------------------------------------------------------------
func is_busy() -> bool:
	return _busy_key != ""


func refresh_circuit(key: String) -> bool:
	## Re-query one circuit's subclasses live from VFB. Returns false if it
	## could not even be started.
	if is_busy():
		return false
	var root: String = str(circuit(key).get("root", {}).get("id", ""))
	if root.is_empty():
		refresh_finished.emit(key, false, "no root term for this circuit")
		return false

	var query := ('MATCH (c:Class)-[:SUBCLASSOF*1..3]->(p:Class {short_form:"%s"}) '
			+ 'WHERE c.label IS NOT NULL '
			+ 'RETURN DISTINCT c.short_form AS id, c.label AS label, '
			+ '       c.symbol AS symbol, c.description AS descr LIMIT 60') % root
	var body := JSON.stringify({"statements": [{"statement": query}]})
	var headers := [
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Basic " + Marshalls.utf8_to_base64("neo4j:vfb"),
		"User-Agent: PetFly/2.0 (+https://virtualflybrain.org)",
	]
	var err := _http.request(NEO_ENDPOINT, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		refresh_finished.emit(key, false, "could not start request (%d)" % err)
		return false
	_busy_key = key
	return true


func _on_request_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var key := _busy_key
	_busy_key = ""
	if key.is_empty():
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		live_status = "offline"
		refresh_finished.emit(key, false, "no connection to VFB (result %d)" % result)
		return
	if code != 200:
		live_status = "offline"
		refresh_finished.emit(key, false, "VFB returned HTTP %d" % code)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		refresh_finished.emit(key, false, "unreadable response from VFB")
		return

	var errors: Array = parsed.get("errors", [])
	if not errors.is_empty():
		refresh_finished.emit(key, false, str(errors[0].get("message", "query error")).substr(0, 90))
		return

	var neurons := _rows_to_neurons(parsed)
	if neurons.is_empty():
		refresh_finished.emit(key, false, "VFB returned no neurons")
		return

	var c: Dictionary = circuits().get(key, {})
	if not c.is_empty():
		c["neurons"] = neurons
		c["count"] = neurons.size()
		c["live"] = true
	live_status = "live"
	_save_live_cache()
	refresh_finished.emit(key, true, "Live from VFB: %d neurons" % neurons.size())


func _rows_to_neurons(payload: Dictionary) -> Array:
	var out: Array = []
	var results: Array = payload.get("results", [])
	if results.is_empty():
		return out
	for entry: Dictionary in results[0].get("data", []):
		var row: Array = entry.get("row", [])
		if row.size() < 2:
			continue
		var id_ := _first(row[0])
		var label := _first(row[1])
		if id_.is_empty() or label.is_empty():
			continue
		out.append({
			"id": id_,
			"label": label,
			"symbol": _first(row[2]) if row.size() > 2 else "",
			"description": _first(row[3]) if row.size() > 3 else "",
			"tags": [],
			"url": REPORT_URL % id_,
		})
	return out


static func _first(v: Variant) -> String:
	## VFB stores some properties as single-element lists.
	if v == null:
		return ""
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v
		return str(a[0]) if not a.is_empty() else ""
	return str(v)


func _save_live_cache() -> void:
	var saved := {}
	for k: String in circuits():
		if circuits()[k].get("live", false):
			saved[k] = circuits()[k].get("neurons", [])
	var f := FileAccess.open(LIVE_CACHE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"saved_utc": Time.get_datetime_string_from_system(true),
		"circuits": saved,
	}))
	f.close()
