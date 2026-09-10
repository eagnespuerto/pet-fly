class_name Terrarium
extends Node3D

## The scene the fly lives in: a Drosophila culture vial standing on a lawn.
##
## Everything here is built in code rather than hand-authored, so the geometry
## and the circadian lighting stay in one readable place. Lighting, sky and
## grass colour all track Zeitgeber Time, so the vial visibly moves through
## dawn, day, dusk and night.

const VIAL_RADIUS := 2.6
const VIAL_HEIGHT := 5.2
## The vial stands on a plinth, so everything inside it is offset upwards.
const PLINTH_HEIGHT := 0.66
const MEDIUM_TOP := PLINTH_HEIGHT + 0.42   # top surface of the food medium
const DISH_POS := Vector3(1.15, MEDIUM_TOP, 0.55)
const DISH_RADIUS := 0.46

# Key light colour through the fly's day.
const DAY_SUN := Color(1.00, 0.97, 0.90)
const DUSK_SUN := Color(1.00, 0.60, 0.36)
const NIGHT_SUN := Color(0.42, 0.52, 0.86)

var grass: Grass
var sun: DirectionalLight3D
var moonfill: OmniLight3D
var vial_wall: MeshInstance3D
var medium: MeshInstance3D
var dish: MeshInstance3D
var food_blob: MeshInstance3D

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _glass_mat: StandardMaterial3D
var _blob_mat: StandardMaterial3D
var _feed_glow := 0.0


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_vial()
	_build_colliders()
	_build_lights()


func _build_colliders() -> void:
	## Only what dropped food needs to hit: the medium surface and the vial
	## wall, so a pellet that drifts sideways stays inside the glass.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = VIAL_RADIUS - 0.04
	cyl.height = MEDIUM_TOP           # solid from the ground up to the surface
	floor_shape.shape = cyl
	floor_body.add_child(floor_shape)
	floor_body.position.y = MEDIUM_TOP * 0.5
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.12
	floor_body.physics_material_override = phys
	add_child(floor_body)

	# The wall is a ring of thin boxes: a hollow tube has no convex shape, and
	# this is cheaper and steadier than a trimesh for a handful of pellets.
	var wall_body := StaticBody3D.new()
	var segments := 16
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.12, VIAL_HEIGHT, TAU * VIAL_RADIUS / float(segments) * 1.15)
		cs.shape = box
		var xf := Transform3D()
		xf = xf.rotated(Vector3.UP, -a)
		xf.origin = Vector3(cos(a) * (VIAL_RADIUS + 0.05), VIAL_HEIGHT * 0.5,
				sin(a) * (VIAL_RADIUS + 0.05))
		cs.transform = xf
		wall_body.add_child(cs)
	add_child(wall_body)


static func daylight_fraction(zt: float) -> float:
	## 1.0 at midday, 0.0 deep at night, with smooth dawn and dusk ramps.
	if zt >= 1.0 and zt <= 10.5:
		return 1.0
	if zt < 1.0:
		return lerpf(0.35, 1.0, zt / 1.0)
	if zt <= 12.5:
		return lerpf(1.0, 0.18, (zt - 10.5) / 2.0)
	if zt <= 14.0:
		return lerpf(0.18, 0.0, (zt - 12.5) / 1.5)
	if zt >= 23.0:
		return lerpf(0.0, 0.35, (zt - 23.0) / 1.0)
	return 0.0


# -- construction ------------------------------------------------------------
func _build_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.30, 0.52, 0.83)
	_sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.90)
	_sky_mat.ground_bottom_color = Color(0.16, 0.20, 0.14)
	_sky_mat.ground_horizon_color = Color(0.58, 0.66, 0.62)
	_sky_mat.sun_angle_max = 12.0
	_sky_mat.sun_curve = 0.18

	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 4.0

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _build_ground() -> void:
	# Soil under the grass, so gaps between blades read as earth not void.
	var soil := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	soil.mesh = plane
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.16, 0.19, 0.11)
	soil_mat.roughness = 1.0
	soil.material_override = soil_mat
	soil.position.y = -0.02
	add_child(soil)

	grass = Grass.new()
	grass.name = "Grass"
	add_child(grass)

	# A stone plinth. It lifts the vial clear of the grass line, so the inside
	# of the glass reads against the sky instead of against blades behind it.
	var plinth := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = VIAL_RADIUS + 0.30
	pc.bottom_radius = VIAL_RADIUS + 0.62
	pc.height = PLINTH_HEIGHT
	pc.radial_segments = 56
	plinth.mesh = pc
	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = Color(0.38, 0.37, 0.34)
	plinth_mat.roughness = 0.92
	plinth.material_override = plinth_mat
	plinth.position.y = PLINTH_HEIGHT * 0.5
	add_child(plinth)


func _build_vial() -> void:
	# --- glass wall, open at both ends
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.74, 0.87, 0.95, 0.16)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass_mat.metallic = 0.15
	_glass_mat.roughness = 0.06
	_glass_mat.rim_enabled = true
	_glass_mat.rim = 0.85

	vial_wall = MeshInstance3D.new()
	var wall := CylinderMesh.new()
	wall.top_radius = VIAL_RADIUS
	wall.bottom_radius = VIAL_RADIUS
	wall.height = VIAL_HEIGHT
	wall.radial_segments = 64
	wall.cap_top = false
	wall.cap_bottom = false
	vial_wall.mesh = wall
	vial_wall.material_override = _glass_mat
	vial_wall.position.y = PLINTH_HEIGHT + VIAL_HEIGHT * 0.5
	vial_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vial_wall)

	# A thicker rim at the mouth reads as real glass.
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = VIAL_RADIUS - 0.02
	rim_mesh.outer_radius = VIAL_RADIUS + 0.09
	rim_mesh.rings = 48
	rim.mesh = rim_mesh
	rim.material_override = _glass_mat
	rim.position.y = PLINTH_HEIGHT + VIAL_HEIGHT
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)

	# --- food medium in the bottom
	medium = MeshInstance3D.new()
	var med := CylinderMesh.new()
	med.top_radius = VIAL_RADIUS - 0.04
	med.bottom_radius = VIAL_RADIUS - 0.04
	med.height = MEDIUM_TOP - PLINTH_HEIGHT
	med.radial_segments = 64
	medium.mesh = med
	var med_mat := StandardMaterial3D.new()
	med_mat.albedo_color = Color(0.46, 0.30, 0.16)
	med_mat.roughness = 0.72
	medium.material_override = med_mat
	medium.position.y = PLINTH_HEIGHT + (MEDIUM_TOP - PLINTH_HEIGHT) * 0.5
	add_child(medium)

	# --- food dish
	dish = MeshInstance3D.new()
	var d := CylinderMesh.new()
	d.top_radius = DISH_RADIUS
	d.bottom_radius = DISH_RADIUS * 0.82
	d.height = 0.07
	d.radial_segments = 32
	dish.mesh = d
	var dish_mat := StandardMaterial3D.new()
	dish_mat.albedo_color = Color(0.90, 0.86, 0.72)
	dish_mat.roughness = 0.45
	dish.material_override = dish_mat
	dish.position = DISH_POS + Vector3(0, 0.035, 0)
	add_child(dish)

	# --- the food itself, which grows as the fly is fed
	food_blob = MeshInstance3D.new()
	var blob := SphereMesh.new()
	blob.radius = 0.26
	blob.height = 0.30
	blob.radial_segments = 20
	blob.rings = 10
	food_blob.mesh = blob
	_blob_mat = StandardMaterial3D.new()
	_blob_mat.albedo_color = Color(0.93, 0.78, 0.31)
	_blob_mat.roughness = 0.35
	food_blob.material_override = _blob_mat
	food_blob.position = DISH_POS + Vector3(0, 0.07, 0)
	food_blob.scale = Vector3(1.0, 0.42, 1.0)
	add_child(food_blob)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = DAY_SUN
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-52, -38, 0)
	add_child(sun)

	# Warm fill inside the vial so the fly never turns into a silhouette.
	moonfill = OmniLight3D.new()
	moonfill.light_color = Color(1.0, 0.93, 0.82)
	moonfill.light_energy = 0.9
	moonfill.omni_range = 14.0
	moonfill.position = Vector3(2.6, 4.6, -3.2)
	add_child(moonfill)


# -- per-frame ---------------------------------------------------------------
func update_time(zt: float, delta: float) -> void:
	var light := daylight_fraction(zt)

	# The sun tracks an arc across the sky through the light phase.
	var elevation: float = lerpf(-14.0, -68.0, sin(clampf(zt / 12.0, 0.0, 1.0) * PI))
	sun.rotation_degrees = Vector3(elevation, -38.0 + zt * 4.0, 0.0)

	var sun_col: Color
	if light > 0.5:
		sun_col = DUSK_SUN.lerp(DAY_SUN, (light - 0.5) / 0.5)
	else:
		sun_col = NIGHT_SUN.lerp(DUSK_SUN, light / 0.5)
	sun.light_color = sun_col
	sun.light_energy = lerpf(0.20, 1.20, light)
	moonfill.light_energy = lerpf(0.35, 0.90, light)
	moonfill.light_color = Color(0.62, 0.72, 1.0).lerp(Color(1.0, 0.93, 0.82), light)

	# Sky follows the same curve, so night is blue rather than merely dark.
	_sky_mat.sky_top_color = Color(0.03, 0.05, 0.13).lerp(Color(0.30, 0.52, 0.83), light)
	_sky_mat.sky_horizon_color = Color(0.07, 0.09, 0.18).lerp(Color(0.72, 0.82, 0.90), light)
	_sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.06).lerp(Color(0.16, 0.20, 0.14), light)
	_sky_mat.ground_horizon_color = Color(0.05, 0.07, 0.12).lerp(Color(0.58, 0.66, 0.62), light)

	grass.set_daylight(light)
	_glass_mat.albedo_color.a = lerpf(0.10, 0.18, light)

	# Feeding glow on the dish fades out after a meal.
	if _feed_glow > 0.0:
		_feed_glow = maxf(0.0, _feed_glow - delta * 1.5)
		_blob_mat.emission_enabled = true
		_blob_mat.emission = _blob_mat.albedo_color
		_blob_mat.emission_energy_multiplier = _feed_glow * 1.6
	else:
		_blob_mat.emission_enabled = false


func set_food_colour(c: Color) -> void:
	_blob_mat.albedo_color = c


func set_food_level(v: float) -> void:
	## The blob in the dish shrinks as the fly eats through it.
	var s: float = lerpf(0.35, 1.15, clampf(v, 0.0, 1.0))
	food_blob.scale = Vector3(s, s * 0.42, s)


func flash_food() -> void:
	_feed_glow = 1.0
