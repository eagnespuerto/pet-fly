class_name Fly
extends Node3D

## The fly: model loading, behaviour state machine, and animation.
##
## The four bundled models are static single meshes with no rig, so nothing can
## be animated by bone. Instead the body is animated procedurally - velocity
## driven banking and pitch, hover bob, takeoff and landing flares, grooming
## and sleep breathing - and the wings are separate translucent cards that beat
## fast enough to read as blur. That works identically for all four models.

enum State { RESTING, WALKING, TAKEOFF, FLYING, LANDING, FEEDING, SLEEPING, GROOMING }

const MODELS := [
	{"key": "fly_kohyzazi_cc0", "author": "Kohyzazi", "licence": "CC0"},
	{"key": "fly_google_ccby", "author": "Poly by Google", "licence": "CC-BY 3.0"},
	{"key": "fly_aronia_ccby", "author": "AroniaStudios", "licence": "CC-BY 3.0"},
	{"key": "fly_jeremy_ccby", "author": "jeremy", "licence": "CC-BY 3.0"},
]

const BODY_LENGTH := 0.95          # normalised, in vial units
## The bundled models are all authored pointing down +X; Godot's forward is -Z.
const MODEL_YAW_OFFSET := 90.0

const MEDIUM_TOP := Terrarium.MEDIUM_TOP
const VIAL_RADIUS := Terrarium.VIAL_RADIUS
const VIAL_HEIGHT := Terrarium.VIAL_HEIGHT

const MAX_SPEED_FLY := 3.4
const MAX_SPEED_WALK := 0.55
const ACCEL_FLY := 9.0
const ACCEL_WALK := 2.2

var model_key := MODELS[0]["key"]
var state: State = State.RESTING

var _pivot: Node3D          # carries position; children carry orientation
var _tilt: Node3D           # roll/pitch, so bob does not fight orientation
var _body: Node3D           # the loaded model
var _wing_l: MeshInstance3D
var _wing_r: MeshInstance3D
var _wing_mat: StandardMaterial3D

var _vel := Vector3.ZERO
var _target := Vector3(0, MEDIUM_TOP + 1.4, 0)
var _heading := 0.0
var _heading_rate := 0.0
var _t := 0.0
var _state_t := 0.0
var _retarget_in := 0.0
var _groom_in := 6.0
var _wing_phase := 0.0
var _rng := RandomNumberGenerator.new()

var _feed_anchor := Terrarium.DISH_POS


func _ready() -> void:
	_rng.randomize()
	_pivot = Node3D.new()
	add_child(_pivot)
	_tilt = Node3D.new()
	_pivot.add_child(_tilt)
	_build_wings()
	set_model(model_key)
	_pivot.position = Vector3(0, MEDIUM_TOP, 0)


# -- model -------------------------------------------------------------------
func set_model(key: String) -> String:
	var found := false
	for m in MODELS:
		if m["key"] == key:
			found = true
			break
	if not found:
		key = MODELS[0]["key"]

	if _body:
		_body.queue_free()
		_body = null

	var path := "res://assets/models/%s.glb" % key
	var packed: PackedScene = load(path)
	if packed:
		_body = packed.instantiate()
		_tilt.add_child(_body)
		_normalise(_body)
	else:
		push_warning("PetFly: could not load model %s" % path)
	model_key = key
	_place_wings()
	return key


func model_info() -> Dictionary:
	for m in MODELS:
		if m["key"] == model_key:
			return m
	return MODELS[0]


func _normalise(node: Node3D) -> void:
	## Scale any model to the same body length and sit it on its own origin.
	var aabb := _merged_aabb(node)
	if aabb.size.length() <= 0.0:
		return
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest <= 0.0:
		return
	var s := BODY_LENGTH / longest
	node.scale = Vector3(s, s, s)
	# Re-measure in local space and centre horizontally, resting on y = 0.
	var centre := aabb.position + aabb.size * 0.5
	node.position = Vector3(-centre.x * s, -aabb.position.y * s, -centre.z * s)


func _merged_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in _all_nodes(node):
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if mi.mesh == null:
				continue
			var a := mi.mesh.get_aabb()
			# Fold in the child's own transform relative to the model root.
			var xf := mi.transform
			var p := node.get_path_to(mi)
			a = xf * a
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


func _all_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out


# -- wings -------------------------------------------------------------------
func _build_wings() -> void:
	_wing_mat = StandardMaterial3D.new()
	_wing_mat.albedo_color = Color(0.80, 0.88, 0.95, 0.30)
	_wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wing_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	_wing_l = _make_wing()
	_wing_r = _make_wing()
	_tilt.add_child(_wing_l)
	_tilt.add_child(_wing_r)


func _make_wing() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()          # a squashed sphere reads as a wing blur
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 12
	m.rings = 6
	mi.mesh = m
	mi.material_override = _wing_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _place_wings() -> void:
	var w := BODY_LENGTH * 0.62
	var scale_v := Vector3(w * 0.92, w * 0.06, w * 0.42)
	_wing_l.scale = scale_v
	_wing_r.scale = scale_v
	var y := BODY_LENGTH * 0.42
	var back := BODY_LENGTH * 0.08
	_wing_l.position = Vector3(-back, y, -BODY_LENGTH * 0.22)
	_wing_r.position = Vector3(-back, y, BODY_LENGTH * 0.22)


# -- behaviour ---------------------------------------------------------------
func update(sim: Sim, delta: float) -> void:
	_t += delta
	_state_t += delta
	_decide(sim, delta)
	_steer(sim, delta)
	_animate(sim, delta)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	_state_t = 0.0


func _distance_to_target() -> float:
	## While walking the fly is pinned to the surface of the medium, so a target
	## even slightly above it could never be "reached" on a straight 3D
	## distance. On the ground, only horizontal distance counts.
	var grounded := state in [State.RESTING, State.WALKING, State.FEEDING,
			State.GROOMING, State.SLEEPING]
	if grounded:
		return Vector2(_target.x - _pivot.position.x,
				_target.z - _pivot.position.z).length()
	return _pivot.position.distance_to(_target)


func _decide(sim: Sim, delta: float) -> void:
	if sim.asleep:
		_target = Vector3(-0.75, MEDIUM_TOP, -0.5)
		if _pivot.position.distance_to(_target) < 0.12:
			_set_state(State.SLEEPING)
		elif state != State.SLEEPING:
			_set_state(State.LANDING if _pivot.position.y > MEDIUM_TOP + 0.25 else State.WALKING)
		return

	if state == State.SLEEPING:
		_set_state(State.TAKEOFF)

	# Feeding takes priority when hungry and near the dish.
	var hungry := sim.fullness < 0.45
	if state == State.FEEDING:
		if _state_t > 3.2 or not hungry:
			_set_state(State.TAKEOFF)
		return

	_retarget_in -= delta
	if _retarget_in <= 0.0:
		_retarget_in = lerpf(2.8, 0.8, sim.activity) * _rng.randf_range(0.7, 1.4)
		if hungry and _rng.randf() < 0.6:
			_target = _feed_anchor + Vector3(
					_rng.randf_range(-0.2, 0.2), 0.14, _rng.randf_range(-0.2, 0.2))
		else:
			var r := _rng.randf_range(0.0, VIAL_RADIUS - 0.6)
			var a := _rng.randf() * TAU
			var airborne := _rng.randf() < 0.35 + 0.5 * sim.activity
			var y := (_rng.randf_range(MEDIUM_TOP + 0.8, VIAL_HEIGHT - 1.0) if airborne
					else MEDIUM_TOP + 0.02)
			_target = Vector3(cos(a) * r, y, sin(a) * r)

	var d := _distance_to_target()
	var near_dish := Vector2(_target.x - _feed_anchor.x, _target.z - _feed_anchor.z).length() < 0.45

	match state:
		State.RESTING, State.WALKING, State.GROOMING:
			if _target.y > MEDIUM_TOP + 0.35:
				_set_state(State.TAKEOFF)
			elif d < 0.10:
				if near_dish and hungry:
					_set_state(State.FEEDING)
				else:
					# Flies groom constantly when idle.
					_groom_in -= delta
					if _groom_in <= 0.0:
						_groom_in = _rng.randf_range(5.0, 13.0)
						_set_state(State.GROOMING)
					elif state != State.GROOMING:
						_set_state(State.RESTING)
			else:
				if state != State.GROOMING:
					_set_state(State.WALKING)
			if state == State.GROOMING and _state_t > _rng.randf_range(1.4, 2.6):
				_set_state(State.RESTING)
		State.TAKEOFF:
			if _state_t > 0.42 or _pivot.position.y > MEDIUM_TOP + 0.6:
				_set_state(State.FLYING)
		State.FLYING:
			if _target.y <= MEDIUM_TOP + 0.35 and d < 0.9:
				_set_state(State.LANDING)
		State.LANDING:
			if _pivot.position.y <= MEDIUM_TOP + 0.06:
				if near_dish and hungry:
					_set_state(State.FEEDING)
				else:
					_set_state(State.RESTING)


func _steer(sim: Sim, delta: float) -> void:
	var pos := _pivot.position
	var to_target := _target - pos
	var airborne := state in [State.TAKEOFF, State.FLYING, State.LANDING]

	var max_speed: float
	var accel: float
	match state:
		State.SLEEPING:
			max_speed = 0.0
			accel = 6.0
		State.FEEDING, State.GROOMING, State.RESTING:
			max_speed = 0.06
			accel = 3.0
		State.WALKING:
			max_speed = lerpf(0.22, MAX_SPEED_WALK, sim.activity)
			accel = ACCEL_WALK
		State.TAKEOFF:
			max_speed = 1.9
			accel = 12.0
		State.LANDING:
			max_speed = 1.2
			accel = 7.0
		_:
			max_speed = lerpf(1.2, MAX_SPEED_FLY, sim.activity)
			accel = ACCEL_FLY

	var desired := Vector3.ZERO
	if to_target.length() > 0.001:
		desired = to_target.normalized() * max_speed
		# Ease off on approach so the fly settles instead of overshooting.
		var slow := clampf(to_target.length() / 0.6, 0.0, 1.0)
		desired *= lerpf(0.15, 1.0, slow)
	if state == State.TAKEOFF:
		desired.y = maxf(desired.y, 1.4)

	_vel = _vel.move_toward(desired, accel * delta)
	if not airborne:
		# Walking sticks to the medium surface.
		_vel.y = 0.0
		pos.y = MEDIUM_TOP
	pos += _vel * delta

	# Keep the fly inside the vial.
	var radial := Vector2(pos.x, pos.z)
	if radial.length() > VIAL_RADIUS - 0.28:
		radial = radial.normalized() * (VIAL_RADIUS - 0.28)
		pos.x = radial.x
		pos.z = radial.y
		_vel.x *= 0.4
		_vel.z *= 0.4
	pos.y = clampf(pos.y, MEDIUM_TOP, VIAL_HEIGHT - 0.5)
	_pivot.position = pos

	# Face the direction of travel.
	var flat := Vector2(_vel.x, _vel.z)
	if flat.length() > 0.04:
		var want := rad_to_deg(atan2(flat.x, flat.y))
		var d_h := wrapf(want - _heading, -180.0, 180.0)
		var turn := d_h * minf(1.0, delta * 7.0)
		_heading += turn
		_heading_rate = lerpf(_heading_rate, turn / maxf(delta, 0.0001), 0.25)
	else:
		_heading_rate = lerpf(_heading_rate, 0.0, minf(1.0, delta * 4.0))


func _animate(sim: Sim, delta: float) -> void:
	var airborne := state in [State.TAKEOFF, State.FLYING, State.LANDING]
	var speed := _vel.length()

	# --- wingbeat
	var beat_hz := 0.0
	match state:
		State.SLEEPING:
			beat_hz = 0.0
		State.TAKEOFF:
			beat_hz = 34.0
		State.FLYING:
			beat_hz = lerpf(20.0, 30.0, clampf(speed / MAX_SPEED_FLY, 0.0, 1.0))
		State.LANDING:
			beat_hz = 22.0
		State.GROOMING:
			beat_hz = 4.0
		_:
			beat_hz = 0.0
	_wing_phase += beat_hz * delta * TAU
	var beating := beat_hz > 0.5
	_wing_l.visible = beating
	_wing_r.visible = beating
	if beating:
		var stroke := sin(_wing_phase)
		# Faster beats read as a wider, fainter blur.
		var blur := clampf(beat_hz / 34.0, 0.0, 1.0)
		_wing_mat.albedo_color.a = lerpf(0.42, 0.20, blur)
		var sweep: float = deg_to_rad(lerpf(18.0, 46.0, blur)) * stroke
		_wing_l.rotation = Vector3(sweep, 0.0, deg_to_rad(14.0) + sweep * 0.35)
		_wing_r.rotation = Vector3(-sweep, 0.0, deg_to_rad(-14.0) - sweep * 0.35)

	# --- body bob
	var bob := 0.0
	if state == State.SLEEPING:
		bob = sin(_t * 1.1) * 0.006                     # slow breathing
	elif airborne:
		bob = sin(_t * lerpf(9.0, 17.0, sim.activity)) * 0.045
	elif state == State.WALKING:
		bob = absf(sin(_t * 11.0)) * 0.012              # gait bounce
	elif state == State.FEEDING:
		bob = -absf(sin(_t * 5.5)) * 0.030              # proboscis dips
	elif state == State.GROOMING:
		bob = sin(_t * 8.0) * 0.010

	# --- roll and pitch
	var roll := 0.0
	var pitch := 0.0
	match state:
		State.TAKEOFF:
			pitch = deg_to_rad(-18.0) * (1.0 - _state_t / 0.42)
		State.LANDING:
			pitch = deg_to_rad(16.0)                     # flare, nose up
		State.FLYING:
			# Bank into turns, and pitch down with forward speed.
			roll = deg_to_rad(clampf(-_heading_rate * 0.16, -34.0, 34.0))
			pitch = deg_to_rad(-6.0 - 9.0 * clampf(speed / MAX_SPEED_FLY, 0.0, 1.0))
		State.SLEEPING:
			pitch = deg_to_rad(-4.0)
		State.FEEDING:
			pitch = deg_to_rad(22.0)                     # head down into the food
		State.GROOMING:
			roll = deg_to_rad(9.0) * sin(_t * 7.0)
			pitch = deg_to_rad(6.0) * sin(_t * 5.0)
		State.WALKING:
			roll = deg_to_rad(4.0) * sin(_t * 5.5)       # slight waddle

	_pivot.rotation_degrees = Vector3(0, _heading + MODEL_YAW_OFFSET, 0)
	_tilt.position = Vector3(0, bob, 0)
	_tilt.rotation = _tilt.rotation.lerp(Vector3(pitch, 0.0, roll),
			clampf(delta * 9.0, 0.0, 1.0))

	# Sleeping flies fold down a little.
	var squash: float = 1.0 if state != State.SLEEPING else 0.94
	_tilt.scale = _tilt.scale.lerp(Vector3(1.0, squash, 1.0), clampf(delta * 4.0, 0.0, 1.0))


# -- cues from the game ------------------------------------------------------
func go_feed(anchor: Vector3) -> void:
	_feed_anchor = anchor
	# Sit the target on the medium: a walking fly cannot climb to reach it.
	_target = Vector3(anchor.x, MEDIUM_TOP + 0.02, anchor.z)
	_retarget_in = 2.5
	if state in [State.RESTING, State.WALKING, State.GROOMING]:
		_set_state(State.WALKING)


func recoil() -> void:
	## Bitter rejection: a sharp backward hop.
	_vel += Vector3(-cos(deg_to_rad(_heading)), 0.9, -sin(deg_to_rad(_heading))) * 1.4
	_retarget_in = 0.5


func position_world() -> Vector3:
	return _pivot.position
