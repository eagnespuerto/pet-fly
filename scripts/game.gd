extends Node3D

## PetFly - a virtual pet fruit fly with a real Drosophila brain.
##
## The pet's hunger and sleep are simulated (see sim.gd); the circuits in the
## brain panel are real neuron populations from Virtual Fly Brain, harvested
## with the vfb_connect API and refreshable live from virtualflybrain.org.

const SAVE_EVERY := 20.0
const DROP_HEIGHT := Terrarium.VIAL_HEIGHT + 1.1

var sim: Sim
var vfb: VFB
var hud: HUD
var updater: Updater
var terrarium: Terrarium
var fly: Fly

var _camera: Camera3D
var _cam_yaw := 38.0
var _cam_pitch := 11.0
var _cam_dist := 11.5
var _dragging := false
var _save_t := 0.0
var _click_sfx: AudioStreamPlayer
var _tap_sfx: AudioStreamPlayer


func _ready() -> void:
	# --- data
	vfb = VFB.new()
	vfb.name = "VFB"
	add_child(vfb)

	var loaded := SaveManager.load_pet()
	sim = loaded["sim"]
	var returning: bool = loaded["returning"]
	var away := sim.catch_up() if returning else 0.0

	# --- world
	terrarium = Terrarium.new()
	terrarium.name = "Terrarium"
	add_child(terrarium)

	fly = Fly.new()
	fly.name = "Fly"
	add_child(fly)
	fly.set_model(sim.model)

	_build_camera()
	_build_audio()

	# --- ui
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(sim, vfb)
	_connect_hud()

	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.update_available.connect(_on_update_available)
	updater.update_ready.connect(func() -> void: updater.apply_now())
	updater.update_failed.connect(func(why: String) -> void: hud.toast("Update: " + why))
	updater.check()

	vfb.refresh_finished.connect(_on_vfb_refreshed)
	sim.ate.connect(_on_ate)
	sim.refused.connect(_on_refused)

	terrarium.set_food_level(sim.fullness)

	if returning:
		hud.toast("Welcome back - %s carried on without you." % sim.pet_name
				if away > 0.2 else "Welcome back.")
	else:
		hud.toast("A new fly. Press H for help.")


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.current = true
	add_child(_camera)
	_update_camera()


func _build_audio() -> void:
	_click_sfx = AudioStreamPlayer.new()
	_click_sfx.stream = load("res://assets/sounds/click-a.ogg")
	_click_sfx.volume_db = -8.0
	add_child(_click_sfx)
	_tap_sfx = AudioStreamPlayer.new()
	_tap_sfx.stream = load("res://assets/sounds/tap-a.ogg")
	_tap_sfx.volume_db = -8.0
	add_child(_tap_sfx)


func _connect_hud() -> void:
	hud.food_requested.connect(feed)
	hud.lights_toggled.connect(toggle_lights)
	hud.rouse_requested.connect(rouse)
	hud.model_cycle_requested.connect(cycle_model)
	hud.circuit_selected.connect(func(key: String) -> void:
		_tap_sfx.play()
		hud.show_circuit(key))
	hud.refresh_requested.connect(_refresh_circuit)
	hud.open_url_requested.connect(func(url: String) -> void:
		OS.shell_open(url)
		hud.toast("Opened in your browser."))
	hud.update_requested.connect(func() -> void:
		hud.toast("Downloading update...")
		updater.download_and_apply())


# -- camera ------------------------------------------------------------------
func _update_camera() -> void:
	var yaw := deg_to_rad(_cam_yaw)
	var pitch := deg_to_rad(_cam_pitch)
	var target := Vector3(0, 1.9, 0)
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)) * _cam_dist
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist - 0.8, 6.0, 30.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist + 0.8, 6.0, 30.0)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		_cam_yaw -= mm.relative.x * 0.35
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.25, -6.0, 74.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _handle_key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_ESCAPE:
			if hud.overlay_open():
				hud.close_overlay()
			else:
				_quit()
		KEY_H: hud.show_help()
		KEY_C: hud.show_credits()
		KEY_B: hud.toggle_brain()
		KEY_L: toggle_lights()
		KEY_R: rouse()
		KEY_M: cycle_model()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var idx: int = k.keycode - KEY_1
			if idx < Sim.FOODS.size():
				feed(str(Sim.FOODS[idx]["key"]))


# -- actions -----------------------------------------------------------------
func feed(food_key: String) -> void:
	var food := Sim.food_by_key(food_key)
	var result := sim.feed(food_key)
	hud.toast(str(result["message"]))
	# Drop a pellet in whatever the fly decides to do with it: watching the
	# quinine land and then get refused is the point of the bitter food.
	_drop_food(food)
	if result["accepted"]:
		_tap_sfx.play()
	else:
		_click_sfx.play()


func _drop_food(food: Dictionary) -> void:
	var from := Terrarium.DISH_POS + Vector3(
		randf_range(-0.22, 0.22), DROP_HEIGHT, randf_range(-0.22, 0.22))
	var pellet := FoodPellet.spawn(terrarium, food, from)
	pellet.landed.connect(_on_pellet_landed)
	terrarium.set_food_colour(food.get("colour", Color.WHITE))


func _on_pellet_landed(_p: FoodPellet) -> void:
	terrarium.flash_food()
	terrarium.set_food_level(sim.fullness)
	fly.go_feed(Terrarium.DISH_POS)


func _on_ate(_food: Dictionary) -> void:
	terrarium.set_food_level(sim.fullness)


func _on_refused(_food: Dictionary) -> void:
	fly.recoil()


func toggle_lights() -> void:
	var on := not (sim.zt < 12.0)
	sim.set_lights(on)
	hud.toast("Lights %s." % ("on" if on else "off"))
	_click_sfx.play()


func rouse() -> void:
	var r := sim.rouse()
	hud.toast(str(r["message"]))
	_click_sfx.play()


func cycle_model() -> void:
	var keys := []
	for m in Fly.MODELS:
		keys.append(m["key"])
	var i: int = (keys.find(fly.model_key) + 1) % keys.size()
	fly.set_model(str(keys[i]))
	sim.model = fly.model_key
	var info := fly.model_info()
	hud.toast("Model: %s (%s)" % [info["author"], info["licence"]])
	_click_sfx.play()


func _refresh_circuit(key: String) -> void:
	if key == "":
		return
	if vfb.is_busy():
		hud.toast("Already talking to VFB...")
		return
	if vfb.refresh_circuit(key):
		hud.toast("Querying virtualflybrain.org...")
		hud.set_refresh_label("QUERYING...")
	else:
		hud.toast("Can't refresh this circuit.")


func _on_vfb_refreshed(_key: String, ok: bool, message: String) -> void:
	hud.set_refresh_label("REFRESH LIVE")
	hud.toast(message if ok else "VFB refresh failed: " + message)
	hud.refresh_circuit_view()


func _on_update_available(version: String, _notes: String) -> void:
	hud.show_update_available(version)
	hud.toast("PetFly %s is available." % version)


# -- loop --------------------------------------------------------------------
func _process(delta: float) -> void:
	sim.tick(delta)
	terrarium.update_time(sim.zt, delta)
	fly.update(sim, delta)
	hud.update_hud(delta)

	_save_t += delta
	if _save_t >= SAVE_EVERY:
		_save_t = 0.0
		SaveManager.save_pet(sim)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _quit() -> void:
	SaveManager.save_pet(sim)
	get_tree().quit()
