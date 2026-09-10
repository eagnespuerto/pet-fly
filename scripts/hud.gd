class_name HUD
extends CanvasLayer

## PetFly's whole 2D layer: vitals, food bar, the VFB brain panel, and the
## full-screen overlays for circuit detail, credits and help.

signal food_requested(key: String)
signal lights_toggled()
signal rouse_requested()
signal model_cycle_requested()
signal circuit_selected(key: String)
signal refresh_requested(key: String)
signal open_url_requested(url: String)
signal update_requested()

const METERS := [
	{"key": "fullness", "label": "Fullness", "colour": UIKit.GREEN},
	{"key": "hydration", "label": "Hydration", "colour": UIKit.BLUE},
	{"key": "rested", "label": "Rested", "colour": UIKit.YELLOW},
	{"key": "mood", "label": "Mood", "colour": UIKit.GREEN},
	{"key": "health", "label": "Health", "colour": UIKit.RED},
]

var _vfb: VFB
var _sim: Sim

var _name_label: Label
var _status_label: Label
var _clock_label: Label
var _log_label: Label
var _toast_label: Label
var _toast_t := 0.0

var _meters := {}
var _meter_values := {}
var _food_buttons := {}
var _lights_button: Button
var _rouse_button: Button

var _circuit_rows := {}
var _vfb_status: Label

var _overlay: Control
var _ov_title: Label
var _ov_sub: Label
var _ov_body: Label
var _ov_detail: Label
var _ov_list: VBoxContainer
var _ov_refresh: Button
var _ov_open: Button
var _overlay_mode := ""
var _selected_circuit := ""
var _selected_neuron := 0

var _update_button: Button


var _root: Control


func setup(sim: Sim, vfb: VFB) -> void:
	_sim = sim
	_vfb = vfb
	# Anchors alone do not size a Control that is not inside a Container, so the
	# whole HUD is laid out with real containers: a full-rect margin, a column,
	# and one row that pushes the vitals left and the brain panel right.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var page := MarginContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("margin_left", 20)
	page.add_theme_constant_override("margin_right", 20)
	page.add_theme_constant_override("margin_top", 16)
	page.add_theme_constant_override("margin_bottom", 10)
	_root.add_child(page)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(column)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(right)

	_build_vitals(left)
	_build_brain_panel(right)
	_build_food_bar(column)
	_build_overlay()


# -- vitals ------------------------------------------------------------------
func _build_vitals(parent: Node) -> void:
	var pane := UIKit.panel(Color(0.10, 0.13, 0.18, 0.82))
	parent.add_child(pane)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 16)
	pane.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	inner.add_child(col)

	_name_label = UIKit.label("Buzz", 38, UIKit.INK, true)
	col.add_child(_name_label)
	_status_label = UIKit.label("", 17, UIKit.INK_DIM)
	col.add_child(_status_label)
	_clock_label = UIKit.label("", 15, UIKit.INK_FAINT)
	col.add_child(_clock_label)
	col.add_child(UIKit.spacer(14))

	for spec in METERS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		row.custom_minimum_size = Vector2(250, 0)

		var head := HBoxContainer.new()
		var name_l := UIKit.label(spec["label"], 14, UIKit.INK_DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_l)
		var val_l := UIKit.label("0%", 14, UIKit.INK_DIM)
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(val_l)
		row.add_child(head)

		var m := UIKit.meter(spec["colour"])
		row.add_child(m)
		row.add_child(UIKit.spacer(8))
		col.add_child(row)

		_meters[spec["key"]] = {"bar": m, "value": val_l, "colour": spec["colour"]}

	# Event log sits under the vitals.
	col.add_child(UIKit.spacer(10))
	_log_label = UIKit.label("", 13, UIKit.INK_FAINT)
	_log_label.custom_minimum_size = Vector2(250, 62)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(_log_label)


# -- food bar ----------------------------------------------------------------
func _build_food_bar(parent: Node) -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var hint := UIKit.label(
		"1-5 feed   ·   L lights   ·   R rouse   ·   B brain   ·   M model   ·   H help",
		13, UIKit.INK_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(hint)

	_toast_label = UIKit.label("", 17, UIKit.INK)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_toast_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var i := 1
	for food in Sim.FOODS:
		var colour: String = UIKit.RED if food["bitter"] > 0.5 else UIKit.GREEN
		var b := UIKit.button("%d  %s" % [i, food["short"]], colour, 14)
		b.custom_minimum_size = Vector2(148, 40)
		b.tooltip_text = "%s\n%s" % [food["name"], food["blurb"]]
		var key: String = food["key"]
		b.pressed.connect(func() -> void: food_requested.emit(key))
		row.add_child(b)
		_food_buttons[key] = b
		i += 1



# -- brain panel -------------------------------------------------------------
func _build_brain_panel(parent: Node) -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	parent.add_child(outer)

	# Top controls
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.add_theme_constant_override("separation", 8)
	_rouse_button = UIKit.button("ROUSE", UIKit.BLUE, 13)
	_rouse_button.custom_minimum_size = Vector2(118, 36)
	_rouse_button.pressed.connect(func() -> void: rouse_requested.emit())
	controls.add_child(_rouse_button)
	_lights_button = UIKit.button("LIGHTS OFF", UIKit.YELLOW, 13)
	_lights_button.custom_minimum_size = Vector2(138, 36)
	_lights_button.pressed.connect(func() -> void: lights_toggled.emit())
	controls.add_child(_lights_button)
	outer.add_child(controls)

	var pane := UIKit.panel()
	pane.custom_minimum_size = Vector2(330, 0)
	outer.add_child(pane)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 11)
	pane.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	margin.add_child(col)

	col.add_child(UIKit.label("BRAIN", 20, UIKit.INK, true))
	col.add_child(UIKit.label("Virtual Fly Brain circuits", 13, UIKit.INK_DIM))
	_vfb_status = UIKit.label("", 11, UIKit.INK_FAINT)
	_vfb_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vfb_status.custom_minimum_size = Vector2(300, 0)
	col.add_child(_vfb_status)
	col.add_child(UIKit.spacer(8))

	for key in _vfb.circuit_keys():
		var c := _vfb.circuit(key)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)

		var head := HBoxContainer.new()
		var dot := UIKit.label("*", 14, UIKit.INK_FAINT)
		dot.custom_minimum_size = Vector2(14, 0)
		head.add_child(dot)
		var title := UIKit.label(str(c.get("title", key)), 14, UIKit.INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var count := UIKit.label("", 12, UIKit.INK_FAINT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(count)
		row.add_child(head)

		var bar := UIKit.meter(UIKit.BLUE, 11)
		row.add_child(bar)

		# The whole row is clickable.
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(300, 34)
		btn.tooltip_text = str(c.get("blurb", ""))
		btn.pressed.connect(func() -> void: circuit_selected.emit(key))
		btn.add_child(row)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(btn)

		_circuit_rows[key] = {"bar": bar, "count": count, "dot": dot}

	col.add_child(UIKit.spacer(8))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var b_vfb := UIKit.button("OPEN VFB", UIKit.GREY, 12)
	b_vfb.custom_minimum_size = Vector2(140, 34)
	b_vfb.pressed.connect(func() -> void: open_url_requested.emit(VFB.SITE_URL))
	buttons.add_child(b_vfb)
	var b_credits := UIKit.button("CREDITS", UIKit.GREY, 12)
	b_credits.custom_minimum_size = Vector2(140, 34)
	b_credits.pressed.connect(func() -> void: show_credits())
	buttons.add_child(b_credits)
	col.add_child(buttons)

	var nt := _vfb.nt_counts()
	if not nt.is_empty():
		var pairs := []
		for k: String in nt:
			pairs.append([k, nt[k]])
		pairs.sort_custom(func(a, b): return a[1] > b[1])
		var parts := PackedStringArray()
		for p in pairs.slice(0, 3):
			parts.append("%s %d" % [str(p[0]).substr(0, 4), p[1]])
		var l := UIKit.label("Predicted transmitters  " + " ".join(parts), 11, UIKit.INK_FAINT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		col.add_child(UIKit.spacer(6))
		col.add_child(l)

	# Update banner, shown only when an update is actually available.
	_update_button = UIKit.button("UPDATE AVAILABLE", UIKit.GREEN, 12)
	_update_button.custom_minimum_size = Vector2(300, 34)
	_update_button.visible = false
	_update_button.pressed.connect(func() -> void: update_requested.emit())
	col.add_child(UIKit.spacer(6))
	col.add_child(_update_button)


func show_update_available(version: String) -> void:
	if _update_button:
		_update_button.text = "UPDATE TO %s" % version
		_update_button.visible = true


# -- overlay -----------------------------------------------------------------
func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_root.add_child(_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 26)
	_overlay.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	_ov_title = UIKit.label("", 34, UIKit.INK, true)
	col.add_child(_ov_title)
	_ov_sub = UIKit.label("", 15, UIKit.INK_DIM)
	_ov_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_ov_sub)
	_ov_body = UIKit.label("", 14, UIKit.INK)
	col.add_child(_ov_body)
	col.add_child(UIKit.spacer(10))

	# Two columns: the neuron list, and the detail for the selected one.
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 34)
	col.add_child(cols)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(left)
	_ov_list = VBoxContainer.new()
	_ov_list.add_theme_constant_override("separation", 1)
	left.add_child(_ov_list)

	_ov_detail = UIKit.label("", 13, UIKit.INK_DIM)
	_ov_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ov_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	cols.add_child(_ov_detail)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)

	_ov_refresh = UIKit.button("REFRESH LIVE", UIKit.BLUE, 13)
	_ov_refresh.custom_minimum_size = Vector2(190, 44)
	_ov_refresh.pressed.connect(func() -> void: refresh_requested.emit(_selected_circuit))
	foot.add_child(_ov_refresh)

	_ov_open = UIKit.button("OPEN IN VFB", UIKit.GREEN, 13)
	_ov_open.custom_minimum_size = Vector2(190, 44)
	_ov_open.pressed.connect(_open_selected)
	foot.add_child(_ov_open)

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(grow)

	var close := UIKit.button("CLOSE", UIKit.GREY, 13)
	close.custom_minimum_size = Vector2(150, 44)
	close.pressed.connect(close_overlay)
	foot.add_child(close)


func _open_selected() -> void:
	var n := _current_neuron()
	if n.is_empty():
		open_url_requested.emit(VFB.SITE_URL)
	else:
		open_url_requested.emit(str(n.get("url", VFB.SITE_URL)))


func _current_neuron() -> Dictionary:
	if _overlay_mode != "circuit" or _selected_circuit == "":
		return {}
	var neurons: Array = _vfb.circuit(_selected_circuit).get("neurons", [])
	if neurons.is_empty():
		return {}
	return neurons[mini(_selected_neuron, neurons.size() - 1)]


func overlay_open() -> bool:
	return _overlay.visible


func close_overlay() -> void:
	_overlay_mode = ""
	_overlay.visible = false


func show_circuit(key: String) -> void:
	_selected_circuit = key
	_selected_neuron = 0
	_overlay_mode = "circuit"
	_render_overlay()


func toggle_brain() -> void:
	if _overlay_mode == "circuit":
		close_overlay()
	else:
		var keys := _vfb.circuit_keys()
		show_circuit(_selected_circuit if _selected_circuit != "" else str(keys[0]))


func show_credits() -> void:
	_overlay_mode = "credits"
	_render_overlay()


func show_help() -> void:
	_overlay_mode = "help"
	_render_overlay()


func refresh_circuit_view() -> void:
	if _overlay_mode == "circuit":
		_render_overlay()


func set_refresh_label(text: String) -> void:
	_ov_refresh.text = text


func _render_overlay() -> void:
	_overlay.visible = true
	for c in _ov_list.get_children():
		c.queue_free()
	var is_circuit := _overlay_mode == "circuit"
	_ov_refresh.visible = is_circuit
	_ov_open.visible = is_circuit

	match _overlay_mode:
		"circuit": _render_circuit()
		"credits": _render_credits()
		_: _render_help()


func _render_circuit() -> void:
	var c := _vfb.circuit(_selected_circuit)
	var neurons: Array = c.get("neurons", [])
	_ov_title.text = str(c.get("title", _selected_circuit)).to_upper()
	var live := "     ·     refreshed live from VFB" if c.get("live", false) else ""
	_ov_sub.text = str(c.get("blurb", "")) + live
	_ov_body.text = "%d neuron classes   ·   drives %s   ·   root term %s" % [
		neurons.size(), str(c.get("drives", "?")),
		str(c.get("root", {}).get("id", "?"))]

	var sel := mini(_selected_neuron, maxi(0, neurons.size() - 1))
	for i in neurons.size():
		var n: Dictionary = neurons[i]
		var text := str(n.get("label", n.get("id", "")))
		if str(n.get("symbol", "")) != "":
			text += "  (%s)" % n["symbol"]
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = ("> " if i == sel else "   ") + text
		b.add_theme_font_override("font", UIKit.font())
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UIKit.INK if i == sel else UIKit.INK_DIM)
		b.add_theme_color_override("font_hover_color", UIKit.INK)
		var idx := i
		b.pressed.connect(func() -> void:
			_selected_neuron = idx
			_render_overlay())
		_ov_list.add_child(b)

	var n := _current_neuron()
	if n.is_empty():
		_ov_detail.text = "No neurons loaded for this circuit."
		return
	var bits := PackedStringArray()
	bits.append(str(n.get("label", "")))
	bits.append(str(n.get("id", "")))
	var tags: Array = n.get("tags", [])
	if not tags.is_empty():
		bits.append("tags: " + ", ".join(PackedStringArray(tags.slice(0, 5))))
	var descr := str(n.get("description", ""))
	if descr != "":
		bits.append("")
		bits.append(descr)
	bits.append("")
	bits.append("OPEN IN VFB shows the full report for this term.")
	_ov_detail.text = "\n".join(bits)


func _render_credits() -> void:
	_ov_title.text = "CREDITS"
	_ov_sub.text = _vfb.attribution()
	var lines := PackedStringArray()
	lines.append("FLY MODELS   (press M in game to switch)")
	for m in Fly.MODELS:
		lines.append("   %-16s %-11s poly.pizza" % [m["author"], m["licence"]])
	lines.append("")
	lines.append("UI ART, FONT & SOUND")
	lines.append("   Kenney UI Pack 2.0   ·   CC0   ·   kenney.nl")
	lines.append("")
	lines.append("BRAIN DATA")
	lines.append("   Virtual Fly Brain   ·   virtualflybrain.org")
	lines.append("   Queried with the vfb_connect API.")
	lines.append("   Drosophila Anatomy Ontology (FBbt) and")
	lines.append("   published connectome datasets.")
	lines.append("   " + _vfb.source_note)
	lines.append("")
	lines.append("ENGINE")
	lines.append("   Summer Engine (Godot 4.7)")
	_ov_body.text = ""
	var l := UIKit.label("\n".join(lines), 14, UIKit.INK)
	_ov_list.add_child(l)
	_ov_detail.text = ("The CC-BY models require attribution, which is what this "
		+ "screen is for. The CC0 model (Kohyzazi) and the Kenney UI pack carry "
		+ "no attribution requirement, but are credited anyway.\n\n"
		+ "Virtual Fly Brain aggregates published Drosophila neuroanatomy. "
		+ "Individual neurons carry their own dataset licences, shown on their "
		+ "VFB report pages.\n\nPetFly %s" % ProjectSettings.get_setting(
			"application/config/version", "1.0.0"))


func _render_help() -> void:
	_ov_title.text = "HOW PETFLY WORKS"
	_ov_sub.text = "A fruit fly whose hunger and sleep follow real Drosophila biology."
	_ov_body.text = ""
	var left := PackedStringArray([
		"KEYS",
		"   1-5   offer food",
		"   L     toggle lights",
		"   R     rouse the fly",
		"   B     brain panel",
		"   M     swap fly model",
		"   C     credits",
		"   H     this screen",
		"   Esc   close / quit",
		"   drag to orbit   ·   wheel to zoom",
		"",
		"TIME",
		"   1 real second = 1 fly minute, so a full fly day",
		"   passes in 24 real minutes. ZT is Zeitgeber Time:",
		"   ZT0 is lights on, ZT12 is lights off.",
		"",
		"   Your fly keeps living while the game is closed,",
		"   up to 16 fly hours.",
		"",
		"FOOD",
		"   Sugar, water and bitter are what fly gustatory",
		"   neurons actually tell apart, so the menu follows",
		"   those axes. Bitter gets refused outright.",
	])
	_ov_list.add_child(UIKit.label("\n".join(left), 14, UIKit.INK))
	_ov_detail.text = "\n".join(PackedStringArray([
		"SLEEP",
		"",
		"Sleep is not a timer. It follows the two-process model",
		"used in real fly sleep research:",
		"",
		"   Process C - circadian drive from the clock",
		"   (pacemaker) neurons. Flies are crepuscular: active",
		"   at dawn and dusk, a midday siesta, and",
		"   consolidated night sleep.",
		"",
		"   Process S - sleep pressure, gated by the dorsal",
		"   fan-shaped body neurons. It builds while awake and",
		"   discharges during sleep.",
		"",
		"The fly sleeps when C + S crosses a threshold, and",
		"wakes when it drops below a lower one.",
		"",
		"A starving fly stays awake to forage, exactly as real",
		"flies do. So feed it.",
	]))


# -- per-frame ---------------------------------------------------------------
func toast(message: String) -> void:
	_toast_label.text = message
	_toast_t = 4.0


func update_hud(delta: float) -> void:
	var s := _sim
	_name_label.text = s.pet_name
	var word := s.status_word()
	_status_label.text = word if word == "Asleep" else "%s   ·   awake" % word
	_clock_label.text = "%s   ·   fly day %d   ·   %s" % [
		s.clock_string(), s.fly_day, "light" if s.zt < 12.0 else "dark"]

	_meter_values["fullness"] = s.fullness
	_meter_values["hydration"] = s.hydration
	_meter_values["rested"] = 1.0 - s.sleep_pressure
	_meter_values["mood"] = s.mood
	_meter_values["health"] = s.health
	for key: String in _meters:
		var m: Dictionary = _meters[key]
		var v: float = _meter_values[key]
		m["bar"].value = v
		m["value"].text = "%d%%" % roundi(v * 100.0)
		if key == "fullness":
			UIKit.set_meter_colour(m["bar"], UIKit.RED if v < 0.2 else UIKit.GREEN)
		elif key == "health":
			UIKit.set_meter_colour(m["bar"], UIKit.RED if v < 0.4 else UIKit.GREEN)

	var acts := s.circuit_activations()
	for key: String in _circuit_rows:
		var row: Dictionary = _circuit_rows[key]
		var a: float = acts.get(key, 0.0)
		row["bar"].value = a
		UIKit.set_meter_colour(row["bar"], UIKit.YELLOW if a > 0.66 else UIKit.BLUE)
		var c := _vfb.circuit(key)
		var n: int = (c.get("neurons", []) as Array).size()
		row["count"].text = "%d%s" % [n, " live" if c.get("live", false) else ""]
		row["dot"].add_theme_color_override("font_color",
				UIKit.INK_FAINT.lerp(Color(1.0, 0.92, 0.45), a))

	_vfb_status.text = "%s   ·   %d neurons   ·   %s" % [
		_vfb.source_note, _vfb.neuron_count(), _vfb.live_status]

	_lights_button.text = "LIGHTS OFF" if s.zt < 12.0 else "LIGHTS ON"
	_rouse_button.disabled = not s.asleep
	for key: String in _food_buttons:
		var food := Sim.food_by_key(key)
		_food_buttons[key].disabled = s.asleep and food["sugar"] <= 0.3

	var lines := PackedStringArray()
	for e in s.events.slice(maxi(0, s.events.size() - 4)):
		lines.append(str(e["text"]))
	_log_label.text = "\n".join(lines)

	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast_label.text = ""
